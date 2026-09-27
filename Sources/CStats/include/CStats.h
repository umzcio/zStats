#ifndef CSTATS_H
#define CSTATS_H
#include <stdint.h>
typedef struct {
    int32_t pid, parent;
    uint32_t uid;
    uint64_t started, cpu_ns, memory, read_bytes, write_bytes, energy_nj;
    int io_valid, cpu_valid, memory_valid, energy_valid;
    char name[256], path[4096];
} ZSProcess;
typedef struct {
    uint64_t user_ticks, system_ticks, idle_ticks, nice_ticks;
    double memory_total, memory_used, memory_app, memory_wired, memory_compressed, memory_cached, swap;
    int pressure;
    uint64_t net_in, net_out, disk_read, disk_write;
    int net_valid, disk_valid;
    char interface[32];
    double gpu, gpu_memory, battery, battery_minutes, battery_health, battery_cycles, battery_watts, battery_temperature;
    int charging;
} ZSSystem;
typedef struct {
    char name[32];
    uint64_t received, sent;
} ZSInterface;
int zs_network(ZSInterface **output);
int zs_processes(ZSProcess **output);
void zs_free(void *pointer);
void zs_system(ZSSystem *output);
uint64_t zs_process_start(int32_t pid);
int zs_process_cwd(int32_t pid, char *path, int capacity);
int zs_terminate(int32_t pid, uint64_t expected_start, int force);
// Read-only SMC transport. The caller serializes access and closes its connection.
uint32_t zs_smc_open(void);
void zs_smc_close(uint32_t connection);
int zs_smc_key(uint32_t connection, uint32_t index, char key[5]);
int zs_smc_read(uint32_t connection, const char *key, char type[5], uint8_t bytes[32]);
#endif
