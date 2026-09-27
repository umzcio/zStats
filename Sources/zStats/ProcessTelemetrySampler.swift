import Foundation
import IOKit
import StatsCore
import CStats

/// Called only by SystemSampler's serial sampling task.
final class ProcessTelemetrySampler {
    private var network = ProcessNetworkTracker()
    private var gpu = GPUTimeTracker()
    private var networkWarmed = false
    private var gpuWarmed = false

    func sample(_ processes: inout [ProcessReading], networkEnabled: Bool = true, gpuEnabled: Bool = true) -> (network: Bool, gpu: Bool) {
        let identities = Dictionary(processes.map { ($0.pid, $0.identity) }, uniquingKeysWith: { a, _ in a })
        var networkAvailable = false
        if networkEnabled, let counters = networkCounters() {
            var identified: [ProcessIdentity: NetworkCounters] = [:]
            for (pid, counter) in counters {
                guard let identity = identities[pid], identity.started > 0, zs_process_start(pid) == identity.started else { continue }
                identified[identity] = counter
            }
            let rates = network.sample(identified, time: ProcessInfo.processInfo.systemUptime)
            networkAvailable = networkWarmed
            for index in processes.indices {
                let identity = processes[index].identity
                if identified[identity] == nil {
                    // No external sockets in a successful process-only snapshot.
                    processes[index].download = networkWarmed ? 0 : nil
                    processes[index].upload = networkWarmed ? 0 : nil
                } else {
                    processes[index].download = rates[identity]?.download
                    processes[index].upload = rates[identity]?.upload
                }
            }
            networkWarmed = true
        } else {
            network = ProcessNetworkTracker(); networkWarmed = false
        }
        var gpuAvailable = false
        if gpuEnabled, let counters = gpuCounters(identities: identities) {
            let rates = gpu.sample(counters, time: ProcessInfo.processInfo.systemUptime)
            let owners = Set(counters.keys.map(\.process))
            gpuAvailable = gpuWarmed
            for index in processes.indices {
                let identity = processes[index].identity
                processes[index].gpu = owners.contains(identity) ? rates[identity] : gpuWarmed ? 0 : nil
            }
            gpuWarmed = true
        } else {
            gpu = GPUTimeTracker(); gpuWarmed = false
        }
        return (networkAvailable, gpuAvailable)
    }

    private func networkCounters() -> [Int32: NetworkCounters]? {
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        command.arguments = ["-P", "-L", "1", "-n", "-x", "-t", "external", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        command.standardOutput = pipe; command.standardError = FileHandle.nullDevice
        do { try command.run() } catch { return nil }
        let timeout = DispatchWorkItem { if command.isRunning { command.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        command.waitUntilExit(); timeout.cancel()
        guard command.terminationStatus == 0 else { return nil }
        return NettopParser.parse(String(decoding: data, as: UTF8.self))
    }

    private func gpuCounters(identities: [Int32: ProcessIdentity]) -> [GPUClientIdentity: UInt64]? {
        var devices: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &devices) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(devices) }
        var counters: [GPUClientIdentity: UInt64] = [:]
        var supported = false
        while case let device = IOIteratorNext(devices), device != 0 {
            defer { IOObjectRelease(device) }
            var children: io_iterator_t = 0
            guard IORegistryEntryCreateIterator(device, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }
            while case let client = IOIteratorNext(children), client != 0 {
                defer { IOObjectRelease(client) }
                guard IOObjectConformsTo(client, "AGXDeviceUserClient") != 0 else { continue }
                guard let usage = IORegistryEntryCreateCFProperty(client, "AppUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]] else { continue }
                let values = usage.compactMap { ($0["accumulatedGPUTime"] as? NSNumber)?.uint64Value }
                guard !values.isEmpty else { continue }
                supported = true
                guard let creator = IORegistryEntryCreateCFProperty(client, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                      let first = creator.split(separator: ",").first,
                      let pid = first.split(separator: " ").last.flatMap({ Int32($0) }),
                      let identity = identities[pid], identity.started > 0,
                      zs_process_start(pid) == identity.started else { continue }
                var registryID: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(client, &registryID) == KERN_SUCCESS else { continue }
                var total: UInt64 = 0
                var overflow = false
                for value in values { let sum = total.addingReportingOverflow(value); total = sum.partialValue; overflow = overflow || sum.overflow }
                if !overflow { counters[GPUClientIdentity(process: identity, registryID: registryID)] = total }
            }
        }
        return supported ? counters : nil
    }
}
