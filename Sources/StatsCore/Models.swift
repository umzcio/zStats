import Foundation

public struct ProcessIdentity: Codable, Hashable, Sendable {
    public let pid: Int32
    public let started: UInt64
    public init(pid: Int32, started: UInt64) { self.pid = pid; self.started = started }
    public func canTerminate(current: Self?, ownPID: Int32) -> Bool {
        pid > 1 && pid != ownPID && started > 0 && current == self
    }
}

public struct ProcessReading: Identifiable, Sendable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var parentPID: Int32
    public var name: String
    public var path: String
    public var memory: Double?
    public var cpu: Double?
    public var readRate: Double?
    public var writeRate: Double?
    public var download: Double?
    public var upload: Double?
    public var gpu: Double?
    public var cpuWatts: Double?
    public var started: UInt64
    public var uid: UInt32
    public var identity: ProcessIdentity { .init(pid: pid, started: started) }
    public init(pid: Int32, parentPID: Int32, name: String, path: String, memory: Double? = nil, cpu: Double? = nil, readRate: Double? = nil, writeRate: Double? = nil, download: Double? = nil, upload: Double? = nil, gpu: Double? = nil, cpuWatts: Double? = nil, started: UInt64 = 0, uid: UInt32 = 0) {
        self.pid = pid; self.parentPID = parentPID; self.name = name; self.path = path
        self.memory = memory; self.cpu = cpu; self.readRate = readRate; self.writeRate = writeRate; self.started = started; self.uid = uid
        self.download = download; self.upload = upload; self.gpu = gpu; self.cpuWatts = cpuWatts
    }
}

public struct AppReading: Identifiable, Sendable {
    public var id: String
    public var name: String
    public var bundlePath: String?
    public var processes: [ProcessReading]
    public var memory: Double? { sum(\.memory) }
    public var cpu: Double? { sum(\.cpu) }
    public var readRate: Double? { sum(\.readRate) }
    public var writeRate: Double? { sum(\.writeRate) }
    public var download: Double? { sum(\.download) }
    public var upload: Double? { sum(\.upload) }
    public var gpu: Double? { sum(\.gpu) }
    public var cpuWatts: Double? { sum(\.cpuWatts) }
    private func sum(_ key: KeyPath<ProcessReading, Double?>) -> Double? {
        let values = processes.compactMap { $0[keyPath: key] }
        return values.isEmpty || values.count != processes.count ? nil : values.reduce(0, +)
    }
}

public struct SystemSnapshot: Sendable {
    public var date = Date()
    public var cpu: Double? = nil
    public var userCPU: Double? = nil
    public var systemCPU: Double? = nil
    public var cores = ProcessInfo.processInfo.processorCount
    public var load = 0.0
    public var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    public var memoryUsed = 0.0
    public var memoryApp = 0.0
    public var memoryWired = 0.0
    public var memoryCompressed = 0.0
    public var memoryCached = 0.0
    public var swap = 0.0
    public var pressure = 1
    public var diskTotal = 0.0
    public var diskFree = 0.0
    public var diskRead: Double? = nil
    public var diskWrite: Double? = nil
    public var download: Double? = nil
    public var upload: Double? = nil
    public var received = 0.0
    public var sent = 0.0
    public var interface = "—"
    public var gpu: Double? = nil
    public var gpuMemory: Double? = nil
    public var battery: Double? = nil
    public var charging = false
    public var batteryMinutes: Double? = nil
    public var batteryHealth: Double? = nil
    public var batteryCycles: Double? = nil
    public var batteryWatts: Double? = nil
    public var batteryTemperature: Double? = nil
    public var sensors: [SensorReading] = []
    public var cpuTemperature: Double? { SensorReading.average(sensors, group: .cpu) }
    public var gpuTemperature: Double? { SensorReading.average(sensors, group: .gpu) }
    public var networkAppsAvailable = false
    public var gpuAppsAvailable = false
    public var powerAppsAvailable = false
    public var apps: [AppReading] = []
    public var uptime = ProcessInfo.processInfo.systemUptime
    public init() {}
}

public struct ProjectReading: Identifiable, Sendable {
    public var id: String { directory ?? "pid:\(pid)" }
    public var pid: Int32
    public var name: String
    public var directory: String?
    public var ports: [Int]
    public var processes: [ProcessReading] = []
    public var memory: Double { processes.reduce(0) { $0 + ($1.memory ?? 0) } }
    public var cpu: Double { processes.reduce(0) { $0 + ($1.cpu ?? 0) } }
    public init(pid: Int32, name: String, directory: String?, ports: [Int], processes: [ProcessReading] = []) {
        self.pid = pid; self.name = name; self.directory = directory; self.ports = ports; self.processes = processes
    }
}

public enum CounterRate {
    public static func rate(current: UInt64, previous: UInt64?, seconds: Double) -> Double? {
        guard let previous, current >= previous, seconds > 0, seconds.isFinite else { return nil }
        return Double(current - previous) / seconds
    }
}
