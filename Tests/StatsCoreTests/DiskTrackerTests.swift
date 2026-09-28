import Testing
@testable import StatsCore

private func disk(_ id: UInt64, _ read: UInt64?, _ write: UInt64?) -> DiskDeviceSample {
    DiskDeviceSample(id: id, read: read, write: write)
}

@Test func diskTrackerHandlesAdditionRemovalAndReappearance() {
    var tracker = DiskTracker()
    #expect(tracker.sample([disk(1, 100, 200)], time: 1) == .init(read: nil, write: nil))
    #expect(tracker.sample([disk(1, 300, 500)], time: 3) == .init(read: 100, write: 150))
    #expect(tracker.sample([disk(1, 500, 800), disk(2, 1_000, 2_000)], time: 5) == .init(read: 100, write: 150))
    #expect(tracker.sample([disk(2, 1_200, 2_400)], time: 7) == .init(read: 100, write: 200))
    #expect(tracker.sample([disk(1, 900, 1_200), disk(2, 1_400, 2_800)], time: 9) == .init(read: 100, write: 200))
    #expect(tracker.sample([], time: 11) == .init(read: nil, write: nil))
    #expect(tracker.sample([disk(1, 1_100, 1_500)], time: 13) == .init(read: nil, write: nil))
}

@Test func resetDeviceDoesNotSuppressAdvancingDevice() {
    var tracker = DiskTracker()
    _ = tracker.sample([disk(1, 100, 200), disk(2, 100, 200)], time: 1)
    #expect(tracker.sample([disk(1, 50, 100), disk(2, 300, 600)], time: 3) == .init(read: 100, write: 200))
    #expect(tracker.sample([disk(1, 150, 300), disk(2, 500, 1_000)], time: 5) == .init(read: 150, write: 300))
}

@Test func missingDeviceStatsInvalidateOnlyThatBaseline() {
    var tracker = DiskTracker()
    _ = tracker.sample([disk(1, 100, 200), disk(2, 100, 200)], time: 1)
    #expect(tracker.sample([disk(1, nil, nil), disk(2, 300, 600)], time: 3) == .init(read: 100, write: 200))
    #expect(tracker.sample([disk(1, 500, 700), disk(2, 500, 1_000)], time: 5) == .init(read: 100, write: 200))
}

@Test func globalDiskQueryFailureInvalidatesAllBaselines() {
    var tracker = DiskTracker()
    _ = tracker.sample([disk(1, 100, 200)], time: 1)
    #expect(tracker.sample(nil, time: 3) == .init(read: nil, write: nil))
    #expect(tracker.sample([disk(1, 500, 700)], time: 5) == .init(read: nil, write: nil))
    #expect(tracker.sample([disk(1, 700, 1_100)], time: 7) == .init(read: 100, write: 200))
}

@Test func diskTrackerPreservesLargeIntegerDeltas() {
    var tracker = DiskTracker()
    _ = tracker.sample([disk(1, 5_000_000_000, 6_000_000_000)], time: 1)
    #expect(tracker.sample([disk(1, 9_000_000_000, 10_000_000_000)], time: 3) == .init(read: 2_000_000_000, write: 2_000_000_000))
}

@Test func diskTrackerRejectsNonpositiveElapsedTime() {
    var tracker = DiskTracker()
    #expect(tracker.sample([disk(1, 100, 200)], time: 1) == .init(read: nil, write: nil))
    #expect(tracker.sample([disk(1, 300, 500)], time: 1) == .init(read: nil, write: nil))
    #expect(tracker.sample([disk(1, 500, 900)], time: 3) == .init(read: 100, write: 200))
}
