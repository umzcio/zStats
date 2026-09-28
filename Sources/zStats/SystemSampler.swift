import Foundation
import StatsCore
import CStats

final class SystemSampler: @unchecked Sendable {
    // Owned exclusively by the store's sampling task.
    private var previousProcesses: [ProcessIdentity: ZSProcess] = [:]
    private var previousTime: TimeInterval?
    private var systemCounterTracker = SystemCounterTracker()
    private var networkTracker = NetworkTracker()
    private var diskTracker = DiskTracker()
    private let telemetry = ProcessTelemetrySampler()
    private let sensors = SensorSampler()
    private let appNames = AppNameResolver()
    private var lastProjectDiscovery = -Double.infinity
    private var lastHistorySave = -Double.infinity
    private var projects: [ProjectReading] = []
    private let historyPersistence: HistoryPersistence

    init(historyURL: URL? = nil) {
        let url = historyURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("zStats/history.json")
        historyPersistence = HistoryPersistence(url: url)
    }

    func sample(enabled: Set<String> = Set(MonitorPreferences.monitorOrder), sensorMonitoring: Bool = true) -> (SystemSnapshot, [ProjectReading], HistoryArchive, String?) {
        let time = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTime.map { time - $0 } ?? 0
        var raw = ZSSystem(); zs_system(&raw)
        var result = SystemSnapshot()
        let cpuCounters = SystemCPUCounters(
            valid: raw.cpu_valid != 0,
            user: raw.user_ticks,
            system: raw.system_ticks,
            idle: raw.idle_ticks,
            nice: raw.nice_ticks
        )
        if let usage = systemCounterTracker.sample(cpuCounters) {
            result.userCPU = usage.user; result.systemCPU = usage.system; result.cpu = usage.total
        }
        let memory = SystemMemoryReading(
            total: raw.memory_total, totalValid: raw.memory_total_valid != 0,
            used: raw.memory_used, app: raw.memory_app, wired: raw.memory_wired,
            compressed: raw.memory_compressed, cached: raw.memory_cached, vmValid: raw.memory_valid != 0,
            swap: raw.swap, swapValid: raw.swap_valid != 0,
            pressure: Int(raw.pressure), pressureValid: raw.pressure_valid != 0
        )
        if let total = memory.total { result.memoryTotal = total }
        result.memoryUsed = memory.used; result.memoryApp = memory.app; result.memoryWired = memory.wired
        result.memoryCompressed = memory.compressed; result.memoryCached = memory.cached
        result.swap = memory.swap; result.pressure = memory.pressure
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            result.diskTotal = (attrs[.systemSize] as? NSNumber)?.doubleValue ?? 0
            result.diskFree = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        }
        var loads = [Double](repeating: 0, count: 3); getloadavg(&loads, 3); result.load = loads[0]
        var networkPointer: UnsafeMutablePointer<ZSInterface>?
        let networkCount = zs_network(&networkPointer)
        var counters: [String: NetworkCounters] = [:]
        if let networkPointer {
            for index in 0..<Int(networkCount) {
                let row = networkPointer[index]
                counters[cString(row.name)] = .init(received: row.received, sent: row.sent)
            }
            zs_free(networkPointer)
        }
        let network = networkTracker.sample(counters, time: time)
        result.download = network.download; result.upload = network.upload
        result.received = network.received; result.sent = network.sent
        result.interface = counters.keys.sorted().joined(separator: ", ")
        if result.interface.isEmpty { result.interface = "—" }
        var diskPointer: UnsafeMutablePointer<ZSDisk>?
        let diskCount = zs_disks(&diskPointer)
        var diskSamples: [DiskDeviceSample]?
        if diskCount >= 0 {
            diskSamples = []
            if let diskPointer {
                for index in 0..<Int(diskCount) {
                    let disk = diskPointer[index]
                    let valid = disk.stats_valid != 0
                    diskSamples?.append(.init(id: disk.registry_id, read: valid ? disk.read_bytes : nil, write: valid ? disk.write_bytes : nil))
                }
            }
        }
        if let diskPointer { zs_free(diskPointer) }
        let disk = diskTracker.sample(diskSamples, time: time)
        result.diskRead = disk.read; result.diskWrite = disk.write
        result.gpu = finite(raw.gpu); result.gpuMemory = finite(raw.gpu_memory)
        result.battery = finite(raw.battery); result.charging = raw.charging != 0
        result.batteryMinutes = finite(raw.battery_minutes); result.batteryHealth = finite(raw.battery_health)
        result.batteryCycles = finite(raw.battery_cycles); result.batteryWatts = finite(raw.battery_watts)
        result.batteryTemperature = finite(raw.battery_temperature)
        if sensorMonitoring { result.sensors = sensors.sample() } else { sensors.reset() }
        var pointer: UnsafeMutablePointer<ZSProcess>?
        let count = zs_processes(&pointer)
        var processRows: [ProcessReading] = []
        var next: [ProcessIdentity: ZSProcess] = [:]
        if let pointer {
            for index in 0..<Int(count) {
                let p = pointer[index]
                let identity = ProcessIdentity(pid: p.pid, started: p.started)
                let old = previousProcesses[identity]
                let cpu = p.cpu_valid != 0 ? CounterRate.rate(current: p.cpu_ns, previous: old.flatMap { $0.cpu_valid != 0 ? $0.cpu_ns : nil }, seconds: elapsed).map { $0 / 1e9 * 100 } : nil
                let read = p.io_valid != 0 ? CounterRate.rate(current: p.read_bytes, previous: old.flatMap { $0.io_valid != 0 ? $0.read_bytes : nil }, seconds: elapsed) : nil
                let write = p.io_valid != 0 ? CounterRate.rate(current: p.write_bytes, previous: old.flatMap { $0.io_valid != 0 ? $0.write_bytes : nil }, seconds: elapsed) : nil
                let watts = p.energy_valid != 0 ? CounterRate.rate(current: p.energy_nj, previous: old.flatMap { $0.energy_valid != 0 ? $0.energy_nj : nil }, seconds: elapsed).map { $0 / 1e9 } : nil
                processRows.append(.init(pid: p.pid, parentPID: p.parent, name: cString(p.name), path: cString(p.path), memory: p.memory_valid != 0 ? Double(p.memory) : nil, cpu: cpu, readRate: read, writeRate: write, cpuWatts: watts, started: p.started, uid: p.uid))
                next[identity] = p
            }
            zs_free(pointer)
        }
        let attributed = telemetry.sample(&processRows, networkEnabled: enabled.contains("Network"), gpuEnabled: enabled.contains("GPU"))
        result.networkAppsAvailable = attributed.network; result.gpuAppsAvailable = attributed.gpu
        result.powerAppsAvailable = processRows.contains { $0.cpuWatts != nil }
        result.apps = ProcessGrouper.group(processRows).map { app in
            var named = app; named.name = appNames.name(for: app); return named
        }
        if !enabled.contains("Projects") { projects = []; lastProjectDiscovery = -Double.infinity }
        else if time - lastProjectDiscovery >= 20 { projects = discoverProjects(processes: processRows); lastProjectDiscovery = time }
        else {
            let current = Dictionary(processRows.map { ($0.identity, $0) }, uniquingKeysWith: { a, _ in a })
            projects = projects.compactMap { project in
                var p = project; p.processes = p.processes.compactMap { current[$0.identity] }
                return p.processes.isEmpty ? nil : p
            }
        }
        historyPersistence.record(HistoryPoint(result))
        if time - lastHistorySave >= 60 { historyPersistence.save(); lastHistorySave = time }
        previousProcesses = next; previousTime = time
        return (result, projects, historyPersistence.archive, historyPersistence.errorMessage)
    }

    private func discoverProjects(processes: [ProcessReading]) -> [ProjectReading] {
        let command = Process(); command.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        command.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcfn"]
        let pipe = Pipe(); command.standardOutput = pipe; command.standardError = FileHandle.nullDevice
        do { try command.run() } catch { return [] }
        let timeout = DispatchWorkItem { if command.isRunning { command.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        command.waitUntilExit(); timeout.cancel()
        let discovered = ProjectParser.parse(String(data: data, encoding: .utf8) ?? "")
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var groups: [String: ProjectReading] = [:]
        for var project in discovered {
            guard let process = byPID[project.pid], process.uid == getuid() else { continue }
            var path = [CChar](repeating: 0, count: 4096)
            if zs_process_cwd(project.pid, &path, Int32(path.count)) != 0 { project.directory = String(cString: path) }
            let isRuntime = ProjectParser.isDevelopmentRuntime(process.name)
            let isProject = project.directory.map { directory in
                ["package.json", "Package.swift", "pyproject.toml", "Cargo.toml", "go.mod", "mix.exs", ".git"].contains { FileManager.default.fileExists(atPath: directory + "/" + $0) }
            } ?? false
            guard isRuntime || isProject else { continue }
            if let dir = project.directory, dir != "/" { project.name = URL(fileURLWithPath: dir).lastPathComponent }
            project.processes = [process]
            let key = project.id
            if var existing = groups[key] {
                existing.ports = Array(Set(existing.ports + project.ports)).sorted()
                existing.processes += project.processes; groups[key] = existing
            } else { groups[key] = project }
        }
        return groups.values.sorted { $0.memory > $1.memory }
    }
}

func finite(_ value: Double) -> Double? { value.isFinite ? value : nil }
func cString<T>(_ value: T) -> String {
    withUnsafeBytes(of: value) { bytes in
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
