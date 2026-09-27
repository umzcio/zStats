import SwiftUI
import StatsCore

struct SensorsView: View {
    @EnvironmentObject private var store: MonitorStore
    @State private var showAdditional = false
    private var s: SystemSnapshot { store.snapshot }
    private var known: [SensorReading] { s.sensors.filter { $0.name != $0.id } }
    private var additional: [SensorReading] { s.sensors.filter { $0.name == $0.id } }
    private func degrees(_ value: Double?) -> String { StatusWidgetRenderer.temperature(value, preference: store.preferences.temperatureUnit) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Sensors", systemImage: "thermometer.medium").font(.system(size: 19, weight: .semibold))
                    Spacer()
                    Text("Live temperatures & fans").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
                HStack(spacing: 14) {
                    summary("CPU average", degrees(s.cpuTemperature), .cpu)
                    summary("GPU average", degrees(s.gpuTemperature), .gpu)
                    summary("Battery", degrees(s.batteryTemperature), .battery)
                }
                Text("CPU and GPU figures average the available component sensors. These are internal temperatures, not the temperature of the case.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if s.sensors.isEmpty {
                    ContentUnavailableView("No thermal sensors available", systemImage: "thermometer.medium", description: Text("Waiting for readable temperature and fan sensors from this Mac."))
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 14) {
                            sensorGroup(.cpu)
                            sensorGroup(.battery)
                        }.frame(maxWidth: .infinity)
                        VStack(spacing: 14) {
                            sensorGroup(.fan)
                            sensorGroup(.gpu)
                            sensorGroup(.other)
                        }.frame(maxWidth: .infinity)
                    }
                    if !additional.isEmpty {
                        DisclosureGroup("Additional sensors (\(additional.count))", isExpanded: $showAdditional) {
                            Text("macOS does not identify the component for these readings. Sensor keys are shown as reported.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 8)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(additional) { sensor in sensorRow(sensor).padding(.horizontal, 12) }
                            }
                        }.font(.system(size: 12)).padding(16).background(Color.panel, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }.padding(.bottom, 12)
        }
    }
    @ViewBuilder private func sensorGroup(_ group: SensorReading.Group) -> some View {
        let rows = known.filter { $0.group == group }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(group.rawValue).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if group == .cpu || group == .gpu {
                        Text("Hottest \(degrees(rows.compactMap(\.value).max()))").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.padding(.bottom, 2)
                ForEach(rows) { sensor in sensorRow(sensor) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 16))
        }
    }
    private func summary(_ title: String, _ value: String, _ metric: Metric) -> some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                MetricLabel(metric: metric, title: title)
                Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            }
        }.frame(height: 105)
    }
    private func sensorRow(_ sensor: SensorReading) -> some View {
        HStack {
            Text(sensor.name).lineLimit(1)
            Spacer(minLength: 10)
            Text(sensor.kind == .fan ? sensor.value.map { Format.number($0) + " rpm" } ?? "—" : degrees(sensor.value)).monospacedDigit()
        }.font(.system(size: 12)).frame(height: 22).help("Sensor " + sensor.id)
    }
}

struct MenuSensorsDetail: View {
    @EnvironmentObject private var store: MonitorStore
    private var s: SystemSnapshot { store.snapshot }
    private func degrees(_ value: Double?) -> String { StatusWidgetRenderer.temperature(value, preference: store.preferences.temperatureUnit) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU average").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(degrees(s.cpuTemperature)).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                Spacer()
                Image(systemName: "thermometer.medium").font(.system(size: 28, weight: .light)).foregroundStyle(Metric.sensors.color)
            }
            row("GPU average", degrees(s.gpuTemperature))
            row("Battery", degrees(s.batteryTemperature))
            Divider()
            Text("Fans").font(.system(size: 11)).foregroundStyle(.secondary)
            let fans = s.sensors.filter { $0.kind == .fan }
            if fans.isEmpty { Text("No fan sensors reported").font(.system(size: 11)).foregroundStyle(.secondary) }
            ForEach(fans.prefix(4)) { fan in row(fan.name, fan.value.map { Format.number($0) + " rpm" } ?? "—") }
            Spacer(minLength: 0)
            Text(s.sensors.isEmpty ? "Waiting for readable thermal sensors." : "Open zStats for individual sensor readings.").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.menuCard, in: RoundedRectangle(cornerRadius: 15))
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.system(size: 12))
    }
}
