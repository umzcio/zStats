public struct SystemCPUCounters: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64 = 0) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public init?(valid: Bool, user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        guard valid else { return nil }
        self.init(user: user, system: system, idle: idle, nice: nice)
    }
}

public struct SystemCPUUsage: Equatable, Sendable {
    public var user: Double
    public var system: Double
    public var total: Double
}

public struct SystemCounterTracker: Sendable {
    private var previous: SystemCPUCounters?

    public init() {}

    public mutating func sample(_ current: SystemCPUCounters?) -> SystemCPUUsage? {
        guard let current else {
            previous = nil
            return nil
        }
        defer { previous = current }
        guard let previous,
              current.user >= previous.user,
              current.system >= previous.system,
              current.idle >= previous.idle,
              current.nice >= previous.nice else { return nil }
        let user = Double(current.user - previous.user) + Double(current.nice - previous.nice)
        let system = Double(current.system - previous.system)
        let idle = Double(current.idle - previous.idle)
        let total = user + system + idle
        guard total > 0, total.isFinite else { return nil }
        let userPercent = user / total * 100
        let systemPercent = system / total * 100
        return SystemCPUUsage(user: userPercent, system: systemPercent, total: userPercent + systemPercent)
    }
}

public struct SystemMemoryReading: Equatable, Sendable {
    public var total: Double?
    public var used: Double?
    public var app: Double?
    public var wired: Double?
    public var compressed: Double?
    public var cached: Double?
    public var swap: Double?
    public var pressure: Int?

    public init(
        total: Double, totalValid: Bool,
        used: Double, app: Double, wired: Double, compressed: Double, cached: Double, vmValid: Bool,
        swap: Double, swapValid: Bool,
        pressure: Int, pressureValid: Bool
    ) {
        self.total = Self.available(total, valid: totalValid && total > 0)
        self.used = Self.available(used, valid: vmValid)
        self.app = Self.available(app, valid: vmValid)
        self.wired = Self.available(wired, valid: vmValid)
        self.compressed = Self.available(compressed, valid: vmValid)
        self.cached = Self.available(cached, valid: vmValid)
        self.swap = Self.available(swap, valid: swapValid)
        self.pressure = pressureValid ? pressure : nil
    }

    private static func available(_ value: Double, valid: Bool) -> Double? {
        valid && value.isFinite && value >= 0 ? value : nil
    }
}
