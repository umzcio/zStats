import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: MonitorStore
    @Environment(\.openSettings) private var openSettings
    @FocusState private var windowFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("zStats").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 68, alignment: .leading)
                Spacer(minLength: 0)
                ViewThatFits { TabStrip(); TabStrip(compact: true) }
                Spacer(minLength: 0)
                Button { openSettings(); NSApp.activate(ignoringOtherApps: true) } label: {
                    Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 28, height: 28)
                }.buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
            }.padding(.horizontal, 20).frame(height: 51)
            Group {
                switch store.selected {
                case .machine: MachineView()
                case .overview: OverviewView()
                case .projects: ProjectsView()
                case .sensors: SensorsView()
                default: MetricView(metric: store.selected).id(store.selected)
                }
            }.padding(.horizontal, 20).padding(.bottom, 10)
            if store.selected != .machine { footer }
        }.frame(minWidth: 900, minHeight: 660).background(Color.canvas)
            .focusable().focusEffectDisabled().focused($windowFocused)
            .onAppear { windowFocused = true }
            .onExitCommand { NSApp.keyWindow?.performClose(nil) }
            .onChange(of: store.selected) { _, _ in store.search = ""; windowFocused = true }
            .alert("zStats", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(store.referenceMode ? Metric.projects.color : Metric.network.color).frame(width: 5, height: 5)
            Text(store.referenceMode ? "Reference data" : store.sampled ? "Live" : "Loading…").font(.system(size: 10, weight: .medium))
            if store.referenceMode { Text("Simulated readings").font(.system(size: 10)).foregroundStyle(.tertiary) }
            else { Text("\(store.snapshot.apps.count) groups · \(store.snapshot.apps.reduce(0) { $0 + $1.processes.count }) processes").font(.system(size: 10)).foregroundStyle(.tertiary) }
            Spacer()
            if store.selected != .projects && store.selected != .sensors {
                HStack(spacing: 2) {
                    ForEach(HistoryRange.allCases, id: \.self) { range in
                        Button { store.range = range } label: {
                            Text(range.rawValue).font(.system(size: 10, weight: store.range == range ? .medium : .regular)).padding(.horizontal, 8).padding(.vertical, 4)
                                .foregroundStyle(store.range == range ? Color.primary : .secondary)
                                .background(store.range == range ? Color.primary.opacity(0.065) : Color.clear, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            Text("Up \(Int(store.snapshot.uptime) / 86400)d \(Int(store.snapshot.uptime) / 3600 % 24)h").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 24).frame(height: 33)
    }
}

struct TabStrip: View {
    @EnvironmentObject var store: MonitorStore
    var compact = false
    var body: some View {
        HStack(spacing: 2) {
            ForEach(store.dashboardMetrics) { metric in
                Button { store.selected = metric } label: {
                    HStack(spacing: 5) {
                        Image(systemName: metric.symbol).font(.system(size: compact ? 12 : 10))
                        if !compact { Text(metric.rawValue).font(.system(size: 11, weight: .medium)) }
                    }.foregroundStyle(store.selected == metric ? metric.color : .secondary)
                        .padding(.horizontal, compact ? 10 : 11).frame(height: 31)
                        .background(store.selected == metric ? metric.color.opacity(0.12) : Color.clear, in: Capsule())
                }.buttonStyle(.plain).help(metric.rawValue).accessibilityLabel(metric.rawValue).accessibilityAddTraits(store.selected == metric ? [.isSelected] : [])
            }
        }.padding(3).background(Color.panel.opacity(0.65), in: Capsule())
    }
}
