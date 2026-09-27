import Foundation
import StatsCore
import CStats

// Confined to SystemSampler's background sampling task.
final class SensorSampler {
    private var connection: UInt32 = 0
    private var catalog: [String] = []
    private var failedSamples = 0
    private var lastDiscovery = -Double.infinity
    private let chip = HardwareName.chip
    private var descriptions: [String: (String, SensorReading.Group)] = [:]
    deinit { zs_smc_close(connection) }

    private func read(_ key: String) -> Double? {
        var type = [CChar](repeating: 0, count: 5)
        var bytes = [UInt8](repeating: 0, count: 32)
        let count = zs_smc_read(connection, key, &type, &bytes)
        guard count > 0 else { return nil }
        return SMCDecoder.value(type: String(cString: type), bytes: Array(bytes.prefix(Int(count))))
    }
    func sample() -> [SensorReading] {
        let now = ProcessInfo.processInfo.systemUptime
        if catalog.isEmpty && now - lastDiscovery >= 30 {
            lastDiscovery = now
            if connection == 0 { connection = zs_smc_open() }
            guard connection != 0, let count = read("#KEY"), count > 0, count <= 16384 else {
                zs_smc_close(connection); connection = 0
                return []
            }
            for index in 0..<Int(count) {
                var chars = [CChar](repeating: 0, count: 5)
                guard zs_smc_key(connection, UInt32(index), &chars) != 0 else { continue }
                let key = String(cString: chars)
                guard key.hasPrefix("T") || (key.hasPrefix("F") && key.hasSuffix("Ac")) else { continue }
                guard let value = read(key), SensorReading.valid(value, kind: key.hasPrefix("F") ? .fan : .temperature) else { continue }
                catalog.append(key)
                descriptions[key] = SensorCatalog.description(key: key, chip: chip)
            }
        }
        let readings = catalog.sorted().map { key in
            let descriptor = descriptions[key] ?? (key, .other)
            return SensorReading(id: key, name: descriptor.0, kind: key.hasPrefix("F") ? .fan : .temperature, group: descriptor.1, value: read(key))
        }
        if !readings.isEmpty && readings.allSatisfy({ $0.value == nil }) {
            failedSamples += 1
            // Reopen after repeated connection failures (for example after sleep).
            if failedSamples >= 3 { reset() }
        } else { failedSamples = 0 }
        return readings
    }
    func reset() {
        zs_smc_close(connection); connection = 0; catalog = []; descriptions = [:]; lastDiscovery = -Double.infinity; failedSamples = 0
    }
}
