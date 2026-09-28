import Testing
@testable import StatsCore

@Test func systemCPURequiresFreshBaselineAfterFailure() {
    var tracker = SystemCounterTracker()
    let first = SystemCPUCounters(user: 100, system: 50, idle: 850, nice: 0)
    let second = SystemCPUCounters(user: 120, system: 60, idle: 920, nice: 0)
    let recovered = SystemCPUCounters(user: 140, system: 70, idle: 990, nice: 0)
    let following = SystemCPUCounters(user: 160, system: 80, idle: 1_060, nice: 0)

    #expect(tracker.sample(first) == nil)
    #expect(tracker.sample(second) == .init(user: 20, system: 10, total: 30))
    #expect(tracker.sample(nil) == nil)
    #expect(tracker.sample(recovered) == nil)
    #expect(tracker.sample(following) == .init(user: 20, system: 10, total: 30))
}

@Test func systemCPUCounterResetEstablishesNewBaseline() {
    var tracker = SystemCounterTracker()
    #expect(tracker.sample(.init(user: 100, system: 100, idle: 800)) == nil)
    #expect(tracker.sample(.init(user: 10, system: 10, idle: 80)) == nil)
    #expect(tracker.sample(.init(user: 20, system: 15, idle: 165)) == .init(user: 10, system: 5, total: 15))
    #expect(SystemCPUCounters(valid: false, user: 0, system: 0, idle: 0, nice: 0) == nil)
}

@Test func systemMemoryDistinguishesValidZeroFromFailedReads() {
    let zero = SystemMemoryReading(
        total: 64, totalValid: true,
        used: 0, app: 0, wired: 0, compressed: 0, cached: 0, vmValid: true,
        swap: 0, swapValid: true,
        pressure: 0, pressureValid: true
    )
    #expect(zero.total == 64)
    #expect(zero.used == 0)
    #expect(zero.app == 0)
    #expect(zero.swap == 0)
    #expect(zero.pressure == 0)

    let failed = SystemMemoryReading(
        total: 0, totalValid: false,
        used: 0, app: 0, wired: 0, compressed: 0, cached: 0, vmValid: false,
        swap: 0, swapValid: false,
        pressure: 0, pressureValid: false
    )
    #expect(failed.total == nil)
    #expect(failed.used == nil)
    #expect(failed.app == nil)
    #expect(failed.wired == nil)
    #expect(failed.compressed == nil)
    #expect(failed.cached == nil)
    #expect(failed.swap == nil)
    #expect(failed.pressure == nil)

    let mixed = SystemMemoryReading(
        total: 64, totalValid: true,
        used: 0, app: 0, wired: 0, compressed: 0, cached: 0, vmValid: false,
        swap: 0, swapValid: true,
        pressure: 0, pressureValid: false
    )
    #expect(mixed.total == 64)
    #expect(mixed.used == nil)
    #expect(mixed.swap == 0)
    #expect(mixed.pressure == nil)
}
