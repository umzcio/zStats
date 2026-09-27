import SwiftUI
import StatsCore

struct MenuBarSettingsView: View {
    @EnvironmentObject var store: MonitorStore
    @State private var selection: UUID?
    private var widgets: [StatusWidget] { store.preferences.resolvedWidgets }
    private var selected: StatusWidget? { widgets.first { $0.id == selection } ?? widgets.first }
    private func update(_ edit: (inout [StatusWidget]) -> Void) {
        store.updatePreferences { p in var items = p.resolvedWidgets; edit(&items); p.widgets = items }
    }
    private func field<Value>(_ widget: StatusWidget, _ key: WritableKeyPath<StatusWidget, Value>) -> Binding<Value> {
        Binding(get: { widgets.first { $0.id == widget.id }?[keyPath: key] ?? widget[keyPath: key] }, set: { value in
            update { items in if let i = items.firstIndex(where: { $0.id == widget.id }) { items[i][keyPath: key] = value } }
        })
    }
    var body: some View {
        VStack(spacing: 0) {
        preview.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 4)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Menu-bar items").font(.headline)
                    Spacer()
                    SettingsActionMenu("Presets", chevron: true) {
                        ForEach(MenuBarPreset.allCases, id: \.self) { preset in
                            Button(preset.rawValue) { let items = preset.widgets(); update { $0 = items }; selection = items.first?.id }
                        }
                    }
                    SettingsActionMenu("Add item", symbol: "plus") {
                        ForEach(Metric.monitors.filter { $0 != .projects }) { metric in
                            Button(metric.rawValue) {
                                let widget = StatusWidget(metric: metric.rawValue)
                                update { $0.append(widget) }; selection = widget.id
                            }
                        }
                    }.disabled(widgets.count >= 8)
                }
                VStack(spacing: 0) {
                    if widgets.isEmpty { Text("Add a metric to build your menu bar.").foregroundStyle(.secondary).padding(20) }
                    ForEach(Array(widgets.enumerated()), id: \.element.id) { index, widget in
                        if index > 0 { Divider().padding(.horizontal, 12) }
                        row(widget, index: index)
                            .draggable(widget.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                guard let id = items.first.flatMap(UUID.init(uuidString:)), id != widget.id,
                                      let source = widgets.firstIndex(where: { $0.id == id }) else { return false }
                                update { $0.insert($0.remove(at: source), at: index) }; return true
                            }
                    }
                }.background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
                Text("Drag items or use the arrows to change their order. ⌘-drag the group in the menu bar to move it.")
                    .font(.caption).foregroundStyle(.secondary)
                if let selected { editor(selected) }
                VStack(alignment: .leading, spacing: 16) {
                    SettingsControlRow("Spacing") {
                        SettingsValueSlider(value: Binding(get: { store.preferences.widgetSpacing }, set: { v in store.updatePreferences { $0.widgetSpacing = v } }), range: 0...20, step: 2, title: "Item spacing")
                    }
                    Divider().opacity(0.4)
                    Toggle("Click a widget to open its monitor", isOn: Binding(get: { store.preferences.openClickedMonitor }, set: { value in store.updatePreferences { $0.openClickedMonitor = value } }))
                        .toggleStyle(SettingsSwitchStyle())
                    SettingsControlRow("Default panel") {
                        SettingsChoice("Default panel", selection: Binding(get: { store.preferences.menuDefault }, set: { value in store.updatePreferences { $0.menuDefault = value } }), options: store.menuMetrics.map(\.rawValue)) { $0 }
                    }
                }.font(.system(size: 12)).padding(16).background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
            }.padding(24)
        }
        }
    }
    private var preview: some View {
        let displays = StatusWidgetRenderer.displays(store: store)
        let width = displays.reduce(0) { $0 + $1.width } + Double(max(0, displays.count - 1)) * store.preferences.widgetSpacing
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LIVE PREVIEW").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(width)) pt").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                Image(nsImage: StatusWidgetRenderer.image(displays: displays, spacing: store.preferences.widgetSpacing, dark: true)).renderingMode(.original)
                    .padding(.horizontal, 16).frame(height: 54)
            }.background(Color(hex: 0x12131A), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Menu bar preview: " + displays.map(\.tooltip).joined(separator: ", "))
        }
    }
    private func row(_ widget: StatusWidget, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).font(.system(size: 10))
            Toggle("Show \(widget.metric)", isOn: field(widget, \.enabled)).labelsHidden().toggleStyle(SettingsCheckboxStyle())
            Button { selection = widget.id } label: {
                HStack {
                    if let metric = Metric(rawValue: widget.metric) { Image(systemName: metric.symbol).foregroundStyle(metric.color).frame(width: 18) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(widget.metric).font(.system(size: 12, weight: .medium))
                        if !store.preferences.enabledMonitors.contains(widget.metric) { Text("Disabled in Monitors").font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(widget.style.rawValue).font(.system(size: 11)).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Customize \(widget.metric) item \(index + 1)")
            Button { update { $0.swapAt(index, index - 1) } } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0).help("Move left").accessibilityLabel("Move \(widget.metric) left")
            Button { update { $0.swapAt(index, index + 1) } } label: { Image(systemName: "chevron.down") }
                .disabled(index == widgets.count - 1).help("Move right").accessibilityLabel("Move \(widget.metric) right")
            Button { update { $0.removeAll { $0.id == widget.id } } } label: { Image(systemName: "minus.circle") }
                .help("Remove item").accessibilityLabel("Remove \(widget.metric) item")
        }.buttonStyle(.borderless).padding(12)
            .background(selected?.id == widget.id ? Color(hex: 0x5B9CF6).opacity(0.09) : Color.clear)
    }
    private func editor(_ widget: StatusWidget) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(widget.metric) appearance").font(.headline)
            VStack(spacing: 12) {
                SettingsControlRow("Style") {
                    SettingsChoice("Style", selection: field(widget, \.style), options: widget.styles) { $0.rawValue }
                }
                if widget.readings.count > 1 {
                    SettingsControlRow("Reading") {
                        SettingsChoice("Reading", selection: field(widget, \.reading), options: widget.readings) { $0.rawValue }
                    }
                }
                SettingsControlRow("Label") {
                    SettingsLabelSegments(selection: field(widget, \.label))
                }
                if widget.label == .short {
                    SettingsControlRow("Custom text") {
                        SettingsTextInput(text: field(widget, \.customLabel))
                    }
                }
                SettingsControlRow("Color") {
                    SettingsChoice("Color", selection: field(widget, \.color), options: WidgetColor.allCases) { $0.rawValue }
                }
                if [.graph, .histogram, .bar, .stacked].contains(widget.style) {
                    SettingsControlRow("Width") {
                        SettingsValueSlider(value: field(widget, \.width), range: 32...80, step: 4, title: "Widget width")
                    }
                }
                if widget.style == .figure || widget.style == .stacked {
                    SettingsControlRow("Units") { Toggle("Show units", isOn: field(widget, \.showUnits)).toggleStyle(SettingsSwitchStyle()) }
                }
            }.font(.system(size: 12))
            if widget.metric == "Disk" { Text("Usage meters show space used. Graphs show disk writes.").font(.caption).foregroundStyle(.secondary) }
            if widget.reading == .temperature {
                Text(widget.metric == "Battery" ? "Battery sensor temperature. Units follow General settings." : "Average of available \(widget.metric) sensors. Units follow General settings.").font(.caption).foregroundStyle(.secondary)
                if widget.metric != "Battery" && !store.preferences.sensorMonitoring {
                    Text("Enable Sensors in Monitors to read temperatures.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(16).background(Color.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}
