import Foundation

public enum StatusItemStyle: String, Codable, CaseIterable, Sendable {
    case icon = "Icon", figure = "Figure", graph = "Graph", stacked = "Stacked", bar = "Usage bar", vertical = "Vertical gauge", histogram = "History bars"
}

public struct MonitorPreferences: Codable, Equatable, Sendable {
    public static let monitorOrder = ["CPU", "Memory", "Disk", "Network", "GPU", "Battery", "Projects"]
    public var enabledMonitors = Set(monitorOrder)
    public var statusMetric = "CPU"
    public var statusStyle: StatusItemStyle = .figure
    public var menuDefault = "Overview"
    public var dashboardDefault = "My Machine"
    public var refreshInterval = 2.0
    public var showDockIcon = true
    public var showSystemProcesses = true
    public var preciseNumbers = true
    public var widgets: [StatusWidget]? = nil
    public var widgetSpacing = 8.0
    public var keepMenuBarPosition = true
    public var openClickedMonitor = true
    public var temperatureUnit: TemperatureUnit = .system
    public var sensorMonitoring = true
    public var resolvedWidgets: [StatusWidget] {
        if let widgets { return widgets }
        var widget = StatusWidget(metric: statusMetric, style: statusStyle)
        widget.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        widget.label = statusStyle == .stacked ? .short : .icon
        return [widget]
    }
    public var visibleWidgets: [StatusWidget] { resolvedWidgets.filter { $0.enabled && enabledMonitors.contains($0.metric) } }
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case enabledMonitors, statusMetric, statusStyle, menuDefault, dashboardDefault, refreshInterval, showDockIcon, showSystemProcesses, preciseNumbers, widgets, widgetSpacing, keepMenuBarPosition, temperatureUnit, openClickedMonitor, sensorMonitoring
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabledMonitors = try c.decodeIfPresent(Set<String>.self, forKey: .enabledMonitors) ?? enabledMonitors
        statusMetric = try c.decodeIfPresent(String.self, forKey: .statusMetric) ?? statusMetric
        statusStyle = try c.decodeIfPresent(StatusItemStyle.self, forKey: .statusStyle) ?? statusStyle
        menuDefault = try c.decodeIfPresent(String.self, forKey: .menuDefault) ?? menuDefault
        dashboardDefault = try c.decodeIfPresent(String.self, forKey: .dashboardDefault) ?? dashboardDefault
        refreshInterval = try c.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? refreshInterval
        showDockIcon = try c.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? showDockIcon
        showSystemProcesses = try c.decodeIfPresent(Bool.self, forKey: .showSystemProcesses) ?? showSystemProcesses
        preciseNumbers = try c.decodeIfPresent(Bool.self, forKey: .preciseNumbers) ?? preciseNumbers
        widgets = try c.decodeIfPresent([StatusWidget].self, forKey: .widgets)
        widgetSpacing = try c.decodeIfPresent(Double.self, forKey: .widgetSpacing) ?? widgetSpacing
        keepMenuBarPosition = try c.decodeIfPresent(Bool.self, forKey: .keepMenuBarPosition) ?? keepMenuBarPosition
        openClickedMonitor = try c.decodeIfPresent(Bool.self, forKey: .openClickedMonitor) ?? openClickedMonitor
        temperatureUnit = try c.decodeIfPresent(TemperatureUnit.self, forKey: .temperatureUnit) ?? temperatureUnit
        sensorMonitoring = try c.decodeIfPresent(Bool.self, forKey: .sensorMonitoring) ?? true
    }

    public mutating func normalize() {
        enabledMonitors.formIntersection(Self.monitorOrder)
        widgetSpacing = widgetSpacing.isFinite ? min(20, max(0, widgetSpacing)) : 8
        if let widgets {
            var ids = Set<UUID>()
            self.widgets = widgets.filter { Self.monitorOrder.contains($0.metric) && $0.metric != "Projects" }.prefix(8).map {
                var widget = $0
                if !ids.insert(widget.id).inserted { widget.id = UUID(); ids.insert(widget.id) }
                widget.normalize(); return widget
            }
        }
        let graphable = Self.monitorOrder.filter { $0 != "Projects" && enabledMonitors.contains($0) }
        if !graphable.contains(statusMetric) { statusMetric = graphable.first ?? "Overview" }
        let available = enabledMonitors.union(sensorMonitoring ? ["Sensors"] : [])
        if menuDefault != "Overview" && !available.contains(menuDefault) { menuDefault = "Overview" }
        if !["My Machine", "Overview"].contains(dashboardDefault) && !available.contains(dashboardDefault) { dashboardDefault = "My Machine" }
        if ![1.0, 2.0, 5.0, 10.0].contains(refreshInterval) { refreshInterval = 2 }
    }
}
