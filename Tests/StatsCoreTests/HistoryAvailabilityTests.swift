import Foundation
import Testing
@testable import StatsCore

@Test func historyPointDecodesLegacyNumericMemory() throws {
    let data = Data(#"{"date":0,"cpu":12,"memory":42}"#.utf8)
    let point = try JSONDecoder().decode(HistoryPoint.self, from: data)

    #expect(point.cpu == 12)
    #expect(point.memory == 42)
}

@Test func historyPointDecodesNullAndMissingMemoryAsUnavailable() throws {
    let nullData = Data(#"{"date":0,"cpu":null,"memory":null}"#.utf8)
    let missingData = Data(#"{"date":0}"#.utf8)

    #expect(try JSONDecoder().decode(HistoryPoint.self, from: nullData).memory == nil)
    #expect(try JSONDecoder().decode(HistoryPoint.self, from: missingData).memory == nil)
}

@Test func historyPointPreservesUnavailableSnapshotMemory() {
    let snapshot = SystemSnapshot()
    let point = HistoryPoint(snapshot)

    #expect(snapshot.memoryUsed == nil)
    #expect(point.memory == nil)
}
