public struct DiskCounters: Equatable, Sendable {
    public var read: UInt64
    public var write: UInt64

    public init(read: UInt64, write: UInt64) {
        self.read = read
        self.write = write
    }
}

public struct DiskDeviceSample: Equatable, Sendable {
    public var id: UInt64
    public var counters: DiskCounters?

    public init(id: UInt64, read: UInt64?, write: UInt64?) {
        self.id = id
        self.counters = read.flatMap { read in write.map { DiskCounters(read: read, write: $0) } }
    }
}

public struct DiskRates: Equatable, Sendable {
    public var read: Double?
    public var write: Double?

    public init(read: Double?, write: Double?) {
        self.read = read
        self.write = write
    }
}

public struct DiskTracker: Sendable {
    private var previous: [UInt64: DiskCounters] = [:]
    private var previousTime: Double?

    public init() {}

    public mutating func sample(_ devices: [DiskDeviceSample]?, time: Double) -> DiskRates {
        guard let devices else {
            previous = [:]
            previousTime = nil
            return DiskRates(read: nil, write: nil)
        }

        let current = Dictionary(devices.compactMap { device in
            device.counters.map { (device.id, $0) }
        }, uniquingKeysWith: { _, latest in latest })
        var read = 0.0, write = 0.0
        var validIntervals = 0
        if let previousTime {
            let elapsed = time - previousTime
            if elapsed > 0, elapsed.isFinite {
                for (id, counters) in current {
                    guard let old = previous[id], counters.read >= old.read, counters.write >= old.write else { continue }
                    read += Double(counters.read - old.read) / elapsed
                    write += Double(counters.write - old.write) / elapsed
                    validIntervals += 1
                }
            }
        }
        previous = current
        previousTime = time
        return DiskRates(
            read: validIntervals == 0 ? nil : read,
            write: validIntervals == 0 ? nil : write
        )
    }
}
