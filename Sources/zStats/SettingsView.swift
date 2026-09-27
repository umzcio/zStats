import SwiftUI
import ServiceManagement
import StatsCore

struct SettingsView: View {
    @EnvironmentObject var store: MonitorStore
    @State private var section = Section.menuBar
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @FocusState private var windowFocused: Bool
    enum Section: String, CaseIterable, Identifiable {
        case general = "General", menuBar = "Menu Bar", monitors = "Monitors", appearance = "Appearance", about = "About"
        var id: String { rawValue }
        var symbol: String {
            switch self { case .general: "gearshape"; case .menuBar: "menubar.rectangle"; case .monitors: "slider.horizontal.3"; case .appearance: "paintpalette"; case .about: "info.circle" }
        }
    }
    private func preference<Value>(_ key: WritableKeyPath<MonitorPreferences, Value>) -> Binding<Value> {
        Binding(get: { store.preferences[keyPath: key] }, set: { value in store.updatePreferences { $0[keyPath: key] = value } })
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("zStats").font(.system(size: 17, weight: .semibold)).padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 18)
                ForEach(Section.allCases) { item in
                    SettingsNavigationButton(item.rawValue, symbol: item.symbol, selected: section == item) {
                        section = item
                    }
                }
                Spacer()
            }.padding(10).frame(width: 154).background(Color.panel)
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 0) {
                Text(section.rawValue).font(.system(size: 20, weight: .semibold)).padding(.horizontal, 24).padding(.top, 24)
                if section == .menuBar {
                    MenuBarSettingsView().environmentObject(store)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            switch section {
                            case .general: general
                            case .menuBar: EmptyView()
                            case .monitors: monitors
                            case .appearance: appearance
                            case .about: about
                            }
                        }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(width: 800, height: 650).background(Color.canvas).tint(Color(hex: 0x5B9CF6))
            .focusable().focusEffectDisabled().focused($windowFocused)
            .onAppear { windowFocused = true }
            .onChange(of: section) { _, _ in windowFocused = true }
            .onExitCommand { NSApp.keyWindow?.performClose(nil) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginStatus = SMAppService.mainApp.status }
    }
    private var general: some View {
        Group {
            SettingsCard("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch { loginError = error.localizedDescription }
                    loginStatus = SMAppService.mainApp.status
                })).toggleStyle(SettingsSwitchStyle())
                if loginStatus == .requiresApproval {
                    Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }.buttonStyle(.plain).foregroundStyle(Color(hex: 0x5B9CF6))
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                SettingsControlRow("Open dashboard to", labelWidth: 150) {
                    SettingsChoice("Open dashboard to", selection: preference(\.dashboardDefault), options: store.dashboardMetrics.map(\.rawValue)) { $0 }
                }
            }
            SettingsCard("Behavior") {
                Toggle("Show Dock icon", isOn: preference(\.showDockIcon)).toggleStyle(SettingsSwitchStyle())
                Toggle("Remember menu-bar position", isOn: preference(\.keepMenuBarPosition)).toggleStyle(SettingsSwitchStyle())
                SettingsControlRow("Temperature", labelWidth: 150) {
                    SettingsChoice("Temperature", selection: preference(\.temperatureUnit), options: TemperatureUnit.allCases) { $0.rawValue }
                }
            }
            SettingsCard("Sampling") {
                SettingsControlRow("Refresh interval", labelWidth: 150) {
                    SettingsChoice("Refresh interval", selection: preference(\.refreshInterval), options: [1.0, 2, 5, 10]) { "\(Int($0)) seconds" }
                }
                SettingsNote("Longer intervals use less energy. History is kept for 30 days.")
            }
        }
    }
    private var monitors: some View {
        Group {
            SettingsCard {
                ForEach(Array(Metric.monitorTabs.enumerated()), id: \.element.id) { index, metric in
                    if index > 0 { Divider().opacity(0.35) }
                    Toggle(isOn: Binding(get: { store.isEnabled(metric) }, set: { enabled in
                        store.updatePreferences {
                            if metric == .sensors { $0.sensorMonitoring = enabled }
                            else if enabled { $0.enabledMonitors.insert(metric.rawValue) }
                            else { $0.enabledMonitors.remove(metric.rawValue) }
                        }
                    })) {
                        HStack(spacing: 10) {
                            Image(systemName: metric.symbol).foregroundStyle(metric.color).frame(width: 18)
                            Text(metric == .memory ? "Memory (RAM)" : metric.rawValue)
                        }
                    }.toggleStyle(SettingsSwitchStyle())
                }
            }
            SettingsNote("Choose the monitors shown in the dashboard and menu panel. My Machine and Overview stay available.")
            SettingsNote("Disabling Network, GPU, or Projects also pauses their extra app monitoring.")
            SettingsNote("Disabling Sensors pauses temperature and fan readings, including CPU and GPU temperature widgets.")
        }
    }
    private var appearance: some View {
        Group {
            SettingsCard("Theme") {
                SettingsControlRow("Appearance", labelWidth: 150) {
                    SettingsChoice("Appearance", selection: $store.appearance, options: ["System", "Light", "Dark"]) { $0 }
                }
                SettingsNote("System follows your Mac’s appearance.")
            }
            SettingsCard("Readings") {
                Toggle("Show decimal figures", isOn: preference(\.preciseNumbers)).toggleStyle(SettingsSwitchStyle())
                SettingsNote("Applies to the main memory, disk, and network readings.")
                Divider().opacity(0.35)
                Toggle("Include system-owned processes", isOn: preference(\.showSystemProcesses)).toggleStyle(SettingsSwitchStyle())
                SettingsNote("Show system-owned processes alongside your apps.")
            }
        }
    }
    private var about: some View {
        Group {
            SettingsCard {
                HStack(spacing: 16) {
                    Image(nsImage: Bundle.main.url(forResource: "zStats", withExtension: "icns").flatMap { NSImage(contentsOf: $0) } ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("zStats").font(.system(size: 20, weight: .semibold))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.vertical, 8)
            }
            SettingsCard("On this Mac") {
                Text("Local system monitoring, from the menu bar to the details.")
                SettingsNote("System activity and 30 days of history stay on this Mac.")
            }
        }
    }
}
