import SwiftUI
import StatsCore

struct MenuPanel: View {
    static let size = size(for: .overview)
    static func size(for metric: Metric, monitors: [Metric] = Metric.monitors) -> CGSize {
        let height: CGFloat
        switch metric {
        case .machine, .overview:
            let cards = monitors.filter { $0 != .projects }.count
            let rows = (cards + 1) / 2
            let gridHeight = rows > 0 ? CGFloat(rows * 100 - 8) : 90
            height = 143 + gridHeight + (monitors.contains(.cpu) ? 133 : 0)
        case .cpu: height = 501
        case .battery: height = 476
        case .memory: height = 521
        case .disk, .network: height = 451
        case .gpu: height = 451
        case .projects: height = 450
        case .sensors: height = 435
        }
        return CGSize(width: 372, height: height)
    }
    @EnvironmentObject var store: MonitorStore
    @Environment(\.openWindow) var openWindow
    var openDashboard: (() -> Void)?
    var onSelectionChange: ((Metric) -> Void)?
    private var selected: Metric { store.menuSelection }
    var openPreferences: (() -> Void)?

    init(openDashboard: (() -> Void)? = nil, onSelectionChange: ((Metric) -> Void)? = nil, openPreferences: (() -> Void)? = nil) {
        self.openPreferences = openPreferences
        self.openDashboard = openDashboard
        self.onSelectionChange = onSelectionChange
    }
    private var s: SystemSnapshot { store.snapshot }

    var body: some View {
        VStack(spacing: 10) {
            tabs
            HStack {
                Text(selected.rawValue.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1)
                if store.referenceMode { Text("DEMO").font(.system(size: 8, weight: .medium)).foregroundStyle(Metric.projects.menuColor) }
                Spacer()
                if selected == .overview {
                    Label("Up \(Int(s.uptime) / 86400)d \(Int(s.uptime) / 3600 % 24)h", systemImage: "clock")
                        .font(.system(size: 10))
                }
            }.foregroundStyle(.secondary).padding(.horizontal, 6).frame(height: 16)
            Group {
                if selected == .sensors {
                    MenuSensorsDetail()
                } else if selected == .projects {
                    MenuProjectsDetail()
                } else if selected == .overview {
                    VStack(spacing: 10) {
                        if store.enabledMetrics.filter({ $0 != .projects }).isEmpty {
                            Text("Choose monitors in Settings").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 90)
                        } else { LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                            ForEach([Metric.cpu, .memory, .network, .disk, .gpu, .battery].filter { store.isEnabled($0) }) { metric in
                                Button { store.menuSelection = metric } label: { MenuMetricCard(metric: metric) }
                                    .buttonStyle(.plain).accessibilityLabel(metric.rawValue)
                                    .accessibilityValue(Format.value(metric, s, decimals: store.preferences.preciseNumbers ? 2 : 0).0 + " " + Format.value(metric, s, decimals: store.preferences.preciseNumbers ? 2 : 0).1)
                            }
                        } }
                        if store.isEnabled(.cpu) { topApps }
                    }
                } else {
                    MenuDetailCard(metric: selected)
                }
            }.frame(height: Self.size(for: selected, monitors: store.enabledMetrics).height - 143)
            footer
        }.padding(12).frame(width: Self.size.width, height: Self.size(for: selected, monitors: store.enabledMetrics).height)
            .background(Color.canvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.09), lineWidth: 1))

            .onChange(of: selected) { _, metric in onSelectionChange?(metric) }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(store.menuMetrics) { metric in
                Button { store.menuSelection = metric } label: {
                    MenuMetricIcon(metric: metric)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .foregroundStyle(selected == metric ? Color.white : Color.secondary)
                        .background(selected == metric ? (metric == .overview ? Color(hex: 0x347FF5) : metric.menuColor) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.plain).help(metric.rawValue).accessibilityLabel(metric.rawValue)
                    .accessibilityAddTraits(selected == metric ? [.isSelected] : [])
            }
        }.padding(4).frame(height: 38).background(Color.menuCard, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var topApps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Busiest Right Now").font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 15)
            ForEach(store.apps(for: .cpu).prefix(3)) { app in
                HStack(spacing: 9) {
                    AppIcon(path: app.bundlePath, size: 16)
                    Text(app.name).lineLimit(1)
                    Spacer(minLength: 0)
                    Capsule().fill(Metric.cpu.menuColor.opacity(0.12)).frame(width: 56, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Metric.cpu.menuColor).frame(width: 56 * min(1, max(0, app.cpu ?? 0) / 50), height: 4)
                        }
                    Text(Format.percent(app.cpu, decimals: 1)).monospacedDigit().frame(width: 56, alignment: .trailing)
                }.font(.system(size: 12)).frame(height: 18)
            }
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 123, maxHeight: 123, alignment: .topLeading)
            .background(Color.menuCard, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                store.selected = selected
                if let openDashboard { openDashboard() }
                else { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
            } label: { HStack(spacing: 8) { MenuGlyph(kind: .window); Text("Open zStats") }.frame(maxWidth: .infinity).frame(height: 35) }
            Button { openPreferences?() } label: { Image(systemName: "gearshape").frame(width: 32, height: 35) }
                .accessibilityLabel("Settings").help("Settings")
            Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power").frame(width: 76, height: 35) }
        }.font(.system(size: 13)).buttonStyle(MenuFooterButtonStyle()).frame(height: 35)
    }
}

private struct MenuMetricCard: View {
    @EnvironmentObject var store: MonitorStore
    var metric: Metric
    private var s: SystemSnapshot { store.snapshot }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                MenuMetricIcon(metric: metric).foregroundStyle(metric.menuColor)
                Text(metric.rawValue).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }.frame(height: 15)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if metric == .network { Image(systemName: "arrow.down").font(.system(size: 10)).foregroundStyle(.secondary) }
                let value = Format.value(metric, s, decimals: store.preferences.preciseNumbers ? 2 : 0)
                ValueText(value: value.0, unit: value.1, size: 23)
                Spacer(minLength: 2)
                Text(annotation).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }.frame(height: 29)
            Group {
                if metric == .disk || metric == .battery {
                    GeometryReader { proxy in
                        Capsule().fill(metric.menuColor.opacity(0.15))
                            .overlay(alignment: .leading) { Capsule().fill(metric.menuColor).frame(width: proxy.size.width * fraction) }
                    }.frame(height: 6).frame(maxHeight: .infinity, alignment: .bottom)
                } else {
                    MenuSparkline(values: store.chartHistory(for: metric), color: metric.menuColor)
                }
            }.frame(height: 20)
        }.padding(10).frame(maxWidth: .infinity).frame(height: 92)
            .background(Color.menuCard, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
    private var annotation: String {
        switch metric {
        case .cpu: return "load " + Format.number(s.load, decimals: 2)
        case .memory: return "of " + Format.memory(s.memoryTotal, decimals: 0)
        case .network: return "↑ " + Format.rate(s.upload)
        case .disk: return "free"
        case .battery: return s.charging ? "Connected to power" : s.batteryMinutes == nil ? "" : Format.duration(s.batteryMinutes) + " left"
        default: return ""
        }
    }
    private var fraction: Double {
        let value = metric == .battery ? (s.battery ?? 0) / 100 : s.diskTotal > 0 ? (s.diskTotal - s.diskFree) / s.diskTotal : 0
        return min(1, max(0, value))
    }
}

struct MenuSparkline: View {
    var values: [Double?]
    var color: Color
    var body: some View {
        Canvas { context, size in
            // Use the available time span while history warms up after launch.
            // Keep gaps within that span; never invent samples to fill them.
            let samples = Array(values.drop(while: { $0 == nil }))
            let maximum = max(1, (samples.compactMap { $0 }.max() ?? 1) * 1.15)
            var segments: [[CGPoint]] = []
            var current: [CGPoint] = []
            for (index, value) in samples.enumerated() {
                guard let value else { if !current.isEmpty { segments.append(current); current = [] }; continue }
                current.append(CGPoint(x: size.width * Double(index) / Double(max(1, samples.count - 1)), y: 1 + (size.height - 2) * (1 - min(1, max(0, value) / maximum))))
            }
            if !current.isEmpty { segments.append(current) }
            for segment in segments {
                guard let first = segment.first, let last = segment.last else { continue }
                if segment.count == 1 { context.fill(Path(ellipseIn: CGRect(x: first.x - 1, y: first.y - 1, width: 2, height: 2)), with: .color(color)); continue }
                var line = Path(); line.addLines(segment)
                var fill = line
                fill.addLine(to: CGPoint(x: last.x, y: size.height)); fill.addLine(to: CGPoint(x: first.x, y: size.height)); fill.closeSubpath()
                context.fill(fill, with: .color(color.opacity(0.14)))
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }.accessibilityLabel("Recent history")
    }
}

extension Color {
    static let menuCard = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.149, green: 0.149, blue: 0.157, alpha: 1) : .white
    })
}

private struct MenuFooterButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.primary)
            .background(Color.menuCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(configuration.isPressed ? 0.08 : hovered ? 0.035 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).onHover { hovered = $0 }
    }
}

// The compact menu uses the reference's quieter, solid category colors.
extension Metric {
    var menuColor: Color {
        switch self {
        case .machine, .overview: Color(hex: 0x347FF5)
        case .cpu: Color(hex: 0x5086E1)
        case .memory: Color(hex: 0x9282DF)
        case .disk: Color(hex: 0xBD8928)
        case .network: Color(hex: 0x499E7D)
        case .gpu: Color(hex: 0xC75281)
        case .battery: Color(hex: 0x53AA40)
        case .projects: Color(hex: 0xC65D31)
        case .sensors: Color(hex: 0xE68752)
        }
    }
    var menuSymbol: String {
        switch self {
        case .network: "globe"
        case .disk: "externaldrive"
        default: symbol
        }
    }
}
