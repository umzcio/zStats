import Foundation
import StatsCore
import CStats

// Confined to SystemSampler's background sampling task.
final class SensorSampler {
    private var connection: UInt32 = 0
    private let discovery = SensorDiscovery(clock: { ProcessInfo.processInfo.systemUptime })
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

    private func candidateKeys() -> [String]? {
        if connection == 0 { connection = zs_smc_open() }
        guard connection != 0, let count = read("#KEY"), count > 0, count <= 16384 else {
            // Discovery metadata can fail while already known keys remain readable.
            // Leave transport recovery to the repeated whole-sample failure policy.
            return nil
        }
        return (0..<Int(count)).compactMap { index in
            var chars = [CChar](repeating: 0, count: 5)
            guard zs_smc_key(connection, UInt32(index), &chars) != 0 else { return nil }
            let key = String(cString: chars)
            return key.hasPrefix("T") || (key.hasPrefix("F") && key.hasSuffix("Ac")) ? key : nil
        }
    }

    func sample() -> [SensorReading] {
        let result = discovery.sample(candidates: candidateKeys, read: read) { key, value in
            SensorReading.valid(value, kind: key.hasPrefix("F") ? .fan : .temperature)
        }
        let readings = result.readings.map { reading in
            let key = reading.id
            if descriptions[key] == nil { descriptions[key] = SensorCatalog.description(key: key, chip: chip) }
            let descriptor = descriptions[key] ?? (key, .other)
            return SensorReading(id: key, name: descriptor.0, kind: key.hasPrefix("F") ? .fan : .temperature, group: descriptor.1, value: reading.value)
        }
        if result.shouldResetTransport {
            // Reopen after repeated connection failures (for example after sleep).
            zs_smc_close(connection); connection = 0; descriptions = [:]
        }
        return readings
    }
    func reset() {
        zs_smc_close(connection); connection = 0; discovery.reset(); descriptions = [:]
    }
}
