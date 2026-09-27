import SwiftUI
import StatsCore

@main enum Launcher {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose-sensors") {
            let sampler = SensorSampler()
            _ = sampler.sample()
            let start = ProcessInfo.processInfo.systemUptime
            let sensors = sampler.sample()
            let duration = ProcessInfo.processInfo.systemUptime - start
            let rows = sensors.filter { $0.name != $0.id }.map { ["key": $0.id, "name": $0.name, "group": $0.group.rawValue, "value": $0.value as Any? ?? NSNull()] as [String: Any] }
            let result: [String: Any] = ["sensorCount": sensors.count, "readMilliseconds": duration * 1000, "cpuAverage": SensorReading.average(sensors, group: .cpu) as Any? ?? NSNull(), "gpuAverage": SensorReading.average(sensors, group: .gpu) as Any? ?? NSNull(), "sensors": rows]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 1 {
            do { try PreviewRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fputs("Preview render failed: \(error)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            let sampler = SystemSampler(historyURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("zstats-diagnostic-history.json"))
            _ = sampler.sample()
            Thread.sleep(forTimeInterval: 2)
            let (snapshot, projects, _, _) = sampler.sample()
            let output: [String: Any] = ["cpuPercent": snapshot.cpu ?? -1, "memoryUsed": snapshot.memoryUsed, "memoryTotal": snapshot.memoryTotal, "appGroups": snapshot.apps.count, "processes": snapshot.apps.reduce(0) { $0 + $1.processes.count }, "projects": projects.count, "diskFree": snapshot.diskFree, "downloadBytesPerSecond": snapshot.download ?? -1, "networkAppsAvailable": snapshot.networkAppsAvailable, "gpuAppsAvailable": snapshot.gpuAppsAvailable, "powerAppsAvailable": snapshot.powerAppsAvailable, "appDownloadTotal": snapshot.apps.compactMap(\.download).reduce(0, +), "appGPUTotal": snapshot.apps.compactMap(\.gpu).reduce(0, +), "appCPUWattsTotal": snapshot.apps.compactMap(\.cpuWatts).reduce(0, +), "gpuPercent": snapshot.gpu ?? -1, "batteryPercent": snapshot.battery ?? -1]
            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        ZStatsApp.main()
    }
}

struct ZStatsApp: App {
    @NSApplicationDelegateAdaptor(ZStatsAppDelegate.self) private var appDelegate
    @StateObject private var store = MonitorStore()
    @StateObject private var menuBar = MenuBarController()
    @StateObject private var updater = AppUpdater()
    var body: some Scene {
        Window("zStats", id: "dashboard") {
            DashboardScene(store: store, menuBar: menuBar)
        }
        .defaultSize(width: 1060, height: 748)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canRequestUpdateCheck)
            }
            CommandMenu("Monitor") {
                Button("Show Menu Bar Panel") { menuBar.show() }.keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                ForEach(Array(([Metric.overview] + Metric.monitors + [.machine]).enumerated()), id: \.element.id) { index, metric in
                    Button(metric.rawValue) { store.selected = metric }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command).disabled(metric != .machine && metric != .overview && !store.isEnabled(metric))
                }
                Button("Sensors") { store.selected = .sensors }.keyboardShortcut("0", modifiers: .command).disabled(!store.preferences.sensorMonitoring)
            }
            CommandMenu("Developer") {
                Toggle("Reference Data", isOn: $store.referenceMode)
            }
        }
        Settings { SettingsView().environmentObject(store).environmentObject(updater) }
    }
}

@MainActor final class ZStatsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // In-place development builds can retain an old Dock icon even after
        // Launch Services registration. Refresh from actool's compiled artwork.
        if let url = Bundle.main.url(forResource: "zStats", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The dashboard is optional; menu-bar monitoring lasts until an explicit Quit.
        false
    }
}
