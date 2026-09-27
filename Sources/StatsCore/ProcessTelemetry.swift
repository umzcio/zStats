import Foundation

public enum NettopParser {
    /// Header-driven process-only CSV. No addresses or connection details are collected.
    public static func parse(_ text: String) -> [Int32: NetworkCounters]? {
        var input: Int?, output: Int?
        var result: [Int32: NetworkCounters] = [:]
        var sawHeader = false
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = csv(String(line))
            if fields.first == "" {
                guard let i = fields.firstIndex(of: "bytes_in"), let o = fields.firstIndex(of: "bytes_out") else { continue }
                input = i; output = o; sawHeader = true; result = [:]
                continue
            }
            guard let input, let output, fields.count > max(input, output),
                  let name = fields.first, let suffix = name.split(separator: ".").last,
                  let pid = Int32(suffix), pid > 0,
                  let received = UInt64(fields[input]), let sent = UInt64(fields[output]) else { continue }
            result[pid] = NetworkCounters(received: received, sent: sent)
        }
        return sawHeader ? result : nil
    }
    private static func csv(_ line: String) -> [String] {
        var fields: [String] = [], field = "", quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let c = line[index], next = line.index(after: index)
            if c == "\"" {
                if quoted, next < line.endIndex, line[next] == "\"" { field.append(c); index = line.index(after: next); continue }
                quoted.toggle()
            } else if c == ",", !quoted { fields.append(field); field = "" }
            else { field.append(c) }
            index = next
        }
        fields.append(field); return fields
    }
}

public struct ProcessNetworkRates: Sendable {
    public var download: Double?
    public var upload: Double?
}

public struct ProcessNetworkTracker: Sendable {
    private var previous: [ProcessIdentity: NetworkCounters] = [:]
    private var time: Double?
    public init() {}
    public mutating func sample(_ counters: [ProcessIdentity: NetworkCounters], time: Double) -> [ProcessIdentity: ProcessNetworkRates] {
        let seconds = self.time.map { time - $0 } ?? 0
        let rates = counters.mapValues { _ in ProcessNetworkRates(download: nil, upload: nil) }
        var result = rates
        for (identity, counter) in counters {
            result[identity] = .init(download: CounterRate.rate(current: counter.received, previous: previous[identity]?.received, seconds: seconds),
                                     upload: CounterRate.rate(current: counter.sent, previous: previous[identity]?.sent, seconds: seconds))
        }
        previous = counters; self.time = time
        return result
    }
}

public struct GPUClientIdentity: Hashable, Sendable {
    public var process: ProcessIdentity
    public var registryID: UInt64
    public init(process: ProcessIdentity, registryID: UInt64) { self.process = process; self.registryID = registryID }
}

public struct GPUTimeTracker: Sendable {
    private var previous: [GPUClientIdentity: UInt64] = [:]
    private var time: Double?
    public init() {}
    public mutating func sample(_ counters: [GPUClientIdentity: UInt64], time: Double) -> [ProcessIdentity: Double] {
        let seconds = self.time.map { time - $0 } ?? 0
        var result: [ProcessIdentity: Double] = [:]
        for (client, counter) in counters {
            guard let rate = CounterRate.rate(current: counter, previous: previous[client], seconds: seconds) else { continue }
            result[client.process, default: 0] += rate / 1e9 * 100
        }
        previous = counters; self.time = time
        return result
    }
}
