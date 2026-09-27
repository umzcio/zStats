import Foundation

public struct NetworkCounters: Sendable {
    public var received: UInt64
    public var sent: UInt64
    public init(received: UInt64, sent: UInt64) { self.received = received; self.sent = sent }
}
public struct NetworkTotals: Sendable {
    public var download: Double?
    public var upload: Double?
    public var received: Double
    public var sent: Double
}
public struct NetworkTracker: Sendable {
    private var previous: [String: NetworkCounters] = [:]
    private var previousTime: Double?
    private var received = 0.0
    private var sent = 0.0
    public init() {}
    public mutating func sample(_ counters: [String: NetworkCounters], time: Double) -> NetworkTotals {
        let elapsed = time - (previousTime ?? time)
        var downloads: [Double] = [], uploads: [Double] = []
        for (name, value) in counters {
            if let delta = CounterRate.rate(current: value.received, previous: previous[name]?.received, seconds: 1) {
                received += delta
                if elapsed > 0 { downloads.append(delta / elapsed) }
            }
            if let delta = CounterRate.rate(current: value.sent, previous: previous[name]?.sent, seconds: 1) {
                sent += delta
                if elapsed > 0 { uploads.append(delta / elapsed) }
            }
        }
        previous = counters; previousTime = time
        return .init(download: downloads.isEmpty ? nil : downloads.reduce(0, +), upload: uploads.isEmpty ? nil : uploads.reduce(0, +), received: received, sent: sent)
    }
}
