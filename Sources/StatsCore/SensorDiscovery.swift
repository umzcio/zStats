public struct SensorDiscoveryReading: Equatable, Sendable {
    public var id: String
    public var value: Double?

    public init(id: String, value: Double?) {
        self.id = id
        self.value = value
    }
}

public struct SensorDiscoveryResult: Equatable, Sendable {
    public var readings: [SensorDiscoveryReading]
    public var shouldResetTransport: Bool

    public init(readings: [SensorDiscoveryReading], shouldResetTransport: Bool) {
        self.readings = readings
        self.shouldResetTransport = shouldResetTransport
    }
}

public final class SensorDiscovery {
    private let interval: Double
    private let clock: () -> Double
    private var catalog: Set<String> = []
    private var lastDiscovery = -Double.infinity
    private var failedSamples = 0

    public init(interval: Double = 30, clock: @escaping () -> Double) {
        self.interval = interval
        self.clock = clock
    }

    public func sample(
        candidates: () -> [String]?,
        read: (String) -> Double?,
        isValid: (String, Double) -> Bool
    ) -> SensorDiscoveryResult {
        let now = clock()
        var discoveredValues: [String: Double] = [:]
        if now - lastDiscovery >= interval {
            lastDiscovery = now
            if let keys = candidates() {
                for key in keys where !catalog.contains(key) {
                    guard let value = read(key), isValid(key, value) else { continue }
                    catalog.insert(key)
                    discoveredValues[key] = value
                }
            }
        }

        let readings = catalog.sorted().map { key in
            let value = discoveredValues[key] ?? read(key)
            return SensorDiscoveryReading(id: key, value: value.flatMap { isValid(key, $0) ? $0 : nil })
        }
        let allFailed = !readings.isEmpty && readings.allSatisfy { $0.value == nil }
        failedSamples = allFailed ? failedSamples + 1 : 0
        let shouldResetTransport = failedSamples >= 3
        if shouldResetTransport { reset() }
        return SensorDiscoveryResult(readings: readings, shouldResetTransport: shouldResetTransport)
    }

    public func reset() {
        catalog = []
        lastDiscovery = -.infinity
        failedSamples = 0
    }
}
