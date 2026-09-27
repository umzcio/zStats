import SwiftUI
import StatsCore
import Darwin

struct MenuDetailCard: View {
    @EnvironmentObject private var store: MonitorStore
    let metric: Metric
    private var s: SystemSnapshot { store.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero.frame(height: 50)
            Color.clear.frame(height: 6)
            if metric == .memory { memoryBar.frame(height: 6).padding(.vertical, 7) }
            statistics
            Divider().padding(.vertical, 10)
            rankings
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.menuCard, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var hero: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if metric == .network { Image(systemName: "arrow.down").font(.system(size: 13)).foregroundStyle(.secondary) }
                    let value = Format.value(metric, s, decimals: store.preferences.preciseNumbers ? 2 : 0)
                    ValueText(value: value.0, unit: value.1 + (metric == .disk ? " free" : ""), size: 30)
                }.frame(height: 33, alignment: .leading)
                HStack(spacing: 6) {
                    Text(subtitle).lineLimit(1)
                    if metric == .memory {
                        Text(s.pressure >= 4 ? "High" : s.pressure >= 2 ? "Elevated" : "Normal")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(pressureColor)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(pressureColor.opacity(0.14), in: Capsule())
                    }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if metric == .disk || metric == .battery {
                    MenuMeter(fraction: metric == .disk ? (s.diskTotal - s.diskFree) / max(1, s.diskTotal) : (s.battery ?? 0) / 100, color: metric.menuColor)
                        .frame(height: 6)
                } else {
                    MenuSparkline(values: store.chartHistory(for: metric), color: metric.menuColor)
                        .frame(height: 38)
                }
            }.frame(width: 112).offset(y: metric == .disk ? 11 : 0)
        }
    }

    private var subtitle: String {
        switch metric {
        case .cpu, .gpu: return store.referenceMode ? "Apple M2 Max" : HardwareName.chip
        case .memory: return "of " + Format.memory(s.memoryTotal, decimals: 0)
        case .disk: return Format.memory(s.diskTotal - s.diskFree) + " used of " + Format.memory(s.diskTotal)
        case .network: return "↑ " + Format.rate(s.upload)
        case .battery: return s.charging ? "Charging" : s.batteryMinutes.map { Format.duration($0) + " left" } ?? "On battery"
        default: return ""
        }
    }
    private var pressureColor: Color { s.pressure >= 4 ? .red : s.pressure >= 2 ? .orange : Metric.battery.menuColor }

    @ViewBuilder private var statistics: some View {
        switch metric {
        case .cpu:
            stat("User", Format.percent(s.userCPU))
            stat("System", Format.percent(s.systemCPU))
            stat("Load Average", Format.number(s.load, decimals: 2))
            stat("Temperature", StatusWidgetRenderer.temperature(s.cpuTemperature, preference: store.preferences.temperatureUnit))
        case .memory:
            stat("App", Format.memory(s.memoryApp), dot: Metric.cpu.menuColor)
            stat("Wired", Format.memory(s.memoryWired), dot: Color(hex: 0xC65D31))
            stat("Compressed", Format.memory(s.memoryCompressed), dot: Metric.network.menuColor)
            stat("Swap Used", s.swap == 0 ? "0 MB" : Format.memory(s.swap))
        case .disk:
            stat("Reading", Format.rate(s.diskRead))
            stat("Writing", Format.rate(s.diskWrite))
        case .network:
            stat("Downloaded This Session", Format.memory(s.received, decimals: 1))
            stat("Uploaded This Session", Format.memory(s.sent, decimals: 0))
        case .gpu:
            stat("GPU Memory in Use", Format.memory(s.gpuMemory))
            stat("Temperature", StatusWidgetRenderer.temperature(s.gpuTemperature, preference: store.preferences.temperatureUnit))
        case .battery:
            stat("Power Draw", s.batteryWatts.map { Format.number($0, decimals: 1) + " W" } ?? "—")
            stat("Maximum Capacity", Format.percent(s.batteryHealth))
            stat("Cycle Count", Format.number(s.batteryCycles))
        default: EmptyView()
        }
    }

    private func stat(_ label: String, _ value: String, dot: Color? = nil) -> some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).monospacedDigit()
        }.font(.system(size: 12)).frame(height: 25)
    }

    private var memoryBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(Array(zip([s.memoryApp, s.memoryWired, s.memoryCompressed], [Metric.cpu.menuColor, Color(hex: 0xC65D31), Metric.network.menuColor]).enumerated()), id: \.offset) { _, segment in
                    Rectangle().fill(segment.1).frame(width: max(0, (proxy.size.width - 4) * min(1, segment.0 / max(1, s.memoryTotal))))
                }
                Spacer(minLength: 0)
            }.clipShape(Capsule())
        }
    }

    private var rankingTitle: String {
        switch metric {
        case .disk: "Top Apps by Disk Writes"
        case .network: "Top Apps by Download"
        case .battery: "Top Apps by CPU Power"
        default: "Top Apps"
        }
    }
    private var supportsLiveRanking: Bool { store.hasAppReadings(for: metric) }
    private var rows: [MenuAppRow] {
        guard supportsLiveRanking else { return [] }
        return store.apps(for: metric).compactMap { app in
            let amount: Double?
            let value: String
            switch metric {
            case .cpu: amount = app.cpu; value = Format.percent(amount, decimals: 1)
            case .disk: amount = app.writeRate; value = Format.rate(amount)
            case .network: amount = app.download; value = Format.rate(amount)
            case .gpu: amount = app.gpu; value = Format.percent(amount, decimals: 1)
            case .battery: amount = app.cpuWatts; value = Format.number(amount, decimals: 2) + " W"
            default: amount = app.memory; value = Format.memory(amount, decimals: (amount ?? 0) >= 1e9 ? 2 : 0)
            }
            guard amount != nil else { return nil }
            return MenuAppRow(id: app.id, name: app.name, path: app.bundlePath, amount: amount, value: value, upload: app.upload)
        }.prefix(5).map { $0 }
    }
    private var rankings: some View {
        let apps = rows
        let maximum = max(1e-9, apps.compactMap(\.amount).max() ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            Text(rankingTitle).help(metric == .battery ? "CPU energy per second reported by macOS. Excludes GPU, display, and other device power." : metric == .gpu ? "GPU execution time per second; concurrent queues can exceed 100%." : "Most active apps in the latest sample").font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 18, alignment: .top)
            if !supportsLiveRanking {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Per-app readings unavailable").foregroundStyle(.primary)
                    Text("Waiting for macOS app counters. System readings are shown above.").foregroundStyle(.secondary)
                }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            } else if apps.isEmpty {
                Text("Waiting for app readings…").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 12)
            } else {
                ForEach(apps) { app in
                    HStack(spacing: 9) {
                        AppIcon(path: app.path, size: 15)
                        Text(app.name).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                        MenuMeter(fraction: (app.amount ?? 0) / maximum, color: metric.menuColor).frame(width: 56, height: 4)
                        Text(app.value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85).frame(width: 63, alignment: .trailing)
                    }.font(.system(size: 12)).frame(height: 25)
                        .help(metric == .network ? "↓ " + app.value + " · ↑ " + Format.rate(app.upload) : app.name + " · " + app.value)
                }
            }
        }.frame(maxWidth: .infinity, minHeight: 143, alignment: .topLeading)
    }
}

private struct MenuAppRow: Identifiable {
    let id: String
    let name: String
    let path: String?
    let amount: Double?
    let value: String
    var upload: Double? = nil
}

struct MenuMeter: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(color.opacity(0.14)).overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
    }
}

struct MenuProjectsDetail: View {
    @EnvironmentObject private var store: MonitorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ValueText(value: String(store.projects.count), unit: "projects", size: 30).frame(height: 35, alignment: .leading)
            Text(Format.memory(store.projects.reduce(0) { $0 + $1.memory }) + " · \(store.projects.reduce(0) { $0 + $1.ports.count }) ports open")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 3)
            Divider().padding(.top, 12).padding(.bottom, 10)
            Text("Running Now").font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 20, alignment: .top)
            ForEach(store.projects.prefix(6)) { project in
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(Metric.projects.menuColor).font(.system(size: 12))
                    Text(project.name).lineLimit(1).layoutPriority(1)
                    ForEach(project.ports.prefix(2), id: \.self) { port in
                        Text(String(port)).font(.system(size: 10, weight: .semibold)).foregroundStyle(Metric.battery.menuColor)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Metric.battery.menuColor.opacity(0.14), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Text(Format.memory(project.memory, decimals: project.memory >= 1e9 ? 2 : 0)).monospacedDigit().fixedSize()
                }.font(.system(size: 12)).frame(height: 26)
            }
            if store.projects.count > 6 {
                Text("and \(store.projects.count - 6) more in zStats").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 6)
            } else if store.projects.isEmpty {
                Text("No development servers detected.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.menuCard, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

enum HardwareName {
    static let chip: String = {
        var length = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &length, nil, 0) == 0, length > 0 else { return "Processor" }
        var bytes = [CChar](repeating: 0, count: length)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &length, nil, 0) == 0 else { return "Processor" }
        return String(cString: bytes)
    }()
}
