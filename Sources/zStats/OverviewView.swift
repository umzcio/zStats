import SwiftUI
import StatsCore

struct OverviewView: View {
    @EnvironmentObject var store: MonitorStore
    private let metrics: [Metric] = [.cpu, .memory, .gpu, .disk, .network, .battery]
    var body: some View {
        GeometryReader { geometry in
            // Preserve the cards' content height when the window shrinks; the
            // surrounding scroll view handles the remaining vertical space.
            let cardHeight = max(218, (geometry.size.height - 190) / 2)
            ScrollView {
                VStack(spacing: 14) {
                    if metrics.filter({ store.isEnabled($0) }).isEmpty {
                        ContentUnavailableView("No monitors selected", systemImage: "slider.horizontal.3", description: Text("Choose monitors in Settings to see them here."))
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                        ForEach(metrics.filter { store.isEnabled($0) }) { metric in
                            Button { store.selected = metric } label: { OverviewCard(metric: metric).frame(height: cardHeight) }
                                .buttonStyle(.plain).accessibilityLabel("Open \(metric.rawValue)")
                        }
                    }
                    HStack(spacing: 14) {
                        if store.isEnabled(.memory) { BreakdownCard(kind: .types); BreakdownCard(kind: .apps) }
                        if store.isEnabled(.battery) { BreakdownCard(kind: .power) }
                    }.frame(height: 164)
                }
            }.scrollIndicators(.hidden)
        }
    }
}

struct OverviewCard: View {
    @EnvironmentObject var store: MonitorStore
    var metric: Metric
    @State private var hovered = false
    private var s: SystemSnapshot { store.snapshot }
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack { MetricLabel(metric: metric); Spacer(); Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(caption).font(.system(size: 10)).foregroundStyle(.secondary)
                    HStack {
                        let value = Format.value(metric, s, decimals: store.preferences.preciseNumbers ? 2 : 0)
                        ValueText(value: value.0, unit: value.1)
                        Spacer(minLength: 2)
                        if metric == .memory { PressureBadge(pressure: s.pressure) }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) { stats }
                BarHistory(values: store.chartHistory(for: metric), color: metric.color, ceiling: ceiling).frame(height: 39)
            }
        }.overlay(RoundedRectangle(cornerRadius: 16).stroke(metric.color.opacity(hovered ? 0.24 : 0), lineWidth: 1))
            .onHover { hovered = $0 }
    }
    private var ceiling: Double? { switch metric { case .cpu, .gpu, .battery: 100; case .memory: s.memoryTotal; default: nil } }
    private var caption: String {
        switch metric {
        case .cpu: "Now"
        case .memory: "In Use of \(Format.memory(s.memoryTotal, decimals: 0))"
        case .gpu: store.referenceMode ? "Apple M2 Max" : "GPU utilization"
        case .disk: "Free of \(Format.memory(s.diskTotal))"
        case .network: "Downloading"
        case .battery: s.battery == nil ? "No battery detected" : s.charging ? "Connected to Power" : "On Battery"
        default: ""
        }
    }
    @ViewBuilder private var stats: some View {
        switch metric {
        case .cpu:
            MiniStat(label: "User", value: Format.percent(s.userCPU)); MiniStat(label: "System", value: Format.percent(s.systemCPU))
            MiniStat(label: "Load Average", value: Format.number(s.load, decimals: 2))
        case .memory:
            MiniStat(label: "App", value: Format.memory(s.memoryApp), dot: Metric.cpu.color)
            MiniStat(label: "Wired", value: Format.memory(s.memoryWired), dot: Metric.projects.color)
            MiniStat(label: "Compressed", value: Format.memory(s.memoryCompressed), dot: Metric.network.color)
        case .gpu:
            MiniStat(label: "Memory", value: Format.memory(s.gpuMemory))
            MiniStat(label: "Average", value: average(.gpu)); MiniStat(label: "Peak", value: Format.percent(store.historySummary(for: .gpu)?.maximum))
        case .disk:
            MiniStat(label: "Reading", value: Format.rate(s.diskRead)); MiniStat(label: "Writing", value: Format.rate(s.diskWrite))
            MiniStat(label: "Used", value: Format.memory(s.diskTotal - s.diskFree, decimals: 1))
        case .network:
            MiniStat(label: "Uploading", value: Format.rate(s.upload)); MiniStat(label: "This Session", value: Format.memory(s.received, decimals: 1))
            MiniStat(label: "Interface", value: s.interface)
        case .battery:
            MiniStat(label: "Remaining", value: Format.duration(s.batteryMinutes))
            MiniStat(label: "Power Draw", value: s.batteryWatts.map { Format.number($0, decimals: 1) + " W" } ?? "—")
            MiniStat(label: "Health", value: Format.percent(s.batteryHealth))
        default: EmptyView()
        }
    }
    private func average(_ metric: Metric) -> String {
        Format.percent(store.historySummary(for: metric)?.average)
    }
}

struct PressureBadge: View {
    var pressure: Int
    private var label: String { pressure >= 4 ? "High" : pressure >= 2 ? "Elevated" : "Normal" }
    private var color: Color { pressure >= 4 ? .red : pressure >= 2 ? .orange : Metric.battery.color }
    var body: some View {
        Text("✓ \(label)").font(.system(size: 9, weight: .medium)).foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 4).background(color.opacity(0.12), in: Capsule())
    }
}

struct BreakdownCard: View {
    enum Kind { case types, apps, power }
    @EnvironmentObject var store: MonitorStore
    var kind: Kind
    private var s: SystemSnapshot { store.snapshot }
    private var metric: Metric { kind == .types ? .cpu : kind == .apps ? .memory : .battery }
    private var title: String { kind == .types ? "Memory by Type" : kind == .apps ? "Memory by App" : "CPU Power by App" }
    private var colors: [Color] { kind == .types ? [Metric.cpu.color, Metric.projects.color, Metric.network.color, Color(hex: 0x44586E), Color.gray.opacity(0.3)] : (0..<5).map { metric.color.opacity(1 - Double($0) * 0.16) } }
    private var rows: [(String, Double)] {
        switch kind {
        case .types: return [("App", s.memoryApp), ("Wired", s.memoryWired), ("Compressed", s.memoryCompressed), ("Cached", s.memoryCached), ("Free", max(0, s.memoryTotal - s.memoryUsed - s.memoryCached))]
        case .apps:
            let apps = s.apps.sorted { ($0.memory ?? 0) > ($1.memory ?? 0) }
            return apps.prefix(4).map { ($0.name, $0.memory ?? 0) } + [("Other", apps.dropFirst(4).reduce(0) { $0 + ($1.memory ?? 0) })]
        case .power:
            guard s.powerAppsAvailable else { return [] }
            let apps = store.apps(for: .battery).filter { $0.cpuWatts != nil }
            return apps.prefix(4).map { ($0.name, $0.cpuWatts ?? 0) } + [("Other", apps.dropFirst(4).reduce(0) { $0 + ($1.cpuWatts ?? 0) })]
        }
    }
    var body: some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                MetricLabel(metric: metric, title: title)
                HStack(spacing: 12) {
                    Donut(segments: rows.enumerated().map { .init(value: $0.element.1, color: colors[$0.offset % colors.count]) }, value: center, subtitle: kind == .types ? "in use" : "all apps")
                    if rows.isEmpty {
                        Text("Per-app power\nis unavailable.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                HStack(spacing: 5) {
                                    Circle().fill(colors[index % colors.count]).frame(width: 5, height: 5)
                                    Text(row.0).lineLimit(1).truncationMode(.tail)
                                    Spacer(minLength: 3)
                                    Text(kind == .power ? "\(Int(row.1 * 1000)) mW" : Format.memory(row.1)).foregroundStyle(.secondary).monospacedDigit().fixedSize()
                                }.font(.system(size: 9))
                            }
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
    private var center: String {
        switch kind {
        case .types: Format.percent(s.memoryTotal > 0 ? s.memoryUsed / s.memoryTotal * 100 : nil)
        case .apps: Format.memory(s.apps.reduce(0) { $0 + ($1.memory ?? 0) })
        case .power: s.powerAppsAvailable ? Format.number(rows.reduce(0) { $0 + $1.1 }, decimals: 2) + " W" : "—"
        }
    }
}
