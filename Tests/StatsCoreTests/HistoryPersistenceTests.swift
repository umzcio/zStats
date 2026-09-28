import Foundation
import Testing
@testable import StatsCore

private enum FixtureError: Error { case injected, missing }
private let fixtureNow = Date(timeIntervalSince1970: 2_000_000_300)

private final class FixtureFiles {
    var failReads = false
    var failRecoveryWrites = false

    var operations: HistoryFileOperations {
        HistoryFileOperations(
            read: { [self] url in
                if failReads { throw FixtureError.injected }
                return try Data(contentsOf: url)
            },
            isFileNotFoundError: { ($0 as? FixtureError) == .missing || HistoryFileOperations.live.isFileNotFoundError($0) },
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
            writeAtomically: { [self] data, url in
                if failRecoveryWrites, url.lastPathComponent.contains(".recovery-") { throw FixtureError.injected }
                try data.write(to: url, options: .atomic)
            }
        )
    }
}

@Test func injectedMissingAndUnreadableFilesHaveDifferentWriteBehavior() throws {
    try withHistoryFixture { url in
        let sample = point(at: 2_000_000_000, cpu: 35)
        let missingFiles = HistoryFileOperations(
            read: { _ in throw FixtureError.missing },
            isFileNotFoundError: { ($0 as? FixtureError) == .missing },
            createDirectory: { _ in },
            writeAtomically: { data, destination in try data.write(to: destination) }
        )
        let missing = persistence(at: url, files: missingFiles)
        missing.record(sample)
        #expect(missing.save())

        let original = Data("must remain".utf8)
        try original.write(to: url)
        let unreadableFiles = HistoryFileOperations(
            read: { _ in throw FixtureError.injected },
            isFileNotFoundError: { _ in false },
            createDirectory: { _ in },
            writeAtomically: { data, destination in try data.write(to: destination) }
        )
        let unreadable = persistence(at: url, files: unreadableFiles)
        unreadable.record(sample)
        #expect(!unreadable.save())
        #expect(try Data(contentsOf: url) == original)
    }
}

private func withHistoryFixture(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zstats-history-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory.appendingPathComponent("history.json"))
}

private func point(at seconds: TimeInterval, cpu: Double) -> HistoryPoint {
    HistoryPoint(date: Date(timeIntervalSince1970: seconds), cpu: cpu, memory: cpu * 10)
}

private func archive(containing points: [HistoryPoint]) -> HistoryArchive {
    var archive = HistoryArchive()
    for point in points { archive.record(point, now: fixtureNow) }
    return archive
}

private struct EncodedArchive: Encodable { let points: [HistoryPoint] }

private func persistence(at url: URL, files: HistoryFileOperations = .live) -> HistoryPersistence {
    HistoryPersistence(url: url, files: files, now: { fixtureNow })
}

private func recoveryFiles(beside url: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("history.recovery-") && $0.pathExtension == "json" }
}

@Test func missingHistoryStartsEmptyAndCanBeSaved() throws {
    try withHistoryFixture { url in
        let persistence = persistence(at: url)
        #expect(persistence.archive.points.isEmpty)
        #expect(persistence.errorMessage == nil)

        let sample = point(at: 2_000_000_000, cpu: 12)
        persistence.record(sample)
        #expect(persistence.save())
        let saved = try JSONDecoder().decode(HistoryArchive.self, from: Data(contentsOf: url))
        #expect(saved.points == [sample])
    }
}

@Test func validHistoryRoundTrips() throws {
    try withHistoryFixture { url in
        let original = archive(containing: [point(at: 2_000_000_000, cpu: 10)])
        try JSONEncoder().encode(original).write(to: url)

        let persistence = persistence(at: url)
        #expect(persistence.archive.points == original.points)
        #expect(persistence.save())
        let saved = try JSONDecoder().decode(HistoryArchive.self, from: Data(contentsOf: url))
        #expect(saved.points == original.points)
    }
}

@Test func malformedHistoryIsBackedUpByteForByteBeforeReplacement() throws {
    try withHistoryFixture { url in
        let malformed = Data([0x00, 0xff, 0x7b, 0x6e, 0x6f])
        try malformed.write(to: url)
        let persistence = persistence(at: url)
        let sample = point(at: 2_000_000_000, cpu: 20)
        persistence.record(sample)

        #expect(persistence.save())
        let backups = try recoveryFiles(beside: url)
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: backups[0]) == malformed)
        let saved = try JSONDecoder().decode(HistoryArchive.self, from: Data(contentsOf: url))
        #expect(saved.points == [sample])
    }
}

@Test func failedRecoveryCopyLeavesMalformedHistoryUntouched() throws {
    try withHistoryFixture { url in
        let malformed = Data("not json".utf8)
        try malformed.write(to: url)
        let fixture = FixtureFiles()
        fixture.failRecoveryWrites = true
        let persistence = persistence(at: url, files: fixture.operations)
        let sample = point(at: 2_000_000_000, cpu: 30)
        persistence.record(sample)

        #expect(!persistence.save())
        #expect(try Data(contentsOf: url) == malformed)
        #expect(try recoveryFiles(beside: url).isEmpty)
        #expect(persistence.errorMessage != nil)

        fixture.failRecoveryWrites = false
        #expect(persistence.save())
        #expect(persistence.errorMessage == nil)
        #expect(try recoveryFiles(beside: url).count == 1)
        let saved = try JSONDecoder().decode(HistoryArchive.self, from: Data(contentsOf: url))
        #expect(saved.points == [sample])
    }
}

@Test func readFailureRefusesToReplaceExistingHistory() throws {
    try withHistoryFixture { url in
        let originalData = try JSONEncoder().encode(archive(containing: [point(at: 2_000_000_000, cpu: 40)]))
        try originalData.write(to: url)
        let fixture = FixtureFiles()
        fixture.failReads = true
        let persistence = persistence(at: url, files: fixture.operations)
        let sample = point(at: 2_000_000_120, cpu: 50)
        persistence.record(sample)

        #expect(!persistence.save())
        #expect(try Data(contentsOf: url) == originalData)
        #expect(persistence.errorMessage != nil)
    }
}

@Test func laterSuccessfulReadMergesStoredAndPendingSamples() throws {
    try withHistoryFixture { url in
        let stored = point(at: 2_000_000_000, cpu: 60)
        try JSONEncoder().encode(archive(containing: [stored])).write(to: url)
        let fixture = FixtureFiles()
        fixture.failReads = true
        let persistence = persistence(at: url, files: fixture.operations)
        let pending = point(at: 2_000_000_120, cpu: 70)
        persistence.record(pending)
        #expect(!persistence.save())

        fixture.failReads = false
        #expect(persistence.save())
        #expect(persistence.errorMessage == nil)
        #expect(persistence.archive.points == [stored, pending])
        let saved = try JSONDecoder().decode(HistoryArchive.self, from: Data(contentsOf: url))
        #expect(saved.points == [stored, pending])
    }
}

@Test func recoveryMergeUsesNewerSampleForAnOverlappingMinute() throws {
    try withHistoryFixture { url in
        let storedOverlap = point(at: 2_000_000_010, cpu: 61)
        let storedLater = point(at: 2_000_000_120, cpu: 62)
        try JSONEncoder().encode(archive(containing: [storedOverlap, storedLater])).write(to: url)
        let fixture = FixtureFiles()
        fixture.failReads = true
        let persistence = persistence(at: url, files: fixture.operations)
        let newerOverlap = point(at: 2_000_000_020, cpu: 63)
        persistence.record(newerOverlap)

        fixture.failReads = false
        #expect(persistence.save())
        #expect(persistence.archive.points == [newerOverlap, storedLater])
    }
}

@Test func recoveryMergeDoesNotTrustFutureArchiveTimestampsForRetention() throws {
    try withHistoryFixture { url in
        let recent = point(at: fixtureNow.timeIntervalSince1970 - 120, cpu: 64)
        let future = point(at: fixtureNow.timeIntervalSince1970 + 365 * 86400, cpu: 65)
        try JSONEncoder().encode(EncodedArchive(points: [recent, future])).write(to: url)
        let fixture = FixtureFiles()
        fixture.failReads = true
        let persistence = persistence(at: url, files: fixture.operations)
        let pending = point(at: fixtureNow.timeIntervalSince1970, cpu: 66)
        persistence.record(pending)

        fixture.failReads = false
        #expect(persistence.save())
        #expect(persistence.archive.points == [recent, pending])
        let saved = try JSONDecoder().decode(HistoryArchive.self, from: Data(contentsOf: url))
        #expect(saved.points == [recent, pending])
    }
}

@Test func malformedHistoryBackupsUseUniqueNames() throws {
    try withHistoryFixture { url in
        try Data("first bad file".utf8).write(to: url)
        let first = persistence(at: url)
        #expect(first.save())

        try Data("second bad file".utf8).write(to: url)
        let second = persistence(at: url)
        #expect(second.save())

        let backups = try recoveryFiles(beside: url)
        #expect(backups.count == 2)
        #expect(Set(backups.map(\.lastPathComponent)).count == 2)
    }
}

@Test func normalSaveUpdatesAnAlreadyLoadedArchive() throws {
    try withHistoryFixture { url in
        let first = point(at: 2_000_000_000, cpu: 80)
        try JSONEncoder().encode(archive(containing: [first])).write(to: url)
        let persistence = persistence(at: url)
        let second = point(at: 2_000_000_120, cpu: 90)
        persistence.record(second)

        #expect(persistence.save())
        let saved = try JSONDecoder().decode(HistoryArchive.self, from: Data(contentsOf: url))
        #expect(saved.points == [first, second])
        #expect(try recoveryFiles(beside: url).isEmpty)
    }
}
