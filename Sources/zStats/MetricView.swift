import SwiftUI
import StatsCore

struct MetricView: View {
    @EnvironmentObject var store: MonitorStore
    var metric: Metric
    private var s: SystemSnapshot { store.snapshot }
    private var historySummary: HistorySummary? { store.historySummary(for: metric) }
    var body: some View {
        VStack(spacing: 14) {
            Panel {
                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(headline).font(.system(size: 11)).foregroundStyle(.secondary)
                        let value = Format.value(metric, s, decimals: store.preferences.preciseNumbers ? 2 : 0)
                        ValueText(value: value.0, unit: value.1, size: 42)
                        if metric == .memory, let pressure = s.pressure { PressureBadge(pressure: pressure) }
                        Spacer()
                        ForEach(Array(heroStats.enumerated()), id: \.offset) { _, item in
                            HStack { Text(item.0).foregroundStyle(.secondary); Spacer(); Text(item.1).monospacedDigit() }.font(.system(size: 10))
                        }
                    }.frame(width: 166)
                    VStack(alignment: .trailing, spacing: 8) {
                        AreaHistory(values: store.chartHistory(for: metric), color: metric.color, ceiling: ceiling)
                        HStack {
                            Text(store.referenceMode ? "Reference history" : store.range == .live ? "Last 2 minutes" : "Recorded history · \(store.range.rawValue)")
                            Spacer(); Text("Now")
                        }.font(.system(size: 9)).foregroundStyle(.tertiary)
                    }.padding(.top, 8)
                }
            }.frame(height: 191)
            HStack(spacing: 14) {
                ForEach(Array(summary.enumerated()), id: \.offset) { _, item in
                    Panel(padding: 15) {
                        VStack(alignment: .leading, spacing: 10) {
                            MetricLabel(metric: metric, title: item.0)
                            Text(item.1).font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            Text(item.2).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }.frame(height: 110)
            AppTable(metric: metric)
        }
    }
    private var ceiling: Double? { switch metric { case .cpu, .gpu, .battery: 100; case .memory: s.memoryTotal; default: nil } }
    private var headline: String {
        switch metric {
        case .cpu: "Now"
        case .memory: "In use of \(Format.memory(s.memoryTotal, decimals: 0))"
        case .disk: "Free of \(Format.memory(s.diskTotal))"
        case .network: "Downloading"
        case .gpu: store.referenceMode ? "Apple M2 Max" : "GPU utilization"
        case .battery: s.battery == nil ? "No battery detected" : s.charging ? "Connected to power" : "On battery"
        default: metric.rawValue
        }
    }
    private var heroStats: [(String, String)] {
        switch metric {
        case .cpu: return [("Average", average), ("Load", Format.number(s.load, decimals: 2)), ("Temperature", StatusWidgetRenderer.temperature(s.cpuTemperature, preference: store.preferences.temperatureUnit))]
        case .memory: return [("Free", Format.memory(s.memoryUsed.map { max(0, s.memoryTotal - $0) })), ("Swap", Format.memory(s.swap))]
        case .disk: return [("Used", Format.memory(s.diskTotal - s.diskFree)), ("Writing", Format.rate(s.diskWrite))]
        case .network: return [("Session down", Format.memory(s.received)), ("Session up", Format.memory(s.sent))]
        case .gpu: return [("Average", average), ("Peak", Format.percent(historySummary?.maximum)), ("Temperature", StatusWidgetRenderer.temperature(s.gpuTemperature, preference: store.preferences.temperatureUnit))]
        case .battery: return [("Remaining", Format.duration(s.batteryMinutes)), ("Cycles", Format.number(s.batteryCycles))]
        default: return []
        }
    }
    private var average: String {
        Format.percent(historySummary?.average)
    }
    private var summary: [(String, String, String)] {
        switch metric {
        case .cpu: return [("User", Format.percent(s.userCPU), "Your apps"), ("System", Format.percent(s.systemCPU), "macOS"), ("Cores", "\(s.cores)", "Logical processors"), ("Top App", store.apps(for: .cpu).first?.name ?? "—", Format.percent(store.apps(for: .cpu).first?.cpu, decimals: 1))]
        case .memory: return [("App", Format.memory(s.memoryApp), "Application memory"), ("Wired", Format.memory(s.memoryWired), "Reserved by macOS"), ("Compressed", Format.memory(s.memoryCompressed), "Compressed in RAM"), ("Top App", store.apps(for: .memory).first?.name ?? "—", Format.memory(store.apps(for: .memory).first?.memory))]
        case .disk: return [("Reading", Format.rate(s.diskRead), "All physical disks"), ("Writing", Format.rate(s.diskWrite), "All physical disks"), ("Capacity", Format.memory(s.diskTotal), "Startup volume"), ("Top App", store.apps(for: .disk).first?.name ?? "—", Format.rate(store.apps(for: .disk).first?.writeRate))]
        case .network: return [("Uploading", Format.rate(s.upload), "Outbound traffic"), ("Downloaded", Format.memory(s.received), "Since zStats opened"), ("Uploaded", Format.memory(s.sent), "Since zStats opened"), ("Interface", s.interface, "Physical interfaces")]
        case .gpu: return [("Memory", Format.memory(s.gpuMemory), "GPU memory in use"), ("Average", average, "Selected time range"), ("Peak", Format.percent(historySummary?.maximum), "Selected time range"), ("Availability", s.gpu == nil ? "Unavailable" : "Available", "Device counters")]
        case .battery: return [("Power Draw", s.batteryWatts.map { Format.number($0, decimals: 1) + " W" } ?? "—", "Battery power"), ("Health", Format.percent(s.batteryHealth), "Maximum capacity"), ("Temperature", StatusWidgetRenderer.temperature(s.batteryTemperature, preference: store.preferences.temperatureUnit), "Battery sensor"), ("Cycles", Format.number(s.batteryCycles), "Charge cycles")]
        default: return []
        }
    }
}

struct AppTable: View {
    @EnvironmentObject var store: MonitorStore
    var metric: Metric
    @State private var selectedApp: AppReading?
    private var unavailable: Bool { !store.hasAppReadings(for: metric) }
    private var rows: [AppReading] { store.apps(for: metric, matching: store.search) }
    var body: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("App").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if !unavailable {
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass").font(.system(size: 10))
                            TextField("Filter apps", text: $store.search).textFieldStyle(.plain).font(.system(size: 11)).frame(width: 110)
                        }.foregroundStyle(.secondary)
                    }
                    Text(columnLabel).help(metric == .battery ? "CPU energy per second; excludes GPU, display, and other device power." : metric == .network ? "Download rate" : "Current app usage").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 120, alignment: .trailing)
                }.padding(.horizontal, 18).padding(.vertical, 13)
                if unavailable {
                    VStack(spacing: 13) {
                        Image(systemName: metric.symbol).font(.system(size: 27, weight: .light)).foregroundStyle(metric.color.opacity(0.7))
                        Text("Per-app \(metric == .battery ? "power" : metric.rawValue.lowercased()) is unavailable").font(.system(size: 14, weight: .medium))
                        Text("\(metric == .network ? "System network totals are shown above." : metric == .gpu ? "Device utilization is shown when macOS exposes it." : "Battery readings are shown above when available.")\nWaiting for readable app counters from macOS.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rows.isEmpty {
                    ContentUnavailableView.search(text: store.search).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, app in
                                Button { selectedApp = app } label: {
                                    HStack(spacing: 12) {
                                        AppIcon(path: app.bundlePath)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                            Text("\(app.processes.count) \(app.processes.count == 1 ? "process" : "processes")").font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 7) {
                                            Text(display(app, index: index)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                                            GeometryReader { proxy in
                                                Capsule().fill(metric.color.opacity(0.1))
                                                    .overlay(alignment: .leading) { Capsule().fill(metric.color).frame(width: max(0, proxy.size.width * fraction(app, index: index))) }
                                            }.frame(width: 145, height: 3)
                                        }
                                    }.padding(.horizontal, 18).padding(.vertical, 11).contentShape(Rectangle())
                                }.buttonStyle(RowButtonStyle())
                            }
                        }
                    }.scrollIndicators(.automatic)
                }
            }
        }.sheet(item: $selectedApp) { app in AppDetailSheet(app: app).environmentObject(store) }
    }
    private var columnLabel: String { metric == .disk ? "Disk writes" : metric == .battery ? "CPU Power" : metric == .network ? "Download / Upload" : metric.rawValue }
    private func value(_ app: AppReading, index: Int) -> Double {
        switch metric { case .cpu: app.cpu ?? 0; case .memory: app.memory ?? 0; case .disk: app.writeRate ?? 0; case .network: app.download ?? 0; case .gpu: app.gpu ?? 0; case .battery: app.cpuWatts ?? 0; default: 0 }
    }
    private func display(_ app: AppReading, index: Int) -> String {
        switch metric {
        case .memory: Format.memory(app.memory)
        case .cpu: Format.percent(app.cpu, decimals: 1)
        case .disk: Format.rate(app.writeRate)
        case .network: "↓ " + Format.rate(app.download) + " · ↑ " + Format.rate(app.upload)
        case .gpu: Format.percent(app.gpu, decimals: 1)
        case .battery: app.cpuWatts.map { Format.number($0, decimals: 2) + " W" } ?? "—"
        default: "—"
        }
    }
    private func fraction(_ app: AppReading, index: Int) -> Double {
        let maximum = rows.enumerated().map { value($0.element, index: $0.offset) }.max() ?? 1
        return min(1, value(app, index: index) / max(1e-9, maximum))
    }
}

struct RowButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Color.primary.opacity(configuration.isPressed ? 0.06 : hovered ? 0.025 : 0)).onHover { hovered = $0 }
    }
}

struct AppDetailSheet: View {
    @EnvironmentObject var store: MonitorStore
    @Environment(\.dismiss) var dismiss
    var app: AppReading
    private var currentApp: AppReading {
        if let live = store.snapshot.apps.first(where: { $0.id == app.id }) { return live }
        var exited = app; exited.processes = []; return exited
    }
    @State private var pending: [ProcessReading] = []
    @State private var confirm = false
    @State private var force = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                AppIcon(path: app.bundlePath, size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(app.name).font(.system(size: 21, weight: .semibold))
                    Text("\(currentApp.processes.count) \(currentApp.processes.count == 1 ? "process" : "processes") · \(Format.memory(currentApp.memory)) · \(Format.percent(currentApp.cpu, decimals: 1)) CPU").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("CPU uses one core as 100%. Memory is the sum of reported process footprints.").font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(currentApp.processes.sorted { ($0.memory ?? 0) > ($1.memory ?? 0) }) { process in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(process.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text("PID \(process.pid)").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(); Text(Format.memory(process.memory)).monospacedDigit().font(.system(size: 11))
                            Button("Stop…") { pending = [process]; force = false; confirm = true }.disabled(!canStop(process))
                        }.padding(.vertical, 10)
                        Divider().opacity(0.3)
                    }
                }
            }.frame(height: 290)
            HStack {
                if store.referenceMode { Text("Reference data · process actions disabled").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                Button("Force Quit…", role: .destructive) { pending = currentApp.processes.filter(canStop); force = true; confirm = true }.disabled(!currentApp.processes.contains(where: canStop))
                Button("Quit App…") { pending = currentApp.processes.filter(canStop); force = false; confirm = true }.disabled(!currentApp.processes.contains(where: canStop))
            }
        }.padding(24).frame(width: 590).background(Color.canvas)
            .alert(force ? "Force quit \(app.name)?" : "Stop \(pending.count) processes?", isPresented: $confirm) {
                Button("Cancel", role: .cancel) {}
                Button(force ? "Force Quit" : "Stop", role: .destructive) { store.terminate(pending, force: force); dismiss() }
            } message: { Text("Unsaved work may be lost. Each process will be checked again before it is stopped.") }
    }
    private func canStop(_ p: ProcessReading) -> Bool { !store.referenceMode && p.uid == getuid() && p.pid > 1 && p.pid != getpid() && p.started > 0 }
}
