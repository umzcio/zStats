import Foundation
import StatsCore

enum ReferenceData {
    static var snapshot: SystemSnapshot {
        var s = SystemSnapshot()
        s.cpu = 27; s.userCPU = 19; s.systemCPU = 8; s.cores = 12; s.load = 3.41
        s.memoryTotal = 64e9; s.memoryUsed = 52.63e9; s.memoryApp = 23.43e9; s.memoryWired = 5.37e9; s.memoryCompressed = 23.82e9; s.memoryCached = 10.32e9
        s.diskTotal = 994.66e9; s.diskFree = 479.72e9; s.diskRead = 737e3; s.diskWrite = 195e3
        s.download = 8.1e6; s.upload = 4e3; s.received = 5.6e9; s.sent = 612e6; s.interface = "en0"
        s.gpu = 60; s.gpuMemory = 1.69e9; s.battery = 64; s.batteryMinutes = 166; s.batteryHealth = 76
        s.batteryCycles = 412; s.batteryWatts = 12.6; s.batteryTemperature = 31; s.uptime = 273600
        s.sensors = [.init(id: "demo-cpu-1", name: "CPU sensor 1", group: .cpu, value: 52), .init(id: "demo-cpu-2", name: "CPU sensor 2", group: .cpu, value: 56), .init(id: "demo-gpu", name: "GPU sensor", group: .gpu, value: 48), .init(id: "demo-battery", name: "Battery pack", group: .battery, value: 31), .init(id: "demo-fan", name: "Fan 1", kind: .fan, group: .fan, value: 1800)]
        let specs: [(String, String, Double, Double, Int)] = [
            ("Google Chrome", "/Applications/Google Chrome.app", 21.23e9, 18.2, 96),
            ("Visual Studio Code", "/Applications/Visual Studio Code.app", 8.17e9, 4.8, 63),
            ("Terminal", "/System/Applications/Utilities/Terminal.app", 3.86e9, 12.4, 49),
            ("Safari", "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", 2.69e9, 8.1, 16),
            ("Docker", "/Applications/Docker.app", 1.57e9, 6.2, 9),
            ("Slack", "/Applications/Slack.app", 1.06e9, 2.1, 13),
            ("Figma", "/Applications/Figma.app", 912e6, 1.8, 14),
            ("Zoom", "/Applications/zoom.us.app", 640e6, 1.2, 8)
        ]
        s.networkAppsAvailable = true; s.gpuAppsAvailable = true; s.powerAppsAvailable = true
        s.apps = ProcessGrouper.group(specs.enumerated().flatMap { index, item in
            (0..<item.4).map { sub in
                ProcessReading(pid: Int32(10000 + index * 100 + sub), parentPID: 1, name: sub == 0 ? item.0 : item.0 + " Helper", path: item.1 + "/Contents/MacOS/" + item.0, memory: item.2 / Double(item.4), cpu: item.3 / Double(item.4), readRate: Double(8 - index) * 13000 / Double(item.4), writeRate: Double(8 - index) * 19000 / Double(item.4), download: Double(8 - index) * 120000 / Double(item.4), upload: Double(8 - index) * 1000 / Double(item.4), gpu: Double(8 - index) * 0.5 / Double(item.4), cpuWatts: Double(8 - index) * 0.12 / Double(item.4))
            }
        })
        return s
    }

    static var projects: [ProjectReading] {
        let rows: [(String, String, Int, Double)] = [("storefront", "node", 3001, 1180), ("storefront-web", "node", 4322, 458), ("scraper-api", "python", 8000, 412), ("marketing-site", "node", 4321, 296), ("billing-api", "node", 3000, 204), ("docs", "node", 5173, 188), ("ml-notebooks", "python", 8888, 164), ("design-tokens", "node", 6006, 121), ("infra", "go", 8081, 96), ("auth-service", "go", 8080, 74)]
        return rows.enumerated().map { index, row in
            .init(pid: Int32(20000 + index), name: row.0, directory: "/Projects/" + row.0, ports: [row.2], processes: [.init(pid: Int32(20000 + index), parentPID: 1, name: row.1, path: "/usr/bin/" + row.1, memory: row.3 * 1e6, cpu: index == 0 ? 8 : 0.1)])
        }
    }

    static func history(for metric: Metric) -> [Double] {
        (0..<56).map { index in
            let x = Double(index)
            switch metric {
            case .cpu, .overview: return 27 + sin(x * 0.19) * 7 + sin(x * 0.83) * 2
            case .memory: return (51.5 + sin(x * 0.13)) * 1e9
            case .disk: return max(1000, (sin(x * 0.27) + cos(x * 0.59)) * 500000 + 300000)
            case .network: return max(8000, (sin(x * 0.4) + cos(x * 0.75)) * 150000 + 80000)
            case .gpu: return 45 + sin(x * 0.16) * 22 + cos(x * 0.6) * 6
            case .battery: return 65 - x / 56
            case .machine, .projects, .sensors: return 0
            }
        }
    }
}
