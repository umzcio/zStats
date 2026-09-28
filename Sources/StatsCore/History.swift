import Foundation

public struct HistoryPoint: Codable, Equatable, Sendable {
    public var date: Date
    public var cpu: Double?
    public var memory: Double
    public var diskRead: Double?
    public var diskWrite: Double?
    public var download: Double?
    public var upload: Double?
    public var gpu: Double?
    public var battery: Double?
    public init(date: Date, cpu: Double?, memory: Double, diskRead: Double? = nil, diskWrite: Double? = nil, download: Double? = nil, upload: Double? = nil, gpu: Double? = nil, battery: Double? = nil) {
        self.date = date; self.cpu = cpu; self.memory = memory; self.diskRead = diskRead; self.diskWrite = diskWrite; self.download = download; self.upload = upload; self.gpu = gpu; self.battery = battery
    }
    public init(_ snapshot: SystemSnapshot) {
        self.init(date: snapshot.date, cpu: snapshot.cpu, memory: snapshot.memoryUsed, diskRead: snapshot.diskRead, diskWrite: snapshot.diskWrite, download: snapshot.download, upload: snapshot.upload, gpu: snapshot.gpu, battery: snapshot.battery)
    }
}

public struct HistoryArchive: Codable, Sendable {
    public private(set) var points: [HistoryPoint] = []
    public init() {}
    public mutating func record(_ point: HistoryPoint, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-30 * 86400)
        points.removeAll { $0.date < cutoff || $0.date > now.addingTimeInterval(60) }
        guard point.date >= cutoff, point.date <= now.addingTimeInterval(60) else { return }
        if let last = points.last, Int(last.date.timeIntervalSince1970 / 60) == Int(point.date.timeIntervalSince1970 / 60) {
            points[points.count - 1] = point
        } else {
            points.append(point)
            points.sort { $0.date < $1.date }
        }
    }
    public func since(_ date: Date) -> [HistoryPoint] { points.filter { $0.date >= date } }
}

public struct HistorySummary: Equatable, Sendable {
    public var average: Double
    public var maximum: Double

    public init?(values: [Double?]) {
        let finiteValues = values.compactMap { value in
            value.flatMap { $0.isFinite ? $0 : nil }
        }
        guard let maximum = finiteValues.max() else { return nil }
        self.average = finiteValues.reduce(0, +) / Double(finiteValues.count)
        self.maximum = maximum
    }
}

public enum HistoryTimeline {
    /// Fixed time buckets preserve missing intervals instead of joining disjoint recording sessions.
    public static func buckets(_ points: [(Date, Double?)], start: Date, end: Date, count: Int) -> [Double?] {
        guard count > 0, end > start else { return [] }
        let duration = end.timeIntervalSince(start)
        var sums = [Double](repeating: 0, count: count), counts = [Int](repeating: 0, count: count)
        for (date, value) in points {
            guard date >= start, date <= end, let value, value.isFinite else { continue }
            let index = min(count - 1, Int(date.timeIntervalSince(start) / duration * Double(count)))
            sums[index] += value; counts[index] += 1
        }
        return (0..<count).map { counts[$0] == 0 ? nil : sums[$0] / Double(counts[$0]) }
    }

    public static func summary(_ points: [(Date, Double?)], start: Date, end: Date) -> HistorySummary? {
        guard end >= start else { return nil }
        return HistorySummary(values: points.compactMap { date, value in
            guard date >= start, date <= end else { return nil }
            return value
        })
    }
}
