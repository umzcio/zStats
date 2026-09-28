import Foundation

public struct HistoryFileOperations {
    public var read: (URL) throws -> Data
    public var isFileNotFoundError: (Error) -> Bool
    public var createDirectory: (URL) throws -> Void
    public var writeAtomically: (Data, URL) throws -> Void

    public init(
        read: @escaping (URL) throws -> Data,
        isFileNotFoundError: @escaping (Error) -> Bool,
        createDirectory: @escaping (URL) throws -> Void,
        writeAtomically: @escaping (Data, URL) throws -> Void
    ) {
        self.read = read
        self.isFileNotFoundError = isFileNotFoundError
        self.createDirectory = createDirectory
        self.writeAtomically = writeAtomically
    }

    public static let live = HistoryFileOperations(
        read: { try Data(contentsOf: $0) },
        isFileNotFoundError: { error in
            let error = error as NSError
            return (error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code))
                || (error.domain == NSPOSIXErrorDomain && error.code == Int(POSIXErrorCode.ENOENT.rawValue))
        },
        createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) },
        writeAtomically: { try $0.write(to: $1, options: .atomic) }
    )
}

public final class HistoryPersistence {
    public private(set) var archive: HistoryArchive
    public private(set) var errorMessage: String?

    private let url: URL
    private let files: HistoryFileOperations
    private var needsLoadResolution = false

    public init(url: URL, files: HistoryFileOperations = .live) {
        self.url = url
        self.files = files
        archive = HistoryArchive()

        do {
            let data = try files.read(url)
            archive = try JSONDecoder().decode(HistoryArchive.self, from: data)
        } catch {
            if files.isFileNotFoundError(error) { return }
            needsLoadResolution = true
            errorMessage = "History could not be loaded; the existing file was preserved: \(error.localizedDescription)"
        }
    }

    public func record(_ point: HistoryPoint, now: Date = Date()) {
        archive.record(point, now: now)
    }

    @discardableResult
    public func save() -> Bool {
        if needsLoadResolution, !resolveLoadBeforeWriting() { return false }

        do {
            try files.createDirectory(url.deletingLastPathComponent())
            try files.writeAtomically(JSONEncoder().encode(archive), url)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "History could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    private func resolveLoadBeforeWriting() -> Bool {
        let existingData: Data
        do {
            existingData = try files.read(url)
        } catch {
            if files.isFileNotFoundError(error) {
                needsLoadResolution = false
                return true
            }
            errorMessage = "History could not be loaded; the existing file was preserved: \(error.localizedDescription)"
            return false
        }

        if let existingArchive = try? JSONDecoder().decode(HistoryArchive.self, from: existingData) {
            archive = merge(existingArchive, with: archive)
            needsLoadResolution = false
            return true
        }

        do {
            try files.createDirectory(url.deletingLastPathComponent())
            try files.writeAtomically(existingData, recoveryURL())
            needsLoadResolution = false
            return true
        } catch {
            errorMessage = "History recovery copy could not be created; the existing file was preserved: \(error.localizedDescription)"
            return false
        }
    }

    private func merge(_ existing: HistoryArchive, with pending: HistoryArchive) -> HistoryArchive {
        let points = (existing.points + pending.points).sorted { $0.date < $1.date }
        let retentionNow = max(Date(), points.last?.date ?? Date())
        var merged = HistoryArchive()
        for point in points {
            merged.record(point, now: retentionNow)
        }
        return merged
    }

    private func recoveryURL() -> URL {
        let extensionPart = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
        let base = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(base).recovery-\(UUID().uuidString)\(extensionPart)")
    }
}
