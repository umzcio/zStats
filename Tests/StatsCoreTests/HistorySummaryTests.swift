import Foundation
import Testing
@testable import StatsCore

@Test func historySummaryIncludesRangeEndpoints() {
    let start = Date(timeIntervalSince1970: 100)
    let end = Date(timeIntervalSince1970: 200)
    let points: [(Date, Double?)] = [
        (start.addingTimeInterval(-1), 1),
        (start, 10),
        (start.addingTimeInterval(50), 20),
        (end, 30),
        (end.addingTimeInterval(1), 40)
    ]

    let summary = HistoryTimeline.summary(points, start: start, end: end)

    #expect(summary?.average == 20)
    #expect(summary?.maximum == 30)
}

@Test func historySummaryIgnoresUnavailableAndNonfiniteReadings() {
    let start = Date(timeIntervalSince1970: 100)
    let end = Date(timeIntervalSince1970: 200)
    let summary = HistoryTimeline.summary([
        (start, nil),
        (start.addingTimeInterval(10), .nan),
        (start.addingTimeInterval(20), .infinity),
        (start.addingTimeInterval(30), -.infinity),
        (end, 42)
    ], start: start, end: end)

    #expect(summary?.average == 42)
    #expect(summary?.maximum == 42)
    #expect(HistoryTimeline.summary([], start: start, end: end) == nil)
    #expect(HistoryTimeline.summary([(start, nil)], start: start, end: end) == nil)
    #expect(HistoryTimeline.summary([(start, 1)], start: end, end: start) == nil)
}

@Test func historySummaryFiltersNonfiniteReferenceValues() {
    let summary = HistorySummary(values: [10, nil, .nan, .infinity, 30])

    #expect(summary?.average == 20)
    #expect(summary?.maximum == 30)
    #expect(HistorySummary(values: [nil, .nan, -.infinity]) == nil)
}

@Test func historySummaryDoesNotDependOnChartBucketCount() {
    let start = Date(timeIntervalSince1970: 100)
    let end = Date(timeIntervalSince1970: 200)
    let points: [(Date, Double?)] = [
        (start, 0),
        (start.addingTimeInterval(49), 100),
        (end.addingTimeInterval(-1), 30)
    ]

    let summary = HistoryTimeline.summary(points, start: start, end: end)
    let twoBuckets = HistoryTimeline.buckets(points, start: start, end: end, count: 2).compactMap { $0 }
    let tenBuckets = HistoryTimeline.buckets(points, start: start, end: end, count: 10).compactMap { $0 }

    #expect(summary?.average == 130.0 / 3)
    #expect(summary?.maximum == 100)
    #expect(twoBuckets.reduce(0, +) / Double(twoBuckets.count) == 40)
    #expect(twoBuckets.max() == 50)
    #expect(tenBuckets.reduce(0, +) / Double(tenBuckets.count) == 130.0 / 3)
    #expect(tenBuckets.max() == 100)
}
