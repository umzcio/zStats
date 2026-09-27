import Foundation

public enum ProcessGrouper {
    public static func bundlePath(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return path.hasSuffix(".app") ? path : nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    public static func group(_ processes: [ProcessReading]) -> [AppReading] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var groups: [String: AppReading] = [:]
        for process in processes {
            var current = process
            var visited: Set<Int32> = []
            var bundle: String?
            while visited.insert(current.pid).inserted {
                if let path = bundlePath(current.path) { bundle = path; break }
                guard current.parentPID > 1, let parent = byPID[current.parentPID] else { break }
                current = parent
            }
            let key = bundle ?? "process:\(process.path.isEmpty ? process.name : process.path)"
            let name = bundle.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? process.name
            if groups[key] == nil { groups[key] = AppReading(id: key, name: name, bundlePath: bundle, processes: []) }
            groups[key]?.processes.append(process)
        }
        return groups.values.sorted { ($0.memory ?? 0) > ($1.memory ?? 0) }
    }
}

public enum ProjectParser {
    /// Match executable names, not substrings such as "go" in "Google Drive".
    public static func isDevelopmentRuntime(_ name: String) -> Bool {
        let name = name.lowercased()
        let runtimes: Set<String> = ["node", "python", "ruby", "php", "java", "deno", "bun", "go", "uvicorn", "dotnet", "beam", "beam.smp", "cargo"]
        return runtimes.contains(name) || name.range(of: "^(python|ruby|php|node|java)[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil
    }

    /// lsof -Fpcfn output. Only listening-port entries are supplied by the caller.
    public static func parse(_ text: String) -> [ProjectReading] {
        var result: [ProjectReading] = []
        var pid: Int32?
        var command = "Process"
        var directory: String?
        var field = ""
        var ports: Set<Int> = []
        func flush() {
            if let pid, !ports.isEmpty { result.append(.init(pid: pid, name: command, directory: directory, ports: ports.sorted())) }
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": flush(); pid = Int32(value); command = "Process"; directory = nil; ports = []; field = ""
            case "c": command = value
            case "f": field = value
            case "n":
                if field == "cwd" { directory = value }
                else if let last = value.split(separator: ":").last, let port = Int(last), (1...65535).contains(port) { ports.insert(port) }
            default: break
            }
        }
        flush()
        return result
    }
}
