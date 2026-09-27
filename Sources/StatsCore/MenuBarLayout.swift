import Foundation

public enum WidgetReading: String, Codable, CaseIterable, Sendable {
    case value = "Value", percentage = "Percentage", traffic = "Upload / download", diskIO = "Read / write", temperature = "Temperature"
}
public enum WidgetLabel: String, Codable, CaseIterable, Sendable {
    case none = "None", short = "Text", icon = "Icon"
}
public enum WidgetColor: String, Codable, CaseIterable, Sendable {
    case monochrome = "Monochrome", metric = "Metric color", blue = "Blue", purple = "Purple", green = "Green", orange = "Orange", pink = "Pink"
}
public enum TemperatureUnit: String, Codable, CaseIterable, Sendable {
    case system = "System", celsius = "Celsius", fahrenheit = "Fahrenheit"
    public func converted(_ celsius: Double, systemUsesFahrenheit: Bool) -> Double {
        self == .fahrenheit || (self == .system && systemUsesFahrenheit) ? celsius * 9 / 5 + 32 : celsius
    }
}
public struct StatusWidget: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var metric: String
    public var style: StatusItemStyle
    public var reading: WidgetReading
    public var label: WidgetLabel = .short
    public var customLabel = ""
    public var color: WidgetColor = .monochrome
    public var width = 48.0
    public var showUnits = true
    public var enabled = true
    public init(metric: String, style: StatusItemStyle = .figure, reading: WidgetReading = .value) {
        self.id = UUID(); self.metric = metric; self.style = style; self.reading = reading
    }
    public var readings: [WidgetReading] {
        switch metric {
        case "Memory", "Disk": return metric == "Disk" ? [.value, .percentage, .diskIO] : [.value, .percentage]
        case "Network": return [.value, .traffic]
        case "CPU", "GPU", "Battery": return [.value, .temperature]
        default: return [.value]
        }
    }
    public var styles: [StatusItemStyle] {
        if reading == .traffic || reading == .diskIO { return [.figure, .stacked] }
        if reading == .temperature { return [.figure, .stacked] }
        if metric == "Network" { return [.icon, .figure, .stacked, .graph, .histogram] }
        return StatusItemStyle.allCases
    }
    public mutating func normalize() {
        if !readings.contains(reading) { reading = .value }
        if !styles.contains(style) { style = .figure }
        width = width.isFinite ? min(80, max(32, width)) : 48
        customLabel = String(customLabel.filter { !$0.isNewline }.prefix(8))
    }
}
public enum MenuBarPreset: String, CaseIterable {
    case minimal = "Minimal", meters = "Usage meters", detailed = "Detailed"
    public func widgets() -> [StatusWidget] {
        switch self {
        case .minimal:
            var cpu = StatusWidget(metric: "CPU"); cpu.label = .icon; return [cpu]
        case .meters:
            return ["Memory", "Disk", "CPU"].map {
                var widget = StatusWidget(metric: $0, style: .bar, reading: .percentage); widget.color = .blue; return widget
            }
        case .detailed:
            var network = StatusWidget(metric: "Network", style: .stacked, reading: .traffic); network.label = .none
            let memory = StatusWidget(metric: "Memory", style: .stacked, reading: .percentage)
            let battery = StatusWidget(metric: "Battery", style: .vertical)
            let disk = StatusWidget(metric: "Disk", style: .vertical, reading: .percentage)
            var cpu = StatusWidget(metric: "CPU", style: .histogram); cpu.width = 72
            return [network, memory, battery, disk, cpu]
        }
    }
}
