import SwiftUI
import StatsCore
import CStats

enum Metric: String, CaseIterable, Identifiable {
    case machine = "My Machine", overview = "Overview", cpu = "CPU", memory = "Memory", disk = "Disk", network = "Network", gpu = "GPU", battery = "Battery", sensors = "Sensors", projects = "Projects"
    static var monitorTabs: [Metric] { allCases.filter { $0 != .machine && $0 != .overview } }
    static var monitors: [Metric] { allCases.filter { $0 != .machine && $0 != .overview && $0 != .sensors } }
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .machine: "laptopcomputer"
        case .sensors: "thermometer.medium"
        case .overview: "square.grid.2x2"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .gpu: "square.3.layers.3d"
        case .battery: "battery.75percent"
        case .projects: "folder"
        }
    }
    var color: Color {
        switch self {
        case .machine, .overview, .cpu: Color(hex: 0x5B9CF6)
        case .memory: Color(hex: 0xA28AE5)
        case .disk: Color(hex: 0xD6A03A)
        case .network: Color(hex: 0x40B99A)
        case .gpu: Color(hex: 0xD9689D)
        case .battery: Color(hex: 0x66B951)
        case .projects: Color(hex: 0xDF8453)
        case .sensors: Color(hex: 0xE68752)
        }
    }
    func value(in s: SystemSnapshot) -> Double? {
        switch self {
        case .cpu, .overview: s.cpu
        case .memory: s.memoryUsed
        case .disk: s.diskFree
        case .network: s.download
        case .gpu: s.gpu
        case .battery: s.battery
        case .machine, .projects, .sensors: nil
        }
    }
    func historyValue(_ p: HistoryPoint) -> Double? {
        switch self {
        case .cpu, .overview: p.cpu
        case .memory: p.memory
        case .disk: p.diskWrite
        case .network: p.download
        case .gpu: p.gpu
        case .battery: p.battery
        case .machine, .projects, .sensors: nil
        }
    }
}

enum HistoryRange: String, CaseIterable {
    case live = "Live", hours12 = "12 h", hours24 = "24 h", days7 = "7 d", days30 = "30 d"
    var seconds: Double {
        switch self { case .live: 120; case .hours12: 43200; case .hours24: 86400; case .days7: 604800; case .days30: 2592000 }
    }
}

@MainActor final class MonitorStore: ObservableObject {
    @Published var selected: Metric = .machine
    @Published var menuSelection: Metric = .overview
    @Published var preferences = MonitorPreferences() {
        didSet {
            if let data = try? JSONEncoder().encode(preferences), persistPreferences { UserDefaults.standard.set(data, forKey: "monitorPreferences.v1") }
            if !dashboardMetrics.contains(selected) { selected = .machine }
            if !menuMetrics.contains(menuSelection) { menuSelection = .overview }
        }
    }
    private var persistPreferences = true
    @Published var referenceMode = false
    @Published var range: HistoryRange = .live
    @Published var search = ""
    @Published private(set) var live = SystemSnapshot()
    @Published private(set) var recent: [HistoryPoint] = []
    @Published private(set) var archive = HistoryArchive()
    @Published private(set) var liveProjects: [ProjectReading] = []
    @Published var error: String?
    @Published private(set) var sampled = false
    @Published var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "Dark" {
        didSet {
            if persistPreferences {
                UserDefaults.standard.set(appearance, forKey: "appearance")
                AppAppearance.apply(appearance)
            }
        }
    }
    private var task: Task<Void, Never>?
    private var storageErrorEpisode = ErrorEpisodeTracker()
    var snapshot: SystemSnapshot { referenceMode ? ReferenceData.snapshot : live }
    var projects: [ProjectReading] { referenceMode ? ReferenceData.projects : liveProjects }

    var enabledMetrics: [Metric] { Metric.monitors.filter { preferences.enabledMonitors.contains($0.rawValue) } }
    var dashboardMetrics: [Metric] { [.machine, .overview] + Metric.monitorTabs.filter(isEnabled) }
    var menuMetrics: [Metric] { [.overview] + Metric.monitorTabs.filter(isEnabled) }
    var statusMetric: Metric { Metric(rawValue: preferences.statusMetric) ?? .overview }
    func updatePreferences(_ edit: (inout MonitorPreferences) -> Void) {
        var value = preferences; edit(&value); value.normalize(); preferences = value
    }
    func isEnabled(_ metric: Metric) -> Bool { metric == .sensors ? preferences.sensorMonitoring : preferences.enabledMonitors.contains(metric.rawValue) }

    init(startSampling: Bool = true) {
        persistPreferences = startSampling
        if startSampling, let data = UserDefaults.standard.data(forKey: "monitorPreferences.v1"), var saved = try? JSONDecoder().decode(MonitorPreferences.self, from: data) {
            saved.normalize(); preferences = saved
        }
        selected = Metric(rawValue: preferences.dashboardDefault) ?? .machine
        menuSelection = Metric(rawValue: preferences.menuDefault) ?? .overview
        referenceMode = ProcessInfo.processInfo.arguments.contains("--reference")
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--tab"), ProcessInfo.processInfo.arguments.count > index + 1,
           let tab = Metric.allCases.first(where: { $0.rawValue.lowercased() == ProcessInfo.processInfo.arguments[index + 1].lowercased() }) { selected = tab }
        guard startSampling else { return }
        AppAppearance.apply(appearance)
        let sampler = SystemSampler()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let configuration = self?.preferences else { return }
                let data = await Task.detached(priority: .utility) { sampler.sample(enabled: configuration.enabledMonitors, sensorMonitoring: configuration.sensorMonitoring) }.value
                guard let self else { return }
                self.live = data.0; self.liveProjects = data.1; self.archive = data.2
                if let error = self.storageErrorEpisode.notification(for: data.3) { self.error = error }
                self.recent.append(HistoryPoint(data.0)); self.recent = Array(self.recent.suffix(1800)); self.sampled = true
                try? await Task.sleep(for: .seconds(self.preferences.refreshInterval))
            }
        }
    }

    func historySummary(for metric: Metric) -> HistorySummary? {
        if referenceMode { return HistorySummary(values: ReferenceData.history(for: metric).map(Optional.some)) }
        let end = live.date
        let start = end.addingTimeInterval(-range.seconds)
        let points = range == .live ? recent : archive.points
        return HistoryTimeline.summary(points.map { ($0.date, metric.historyValue($0)) }, start: start, end: end)
    }

    func chartHistory(for metric: Metric) -> [Double?] {
        if referenceMode { return ReferenceData.history(for: metric).map(Optional.some) }
        let end = live.date
        let start = end.addingTimeInterval(-range.seconds)
        let points = range == .live ? recent : archive.points
        return HistoryTimeline.buckets(points.map { ($0.date, metric.historyValue($0)) }, start: start, end: end, count: range == .live ? min(56, max(12, Int(ceil(range.seconds / preferences.refreshInterval)))) : 90)
    }

    func apps(for metric: Metric, matching query: String = "") -> [AppReading] {
        let rows = snapshot.apps.filter { app in
            (preferences.showSystemProcesses || app.processes.contains { $0.uid == getuid() } || referenceMode) && (query.isEmpty || app.name.localizedCaseInsensitiveContains(query))
        }
        return rows.sorted {
            switch metric { case .cpu: ($0.cpu ?? 0) > ($1.cpu ?? 0); case .disk: ($0.writeRate ?? 0) > ($1.writeRate ?? 0); case .network: ($0.download ?? 0) > ($1.download ?? 0); case .gpu: ($0.gpu ?? 0) > ($1.gpu ?? 0); case .battery: ($0.cpuWatts ?? 0) > ($1.cpuWatts ?? 0); default: ($0.memory ?? 0) > ($1.memory ?? 0) }
        }
    }

    func hasAppReadings(for metric: Metric) -> Bool {
        switch metric {
        case .network: snapshot.networkAppsAvailable
        case .gpu: snapshot.gpuAppsAvailable
        case .battery: snapshot.powerAppsAvailable
        default: true
        }
    }

    func terminate(_ processes: [ProcessReading], force: Bool) {
        guard !referenceMode else { return }
        var failures: [String] = []
        for process in processes {
            let current = ProcessIdentity(pid: process.pid, started: zs_process_start(process.pid))
            guard process.uid == getuid(), process.identity.canTerminate(current: current, ownPID: getpid()) else {
                failures.append("\(process.name) is protected or has already exited."); continue
            }
            let status = zs_terminate(process.pid, process.started, force ? 1 : 0)
            if status != 0 { failures.append("\(process.name): \(String(cString: strerror(status)))") }
        }
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }
}
