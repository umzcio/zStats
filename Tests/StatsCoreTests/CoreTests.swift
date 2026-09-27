import Foundation
import Testing
@testable import StatsCore

@Test func ratesHandleFirstSampleAndCounterReset() {
    #expect(CounterRate.rate(current: 500, previous: nil, seconds: 2) == nil)
    #expect(CounterRate.rate(current: 500, previous: 100, seconds: 2) == 200)
    #expect(CounterRate.rate(current: 50, previous: 100, seconds: 2) == nil)
    #expect(CounterRate.rate(current: 500, previous: 100, seconds: 0) == nil)
}

@Test func helpersGroupUnderOuterAppAndChildrenFollowAncestor() {
    let rows = [
        ProcessReading(pid: 10, parentPID: 1, name: "Editor", path: "/Applications/Editor.app/Contents/MacOS/Editor", memory: 100, cpu: 10),
        ProcessReading(pid: 11, parentPID: 10, name: "Helper", path: "/Applications/Editor.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper", memory: 50, cpu: 20),
        ProcessReading(pid: 12, parentPID: 11, name: "node", path: "/usr/local/bin/node", memory: 25, cpu: 5),
        ProcessReading(pid: 20, parentPID: 1, name: "other", path: "/usr/bin/other", memory: 10, cpu: 1)
    ]
    let grouped = ProcessGrouper.group(rows)
    let editor = grouped.first { $0.bundlePath == "/Applications/Editor.app" }
    #expect(grouped.count == 2)
    #expect(editor?.memory == 175)
    #expect(editor?.cpu == 35)
    #expect(editor?.processes.count == 3)
}

@Test func cyclesAndMissingParentsDoNotLoseProcesses() {
    let rows = [ProcessReading(pid: 2, parentPID: 3, name: "a", path: "/a"), ProcessReading(pid: 3, parentPID: 2, name: "b", path: "/b"), ProcessReading(pid: 4, parentPID: 900, name: "c", path: "/c")]
    #expect(ProcessGrouper.group(rows).flatMap(\.processes).count == 3)
}

@Test func historyExpiresOldDataAndCoalescesMinuteSamples() throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    var archive = HistoryArchive()
    archive.record(HistoryPoint(date: now.addingTimeInterval(-31 * 86400), cpu: 10, memory: 20), now: now)
    archive.record(HistoryPoint(date: now.addingTimeInterval(-1), cpu: 20, memory: 30), now: now)
    archive.record(HistoryPoint(date: now, cpu: 30, memory: 40), now: now)
    #expect(archive.points.count == 1)
    #expect(archive.points.last?.cpu == 30)
    let decoded = try JSONDecoder().decode(HistoryArchive.self, from: JSONEncoder().encode(archive))
    #expect(decoded.points == archive.points)
}

@Test func projectParserHandlesIPv6DuplicatePortsAndPathsWithSpaces() {
    let input = "p42\ncnode\nfcwd\nn/Users/me/My Project\nf12\nn*:3000\nf13\nn[::1]:3000\np55\ncpython\nf9\nn127.0.0.1:8000\npnope\nninvalid"
    let rows = ProjectParser.parse(input)
    #expect(rows.count == 2)
    #expect(rows.first { $0.pid == 42 }?.directory == "/Users/me/My Project")
    #expect(rows.first { $0.pid == 42 }?.ports == [3000])
    #expect(rows.first { $0.pid == 55 }?.ports == [8000])
}

@Test func terminationRejectsStaleOrProtectedIdentity() {
    let original = ProcessIdentity(pid: 100, started: 12345)
    #expect(original.canTerminate(current: ProcessIdentity(pid: 100, started: 12345), ownPID: 999))
    #expect(!original.canTerminate(current: ProcessIdentity(pid: 100, started: 12346), ownPID: 999))
    #expect(!original.canTerminate(current: original, ownPID: 100))
    #expect(!ProcessIdentity(pid: 1, started: 123).canTerminate(current: ProcessIdentity(pid: 1, started: 123), ownPID: 999))
}

@Test func runtimeDetectionRejectsUnrelatedDesktopApps() {
    for name in ["Google Drive", "Google Chrome", "Discord", "Cargo Helper", "node-helper", "Python Launcher"] {
        #expect(!ProjectParser.isDevelopmentRuntime(name))
    }
    for name in ["go", "node", "Python", "python3.13", "ruby3.3", "php8.4", "beam.smp", "uvicorn", "dotnet", "bun"] {
        #expect(ProjectParser.isDevelopmentRuntime(name))
    }
}

@Test func networkTotalsSurviveFourGiBAndInterfaceChanges() {
    var tracker = NetworkTracker()
    let first = tracker.sample(["en0": .init(received: 4_294_967_000, sent: 100)], time: 1)
    #expect(first.download == nil)
    let second = tracker.sample(["en0": .init(received: 4_294_969_000, sent: 300)], time: 3)
    #expect(second.download == 1000)
    #expect(second.received == 2000)
    let added = tracker.sample(["en0": .init(received: 4_294_971_000, sent: 500), "en7": .init(received: 9_000_000, sent: 1000)], time: 5)
    #expect(added.download == 1000)
    #expect(added.received == 4000)
    let reset = tracker.sample(["en0": .init(received: 20, sent: 10)], time: 7)
    #expect(reset.received == 4000)
    #expect(reset.download == nil)
}

@Test func missingProcessReadingsStayUnavailableWhenGrouped() {
    let rows = [ProcessReading(pid: 10, parentPID: 1, name: "unreadable", path: "/unreadable", memory: nil, cpu: nil)]
    #expect(ProcessGrouper.group(rows).first?.memory == nil)
    #expect(ProcessGrouper.group(rows).first?.cpu == nil)
}

@Test func historyKeepsCollectionGapsInTheirTimePositions() {
    let values: [(Date, Double?)] = [(.init(timeIntervalSince1970: 100), 20), (.init(timeIntervalSince1970: 110), 30), (.init(timeIntervalSince1970: 180), 40)]
    let buckets = HistoryTimeline.buckets(values, start: .init(timeIntervalSince1970: 100), end: .init(timeIntervalSince1970: 200), count: 10)
    #expect(buckets.count == 10)
    #expect(buckets[0] == 20)
    #expect(buckets[1] == 30)
    #expect(buckets[2] == nil)
    #expect(buckets[7] == nil)
    #expect(buckets[8] == 40)
    #expect(buckets[9] == nil)
}

@Test func nettopParsesHeadersQuotedNamesAnd64BitCounters() {
    let parsed = NettopParser.parse(",bytes_out,bytes_in,\n\"An app, with dots.name.42\",200,5000000000,\nGoogle Chrome H.53,15,72,\ninvalid,nope,2,\n")
    #expect(parsed?[42]?.received == 5_000_000_000)
    #expect(parsed?[42]?.sent == 200)
    #expect(parsed?[53]?.received == 72)
    #expect(parsed?.count == 2)
    #expect(NettopParser.parse("nettop: NStatManagerCreate failed") == nil)
    #expect(NettopParser.parse(",bytes_in,bytes_out,\n")?.isEmpty == true)
}

@Test func appNetworkRatesRejectPIDReuseCounterResetAndMissingIntervals() {
    var tracker = ProcessNetworkTracker()
    let original = ProcessIdentity(pid: 42, started: 100)
    let reused = ProcessIdentity(pid: 42, started: 200)
    #expect(tracker.sample([original: .init(received: 1000, sent: 200)], time: 1)[original]?.download == nil)
    let next = tracker.sample([original: .init(received: 5000, sent: 800)], time: 3)
    #expect(next[original]?.download == 2000)
    #expect(next[original]?.upload == 300)
    #expect(tracker.sample([original: .init(received: 20, sent: 10)], time: 5)[original]?.download == nil)
    #expect(tracker.sample([reused: .init(received: 500, sent: 100)], time: 7)[reused]?.download == nil)
    _ = tracker.sample([:], time: 9)
    #expect(tracker.sample([reused: .init(received: 900, sent: 200)], time: 11)[reused]?.download == nil)
}

@Test func gpuRatesKeepClientLifetimesSeparate() {
    var tracker = GPUTimeTracker()
    let process = ProcessIdentity(pid: 42, started: 100)
    let a = GPUClientIdentity(process: process, registryID: 1)
    let b = GPUClientIdentity(process: process, registryID: 2)
    #expect(tracker.sample([a: 1_000_000_000, b: 10_000_000_000], time: 1).isEmpty)
    #expect(tracker.sample([a: 1_200_000_000, b: 10_400_000_000], time: 3)[process] == 30)
    // A disappearing client must not turn the surviving client's delta negative.
    #expect(tracker.sample([a: 1_400_000_000], time: 5)[process] == 10)
    let c = GPUClientIdentity(process: process, registryID: 3)
    #expect(tracker.sample([a: 1_600_000_000, c: 8_000_000_000], time: 7)[process] == 10)
    #expect(tracker.sample([a: 0], time: 9).isEmpty)
}

@Test func appTelemetryAggregatesHelpersAndPreservesMissingReadings() {
    let rows = [
        ProcessReading(pid: 10, parentPID: 1, name: "App", path: "/App.app/Contents/MacOS/App", download: 100, upload: 20, gpu: 4, cpuWatts: 0.2),
        ProcessReading(pid: 11, parentPID: 10, name: "Helper", path: "/helper", download: 300, upload: 10, gpu: 2, cpuWatts: 0.3)
    ]
    let app = ProcessGrouper.group(rows).first
    #expect(app?.download == 400)
    #expect(app?.upload == 30)
    #expect(app?.gpu == 6)
    #expect(app?.cpuWatts == 0.5)
    var missing = rows; missing[1].gpu = nil
    #expect(ProcessGrouper.group(missing).first?.gpu == nil)
}

@Test func disabledMonitorsCannotRemainDefaultSelections() {
    var preferences = MonitorPreferences()
    preferences.statusMetric = "GPU"
    preferences.menuDefault = "GPU"
    preferences.dashboardDefault = "GPU"
    preferences.enabledMonitors.remove("GPU")
    preferences.normalize()
    #expect(preferences.statusMetric == "CPU")
    #expect(preferences.menuDefault == "Overview")
    #expect(preferences.dashboardDefault == "My Machine")
    preferences.enabledMonitors = ["Projects", "Unknown"]
    preferences.refreshInterval = -1
    preferences.normalize()
    #expect(preferences.enabledMonitors == ["Projects"])
    #expect(preferences.statusMetric == "Overview")
    #expect(preferences.refreshInterval == 2)
    preferences.enabledMonitors = []
    preferences.normalize()
    #expect(preferences.menuDefault == "Overview")
    #expect(preferences.dashboardDefault == "My Machine")
}

@Test func monitorPreferencesPreserveChoicesAcrossSerialization() throws {
    var original = MonitorPreferences()
    original.enabledMonitors = ["Memory", "Network"]
    original.statusMetric = "Memory"
    original.menuDefault = "Network"
    original.dashboardDefault = "Memory"
    original.statusStyle = .stacked
    original.refreshInterval = 5
    original.showDockIcon = false
    original.showSystemProcesses = false
    original.preciseNumbers = false
    original.normalize()
    var restored = try JSONDecoder().decode(MonitorPreferences.self, from: JSONEncoder().encode(original))
    restored.normalize()
    #expect(restored == original)
}

@Test func legacySettingsMigrateWithoutLosingUserChoices() throws {
    let data = Data("""
    {"enabledMonitors":["Memory","CPU"],"statusMetric":"Memory","statusStyle":"Stacked","menuDefault":"Memory","refreshInterval":5,"preciseNumbers":false}
    """.utf8)
    var preferences = try JSONDecoder().decode(MonitorPreferences.self, from: data)
    preferences.normalize()
    #expect(preferences.resolvedWidgets.count == 1)
    #expect(preferences.resolvedWidgets[0].metric == "Memory")
    #expect(preferences.resolvedWidgets[0].style == .stacked)
    #expect(preferences.resolvedWidgets[0].id == preferences.resolvedWidgets[0].id)
    #expect(preferences.refreshInterval == 5)
    #expect(!preferences.preciseNumbers)
    #expect(preferences.keepMenuBarPosition)
}

@Test func widgetLayoutsPreserveOrderDuplicatesAndDisabledConfiguration() throws {
    var preferences = MonitorPreferences()
    var first = StatusWidget(metric: "CPU", style: .histogram)
    first.color = .pink
    var second = StatusWidget(metric: "CPU", style: .stacked)
    second.customLabel = "Load"; second.showUnits = false
    preferences.widgets = [first, second, StatusWidget(metric: "Network", style: .stacked, reading: .traffic)]
    preferences.normalize()
    #expect(preferences.visibleWidgets.count == 3)
    preferences.enabledMonitors.remove("CPU"); preferences.normalize()
    #expect(preferences.visibleWidgets.count == 1)
    #expect(preferences.widgets?.count == 3)
    preferences.enabledMonitors.insert("CPU"); preferences.normalize()
    #expect(preferences.visibleWidgets.map(\.id) == [first.id, second.id, preferences.widgets![2].id])
    let copy = try JSONDecoder().decode(MonitorPreferences.self, from: JSONEncoder().encode(preferences))
    #expect(copy == preferences)
    preferences.widgets = []
    #expect(preferences.visibleWidgets.isEmpty)
}

@Test func widgetsRejectInvalidCombinationsAndUnboundedDimensions() {
    var invalid = StatusWidget(metric: "Network", style: .bar, reading: .temperature)
    invalid.width = .infinity; invalid.customLabel = "Much too long\nlabel"
    invalid.normalize()
    #expect(invalid.reading == .value)
    #expect(invalid.style == .figure)
    #expect(invalid.width == 48)
    #expect(invalid.customLabel.count == 8)
    var preferences = MonitorPreferences()
    preferences.widgets = [invalid, invalid, StatusWidget(metric: "Not real")]
    preferences.widgetSpacing = -10
    preferences.normalize()
    #expect(preferences.widgets?.count == 2)
    #expect(Set(preferences.widgets!.map(\.id)).count == 2)
    #expect(preferences.widgetSpacing == 0)
    var battery = StatusWidget(metric: "Battery", style: .graph, reading: .temperature)
    battery.normalize()
    #expect(battery.style == .figure)
}

@Test func temperatureUnitsConvertKnownValues() {
    #expect(TemperatureUnit.fahrenheit.converted(0, systemUsesFahrenheit: false) == 32)
    #expect(TemperatureUnit.celsius.converted(100, systemUsesFahrenheit: true) == 100)
    #expect(TemperatureUnit.system.converted(100, systemUsesFahrenheit: true) == 212)
    #expect(TemperatureUnit.system.converted(35, systemUsesFahrenheit: false) == 35)
}
