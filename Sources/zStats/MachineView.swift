import SwiftUI
import AppKit
import Darwin

struct MachineInfo: Sendable {
    var name = "This Mac"
    var chip = "—"
    var processor = "—"
    var memory = "—"
    var graphics = "—"
    var disks = "—"
    var model = "—"
    var year = "Not reported"
    var serial = "—"
    var system = "macOS"
    var icon = "com.apple.macbookpro-16-2021-space-gray"

    static func read() -> MachineInfo {
        var info = MachineInfo()
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        command.arguments = ["SPHardwareDataType", "SPDisplaysDataType", "-json"]
        let pipe = Pipe(); command.standardOutput = pipe; command.standardError = FileHandle.nullDevice
        var root: [String: Any] = [:]
        if (try? command.run()) != nil {
            let timeout = DispatchWorkItem { if command.isRunning { command.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10, execute: timeout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); command.waitUntilExit(); timeout.cancel()
            root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        let hardware = (root["SPHardwareDataType"] as? [[String: Any]])?.first ?? [:]
        let graphics = (root["SPDisplaysDataType"] as? [[String: Any]]) ?? []
        info.model = hardware["machine_model"] as? String ?? string("hw.model") ?? "—"
        info.chip = hardware["chip_type"] as? String ?? string("machdep.cpu.brand_string") ?? "—"
        info.name = hardware["machine_name"] as? String ?? "Mac"
        // Model introduction years, not an inferred manufacture date or decoded serial.
        // Source: Apple Support, Identify your MacBook Pro model (108052).
        switch info.model {
        case "Mac17,6", "Mac17,8": info.name = "MacBook Pro 16\""; info.year = "2026"
        case "Mac17,7", "Mac17,9": info.name = "MacBook Pro 14\""; info.year = "2026"; info.icon = "com.apple.macbookpro-14-2021-space-gray"
        case "Mac17,2": info.name = "MacBook Pro 14\""; info.year = "2025"; info.icon = "com.apple.macbookpro-14-2021-space-gray"
        default: break
        }
        if info.name.contains("Air") { info.icon = "com.apple.macbookair-13-2022-midnight" }
        else if info.name.contains("mini") { info.icon = "com.apple.macmini" }
        else if info.name.contains("Studio") { info.icon = "com.apple.macstudio" }
        else if info.name.contains("iMac") { info.icon = "com.apple.imac-2021-silver" }
        info.serial = hardware["serial_number"] as? String ?? "—"
        info.memory = hardware["physical_memory"] as? String ?? "\(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB"
        var processor = [info.chip, "\(integer("hw.physicalcpu") ?? ProcessInfo.processInfo.processorCount) cores, \(ProcessInfo.processInfo.processorCount) threads"]
        for level in 0..<4 {
            if let count = integer("hw.perflevel\(level).physicalcpu"), count > 0,
               let name = string("hw.perflevel\(level).name") {
                processor.append("\(count) \(name.lowercased()) cores")
            }
        }
        info.processor = processor.joined(separator: "\n")
        info.graphics = graphics.map { gpu in
            let name = gpu["sppci_model"] as? String ?? gpu["_name"] as? String ?? "Graphics"
            return name + ((gpu["sppci_cores"] as? String).map { " (\($0) cores)" } ?? "")
        }.joined(separator: "\n")
        if info.graphics.isEmpty { info.graphics = "Not reported" }
        if let volume = try? URL(fileURLWithPath: "/System/Volumes/Data").resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey]) {
            let capacity = Double(volume.volumeTotalCapacity ?? 0) / 1e12
            info.disks = "\(volume.volumeName ?? "Startup disk") (\(String(format: capacity >= 1 ? "%.0f TB" : "%.2f TB", capacity)))"
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        info.system = version.majorVersion == 26 ? "macOS Tahoe (\(number))" : "macOS \(number)"
        return info
    }
    private static func string(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }
    private static func integer(_ key: String) -> Int? {
        var value: Int32 = 0; var size = MemoryLayout<Int32>.size
        guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

@MainActor final class MachineModel: ObservableObject {
    static let shared = MachineModel()
    @Published var info: MachineInfo?
    @Published var displays = "—"
    private var loading = false
    func load() async {
        refreshDisplays()
        guard info == nil, !loading else { return }
        loading = true
        info = await Task.detached(priority: .utility) { MachineInfo.read() }.value
        loading = false
    }
    func refreshDisplays() {
        displays = NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let mode = CGDisplayCopyDisplayMode(id)
            let width = mode?.pixelWidth ?? CGDisplayPixelsWide(id)
            let height = mode?.pixelHeight ?? CGDisplayPixelsHigh(id)
            let hz = mode.map { $0.refreshRate > 0 ? Int($0.refreshRate.rounded()) : screen.maximumFramesPerSecond } ?? screen.maximumFramesPerSecond
            return "\(screen.localizedName)\n\(width) × \(height), \(hz) Hz"
        }.joined(separator: "\n")
    }
}

struct MachineView: View {
    @StateObject private var model = MachineModel.shared
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let info = model.info {
                    VStack(spacing: 9) {
                        if let icon = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/\(info.icon).icns") {
                            Image(nsImage: icon).resizable().scaledToFit().frame(width: 120, height: 82)
                        } else { Image(systemName: "laptopcomputer").font(.system(size: 62, weight: .ultraLight)).frame(height: 82) }
                        Text(info.name + " (" + info.chip.replacingOccurrences(of: "Apple ", with: "") + ")")
                            .font(.system(size: 20, weight: .semibold))
                        Text(info.system).font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 8)
                    machineGroup([
                        ("Processor", info.processor), ("Memory", info.memory),
                        ("Graphics", info.graphics), ("Disks", info.disks), ("Display", model.displays)
                    ])
                    machineGroup([("Model identifier", info.model), ("Model year", info.year), ("Serial number", info.serial)])
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        let uptime = Int(ProcessInfo.processInfo.systemUptime)
                        machineGroup([("Uptime", "\(uptime / 86400) days, \(uptime / 3600 % 24) hours")])
                    }
                } else {
                    ProgressView("Reading this Mac…").frame(maxWidth: .infinity, minHeight: 400)
                }
            }.padding(.bottom, 10)
        }.task { await model.load() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in model.refreshDisplays() }
    }
    private func machineGroup(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().opacity(0.45).padding(.horizontal, 14) }
                HStack(alignment: .top) {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer(minLength: 30)
                    Text(row.1).multilineTextAlignment(.trailing).textSelection(.enabled)
                }.font(.system(size: 12)).padding(.horizontal, 16).padding(.vertical, 11)
            }
        }.background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}
