#include "CStats.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>

void zs_free(void *p) { free(p); }
int zs_process_cwd(int32_t pid, char *path, int capacity) {
    struct proc_vnodepathinfo info = {0};
    if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, sizeof(info)) != sizeof(info)) return 0;
    strlcpy(path, info.pvi_cdir.vip_path, capacity); return 1;
}
uint64_t zs_process_start(int32_t pid) {
    struct proc_bsdinfo info = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) return 0;
    return info.pbi_start_tvsec * 1000000ULL + info.pbi_start_tvusec;
}
int zs_terminate(int32_t pid, uint64_t expected_start, int force) {
    if (pid <= 1 || pid == getpid() || expected_start == 0 || zs_process_start(pid) != expected_start) return ESRCH;
    return kill(pid, force ? SIGKILL : SIGTERM) == 0 ? 0 : errno;
}
int zs_processes(ZSProcess **output) {
    *output = NULL;
    int bytes = proc_listallpids(NULL, 0);
    if (bytes <= 0) return 0;
    int capacity = bytes + 512;
    pid_t *pids = calloc(capacity, sizeof(pid_t));
    if (!pids) return 0;
    int count = proc_listallpids(pids, capacity * sizeof(pid_t));
    if (count > capacity) count = capacity;
    ZSProcess *rows = calloc(capacity, sizeof(ZSProcess));
    if (!rows) { free(pids); return 0; }
    int used = 0;
    for (int i = 0; i < count; i++) {
        if (pids[i] <= 0) continue;
        struct proc_bsdinfo b = {0};
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &b, sizeof(b)) != sizeof(b)) continue;
        ZSProcess *r = &rows[used++];
        r->pid = pids[i]; r->parent = b.pbi_ppid; r->uid = b.pbi_uid;
        r->started = b.pbi_start_tvsec * 1000000ULL + b.pbi_start_tvusec;
        strlcpy(r->name, b.pbi_name[0] ? b.pbi_name : b.pbi_comm, sizeof(r->name));
        proc_pidpath(pids[i], r->path, sizeof(r->path));
        struct proc_taskinfo task = {0};
        if (proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &task, sizeof(task)) == sizeof(task)) {
            r->cpu_ns = task.pti_total_user + task.pti_total_system; r->cpu_valid = 1;
            r->memory = task.pti_resident_size; r->memory_valid = 1;
        }
        struct rusage_info_v6 usage = {0};
        if (proc_pid_rusage(pids[i], RUSAGE_INFO_V6, (rusage_info_t *)&usage) == 0) {
            r->energy_nj = usage.ri_energy_nj; r->energy_valid = usage.ri_energy_nj > 0;
            r->memory = usage.ri_phys_footprint; r->memory_valid = 1;
            r->read_bytes = usage.ri_diskio_bytesread; r->write_bytes = usage.ri_diskio_byteswritten; r->io_valid = 1;
        } else {
            struct rusage_info_v2 legacy = {0};
            if (proc_pid_rusage(pids[i], RUSAGE_INFO_V2, (rusage_info_t *)&legacy) == 0) {
                r->memory = legacy.ri_phys_footprint; r->memory_valid = 1;
                r->read_bytes = legacy.ri_diskio_bytesread; r->write_bytes = legacy.ri_diskio_byteswritten; r->io_valid = 1;
            }
        }
    }
    free(pids); *output = rows; return used;
}
static double number(CFDictionaryRef dict, CFStringRef key) {
    if (!dict) return NAN;
    CFTypeRef v = CFDictionaryGetValue(dict, key);
    double value;
    return v && CFGetTypeID(v) == CFNumberGetTypeID() && CFNumberGetValue(v, kCFNumberDoubleType, &value) ? value : NAN;
}
static int unsigned_number(CFDictionaryRef dict, CFStringRef key, uint64_t *output) {
    if (!dict) return 0;
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    int64_t signed_value = 0;
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID() ||
        !CFNumberGetValue(value, kCFNumberSInt64Type, &signed_value) || signed_value < 0) return 0;
    *output = (uint64_t)signed_value;
    return 1;
}
static CFDictionaryRef properties(io_registry_entry_t entry) {
    CFMutableDictionaryRef result = NULL;
    IORegistryEntryCreateCFProperties(entry, &result, kCFAllocatorDefault, 0);
    return result;
}
int zs_network(ZSInterface **output) {
    *output = NULL;
    int mib[] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t length = 0;
    if (sysctl(mib, 6, NULL, &length, NULL, 0) != 0 || length == 0) return 0;
    char *buffer = malloc(length);
    if (!buffer) return 0;
    if (sysctl(mib, 6, buffer, &length, NULL, 0) != 0) { free(buffer); return 0; }
    ZSInterface *rows = calloc(128, sizeof(ZSInterface));
    if (!rows) { free(buffer); return 0; }
    int count = 0;
    for (char *cursor = buffer; cursor + sizeof(struct if_msghdr) <= buffer + length;) {
        struct if_msghdr *header = (struct if_msghdr *)cursor;
        if (header->ifm_msglen == 0 || cursor + header->ifm_msglen > buffer + length) break;
        if (header->ifm_type == RTM_IFINFO2 && header->ifm_msglen >= sizeof(struct if_msghdr2) && count < 128) {
            struct if_msghdr2 *info = (struct if_msghdr2 *)cursor;
            char name[IFNAMSIZ] = {0};
            if (if_indextoname(info->ifm_index, name) && strncmp(name, "en", 2) == 0 && (info->ifm_flags & IFF_UP) && !(info->ifm_flags & IFF_LOOPBACK)) {
                strlcpy(rows[count].name, name, sizeof(rows[count].name));
                rows[count].received = info->ifm_data.ifi_ibytes; rows[count].sent = info->ifm_data.ifi_obytes; count++;
            }
        }
        cursor += header->ifm_msglen;
    }
    free(buffer); *output = rows; return count;
}
int zs_disks(ZSDisk **output) {
    *output = NULL;
    io_iterator_t iterator = IO_OBJECT_NULL;
    CFMutableDictionaryRef matching = IOServiceMatching("IOBlockStorageDriver");
    if (!matching || IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS) return -1;

    ZSDisk *rows = NULL;
    int count = 0, capacity = 0, failed = 0;
    io_object_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        uint64_t registry_id = 0;
        if (IORegistryEntryGetRegistryEntryID(entry, &registry_id) != KERN_SUCCESS) {
            IOObjectRelease(entry);
            continue;
        }
        if (count == capacity) {
            int next_capacity = capacity == 0 ? 8 : capacity * 2;
            ZSDisk *next = realloc(rows, (size_t)next_capacity * sizeof(ZSDisk));
            if (!next) {
                IOObjectRelease(entry);
                failed = 1;
                break;
            }
            rows = next;
            capacity = next_capacity;
        }
        ZSDisk *row = &rows[count++];
        memset(row, 0, sizeof(*row));
        row->registry_id = registry_id;
        CFDictionaryRef props = properties(entry);
        CFTypeRef stats = props ? CFDictionaryGetValue(props, CFSTR("Statistics")) : NULL;
        if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID() &&
            unsigned_number((CFDictionaryRef)stats, CFSTR("Bytes (Read)"), &row->read_bytes) &&
            unsigned_number((CFDictionaryRef)stats, CFSTR("Bytes (Write)"), &row->write_bytes)) {
            row->stats_valid = 1;
        }
        if (props) CFRelease(props);
        IOObjectRelease(entry);
    }
    if (!IOIteratorIsValid(iterator)) failed = 1;
    IOObjectRelease(iterator);
    if (failed) {
        free(rows);
        return -1;
    }
    *output = rows;
    return count;
}
void zs_system(ZSSystem *r) {
    memset(r, 0, sizeof(*r));
    r->gpu = r->gpu_memory = r->battery = r->battery_minutes = r->battery_health = r->battery_cycles = r->battery_watts = r->battery_temperature = NAN;
    host_cpu_load_info_data_t cpu;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    mach_port_t host = mach_host_self();
    if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&cpu, &count) == KERN_SUCCESS) {
        r->user_ticks = cpu.cpu_ticks[CPU_STATE_USER]; r->system_ticks = cpu.cpu_ticks[CPU_STATE_SYSTEM];
        r->idle_ticks = cpu.cpu_ticks[CPU_STATE_IDLE]; r->nice_ticks = cpu.cpu_ticks[CPU_STATE_NICE];
        r->cpu_valid = 1;
    }
    uint64_t total = 0; size_t len = sizeof(total);
    if (sysctlbyname("hw.memsize", &total, &len, NULL, 0) == 0 && len == sizeof(total) && total > 0) {
        r->memory_total = total; r->memory_total_valid = 1;
    }
    vm_statistics64_data_t vm; count = HOST_VM_INFO64_COUNT;
    vm_size_t page = 0;
    if (host_page_size(host, &page) == KERN_SUCCESS && page > 0 &&
        host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        r->memory_wired = (double)vm.wire_count * page;
        r->memory_compressed = (double)vm.compressor_page_count * page;
        r->memory_app = fmax(0, ((double)vm.internal_page_count - vm.purgeable_count) * page);
        r->memory_cached = ((double)vm.external_page_count + vm.purgeable_count) * page;
        double used = r->memory_app + r->memory_wired + r->memory_compressed;
        r->memory_used = r->memory_total_valid ? fmin(total, used) : used;
        r->memory_valid = 1;
    }
    mach_port_deallocate(mach_task_self(), host);
    struct xsw_usage swap; len = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &len, NULL, 0) == 0 && len == sizeof(swap)) {
        r->swap = swap.xsu_used; r->swap_valid = 1;
    }
    int pressure = 0; len = sizeof(pressure);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &len, NULL, 0) == 0 && len == sizeof(pressure)) {
        r->pressure = pressure; r->pressure_valid = 1;
    }
    io_iterator_t iterator;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS) {
        io_object_t entry;
        while ((entry = IOIteratorNext(iterator))) {
            CFDictionaryRef props = properties(entry);
            CFTypeRef stats = props ? CFDictionaryGetValue(props, CFSTR("PerformanceStatistics")) : NULL;
            if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
                double gpu = number(stats, CFSTR("Device Utilization %"));
                if (!isfinite(gpu)) gpu = number(stats, CFSTR("GPU Activity(%)"));
                if (isfinite(gpu) && gpu >= 0 && gpu <= 100) r->gpu = isfinite(r->gpu) ? fmax(r->gpu, gpu) : gpu;
                double mem = number(stats, CFSTR("In use system memory"));
                if (isfinite(mem)) r->gpu_memory = mem;
            }
            if (props) CFRelease(props); IOObjectRelease(entry);
        }
        IOObjectRelease(iterator);
    }
    io_service_t battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (battery) {
        CFDictionaryRef props = properties(battery);
        double current = number(props, CFSTR("CurrentCapacity")), maximum = number(props, CFSTR("MaxCapacity"));
        if (isfinite(current) && maximum > 0) r->battery = fmin(100, current / maximum * 100);
        double rawMax = number(props, CFSTR("AppleRawMaxCapacity")), design = number(props, CFSTR("DesignCapacity"));
        if (!isfinite(rawMax)) rawMax = maximum;
        if (design > 0 && rawMax > 100) r->battery_health = fmin(100, rawMax / design * 100);
        r->battery_cycles = number(props, CFSTR("CycleCount"));
        double minutes = number(props, CFSTR("TimeRemaining"));
        if (minutes >= 0 && minutes < 65535) r->battery_minutes = minutes;
        double amps = number(props, CFSTR("Amperage")), volts = number(props, CFSTR("Voltage"));
        if (isfinite(amps) && amps > 2147483647.0) amps -= 4294967296.0;
        if (isfinite(amps) && isfinite(volts)) r->battery_watts = fabs(amps * volts / 1000000.0);
        double temperature = number(props, CFSTR("Temperature"));
        if (temperature > 0 && temperature < 10000) r->battery_temperature = temperature / 100.0;
        if (props) { r->charging = CFDictionaryGetValue(props, CFSTR("ExternalConnected")) == kCFBooleanTrue; CFRelease(props); }
        IOObjectRelease(battery);
    }
}
