import Foundation
import Testing
@testable import StatsCore

@Test func smcDecodingHandlesByteOrderAndFixedPoint() {
    #expect(SMCDecoder.value(type: "flt ", bytes: [0, 0, 0x48, 0x42]) == 50)
    #expect(SMCDecoder.value(type: "sp78", bytes: [0x32, 0x80]) == 50.5)
    #expect(SMCDecoder.value(type: "sp78", bytes: [0xFF, 0x80]) == -0.5)
    #expect(SMCDecoder.value(type: "fpe2", bytes: [0x1F, 0x40]) == 2000)
    #expect(SMCDecoder.value(type: "ui32", bytes: [0, 0, 4, 0]) == 1024)
    #expect(SMCDecoder.value(type: "ui8 ", bytes: [2]) == 2)
}

@Test func malformedSensorValuesStayUnavailable() {
    #expect(SMCDecoder.value(type: "flt ", bytes: [0, 0, 0x80, 0x7F]) == nil)
    #expect(SMCDecoder.value(type: "flt ", bytes: [0, 0, 0xC0, 0x7F]) == nil)
    #expect(SMCDecoder.value(type: "flt ", bytes: [0]) == nil)
    #expect(SMCDecoder.value(type: "sp99", bytes: [0, 0]) == nil)
    #expect(SMCDecoder.value(type: "ch8*", bytes: [0, 0]) == nil)
    for invalid in [Double.nan, .infinity, -1, 0, 65535] {
        #expect(SensorReading(id: "x", name: "x", value: invalid).value == nil)
    }
    #expect(SensorReading(id: "f", name: "Fan", kind: .fan, value: 0).value == 0)
}

@Test func thermalAveragesExcludeUnavailableAndOtherComponents() {
    let sensors: [SensorReading] = [
        .init(id: "1", name: "CPU 1", group: .cpu, value: 40),
        .init(id: "2", name: "CPU 2", group: .cpu, value: 60),
        .init(id: "3", name: "CPU 3", group: .cpu, value: nil),
        .init(id: "4", name: "GPU", group: .gpu, value: 80),
        .init(id: "5", name: "Other", value: 100)
    ]
    #expect(SensorReading.average(sensors, group: .cpu) == 50)
    #expect(SensorReading.average(sensors, group: .gpu) == 80)
    #expect(SensorReading.average(sensors, group: .battery) == nil)
    #expect(SensorReading.average([], group: .cpu) == nil)
}

@Test func sensorLabelsAreChipSpecificAndUnknownKeysAreNotGuessed() {
    #expect(SensorCatalog.description(key: "Tp00", chip: "Apple M5 Max").0 == "CPU super core 1")
    #expect(SensorCatalog.description(key: "Tp0O", chip: "Apple M5 Max").0 == "CPU performance core 1")
    #expect(SensorCatalog.description(key: "Tg1g", chip: "Apple M5 Max").1 == .gpu)
    #expect(SensorCatalog.description(key: "Tp00", chip: "Apple M2").1 == .other)
    #expect(SensorCatalog.description(key: "Tf14", chip: "Apple M3 Pro").1 == .gpu)
    #expect(SensorCatalog.description(key: "Tm0p", chip: "Apple M5 Max").0 == "Tm0p")
    #expect(SensorCatalog.description(key: "F1Ac", chip: "Apple M5 Max").0 == "Fan 2")
}

@Test func temperatureWidgetsAndSensorPreferencesRoundTrip() throws {
    var preferences = try JSONDecoder().decode(MonitorPreferences.self, from: Data("{}".utf8))
    #expect(preferences.sensorMonitoring)
    preferences.widgets = [StatusWidget(metric: "CPU", style: .vertical, reading: .temperature), StatusWidget(metric: "GPU", style: .stacked, reading: .temperature)]
    preferences.menuDefault = "Sensors"; preferences.dashboardDefault = "Sensors"
    preferences.normalize()
    #expect(preferences.widgets?[0].reading == .temperature)
    #expect(preferences.widgets?[0].style == .figure)
    #expect(preferences.widgets?[1].style == .stacked)
    #expect(preferences.menuDefault == "Sensors")
    preferences.sensorMonitoring = false; preferences.normalize()
    #expect(preferences.menuDefault == "Overview")
    #expect(preferences.dashboardDefault == "My Machine")
    #expect(try JSONDecoder().decode(MonitorPreferences.self, from: JSONEncoder().encode(preferences)) == preferences)
}
