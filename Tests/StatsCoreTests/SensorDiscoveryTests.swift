import Testing
@testable import StatsCore

@Test func discoveryRevisitsFailedCandidatesAfterInterval() {
    var now = 0.0
    var scans = 0
    var secondAvailable = false
    let discovery = SensorDiscovery(clock: { now })
    let candidates = {
        scans += 1
        return ["TOne", "TTwo", "TOne"]
    }
    let read: (String) -> Double? = { key in
        key == "TOne" ? 50 : secondAvailable ? 60 : nil
    }
    let valid: (String, Double) -> Bool = { _, value in value > 0 }

    #expect(discovery.sample(candidates: candidates, read: read, isValid: valid).readings.map(\.id) == ["TOne"])
    secondAvailable = true
    now = 29
    #expect(discovery.sample(candidates: candidates, read: read, isValid: valid).readings.map(\.id) == ["TOne"])
    #expect(scans == 1)

    now = 30
    let recovered = discovery.sample(candidates: candidates, read: read, isValid: valid)
    #expect(recovered.readings == [.init(id: "TOne", value: 50), .init(id: "TTwo", value: 60)])
    #expect(scans == 2)
}

@Test func failedEnumerationRetainsWorkingSensors() {
    var now = 0.0
    var enumerate = true
    let discovery = SensorDiscovery(clock: { now })
    let read: (String) -> Double? = { $0 == "TOne" ? 50 : nil }
    let valid: (String, Double) -> Bool = { _, value in value > 0 }

    #expect(discovery.sample(candidates: { ["TOne"] }, read: read, isValid: valid).readings.map(\.id) == ["TOne"])
    now = 30
    enumerate = false
    let retained = discovery.sample(candidates: { enumerate ? ["TOne"] : nil }, read: read, isValid: valid)
    #expect(retained.readings == [.init(id: "TOne", value: 50)])
    #expect(!retained.shouldResetTransport)
}

@Test func whollyFailedSamplesResetDiscoveryAfterThreeAttempts() {
    let now = 0.0
    var scans = 0
    var available = true
    let discovery = SensorDiscovery(clock: { now })
    let candidates = {
        scans += 1
        return ["TOne"]
    }
    let read: (String) -> Double? = { _ in available ? 50 : nil }
    let valid: (String, Double) -> Bool = { _, value in value > 0 }

    _ = discovery.sample(candidates: candidates, read: read, isValid: valid)
    available = false
    #expect(!discovery.sample(candidates: candidates, read: read, isValid: valid).shouldResetTransport)
    #expect(!discovery.sample(candidates: candidates, read: read, isValid: valid).shouldResetTransport)
    #expect(discovery.sample(candidates: candidates, read: read, isValid: valid).shouldResetTransport)

    available = true
    let reopened = discovery.sample(candidates: candidates, read: read, isValid: valid)
    #expect(reopened.readings == [.init(id: "TOne", value: 50)])
    #expect(scans == 2)
}

@Test func explicitResetAllowsImmediateRediscovery() {
    var now = 0.0
    var scans = 0
    let discovery = SensorDiscovery(clock: { now })
    let candidates = {
        scans += 1
        return ["TOne"]
    }
    let read: (String) -> Double? = { _ in 50 }
    let valid: (String, Double) -> Bool = { _, value in value > 0 }

    _ = discovery.sample(candidates: candidates, read: read, isValid: valid)
    now = 1
    discovery.reset()
    _ = discovery.sample(candidates: candidates, read: read, isValid: valid)
    #expect(scans == 2)
}
