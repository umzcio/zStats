import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
    static let canvas = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.103, green: 0.102, blue: 0.116, alpha: 1) : NSColor(red: 0.95, green: 0.95, blue: 0.965, alpha: 1) })
    static let panel = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.126, green: 0.125, blue: 0.140, alpha: 1) : .white })
    static let inset = Color.primary.opacity(0.025)
    static let muted = Color.secondary.opacity(0.8)
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View { content.padding(padding).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
}

struct MetricLabel: View {
    var metric: Metric
    var title: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: metric.symbol).font(.system(size: 11, weight: .medium)).frame(width: 23, height: 23)
                .background(metric.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
            Text(title ?? metric.rawValue).font(.system(size: 11, weight: .medium))
        }.foregroundStyle(metric.color)
    }
}

struct ValueText: View {
    var value: String
    var unit: String = ""
    var size: CGFloat = 34
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: size, weight: .semibold, design: .rounded)).tracking(-0.8)
            if !unit.isEmpty { Text(unit).font(.system(size: size * 0.4, weight: .medium)).foregroundStyle(.secondary) }
        }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
    }
}

struct MiniStat: View {
    var label: String
    var value: String
    var dot: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                if let dot { Circle().fill(dot).frame(width: 4, height: 4) }
                Text(label).lineLimit(1)
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum Format {
    static func bytes(_ value: Double?, decimals: Int = 2) -> (String, String) {
        guard let value, value.isFinite, value >= 0 else { return ("—", "") }
        let units = ["B", "kB", "MB", "GB", "TB"]
        let exponent = value > 0 ? min(4, max(0, Int(log10(value) / 3))) : 0
        let scaled = value / pow(1000, Double(exponent))
        let precision = exponent < 2 ? 0 : decimals
        return (String(format: "%.*f", precision, scaled), units[exponent])
    }
    static func memory(_ value: Double?, decimals: Int = 2) -> String {
        let (number, unit) = bytes(value, decimals: decimals); return unit.isEmpty ? number : number + " " + unit
    }
    static func rate(_ value: Double?) -> String { value == nil ? "—" : memory(value, decimals: 1) + "/s" }
    static func percent(_ value: Double?, decimals: Int = 0) -> String { value.map { String(format: "%.*f%%", decimals, $0) } ?? "—" }
    static func number(_ value: Double?, decimals: Int = 0) -> String { value.map { String(format: "%.*f", decimals, $0) } ?? "—" }
    static func duration(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite, minutes >= 0 else { return "—" }
        let whole = Int(minutes); return whole >= 60 ? "\(whole / 60)h \(whole % 60)m" : "\(whole)m"
    }
    static func value(_ metric: Metric, _ snapshot: StatsCore.SystemSnapshot, decimals: Int = 2) -> (String, String) {
        switch metric {
        case .cpu, .gpu, .battery: return (number(metric.value(in: snapshot)), "%")
        case .memory, .disk: return bytes(metric.value(in: snapshot), decimals: decimals)
        case .network:
            let value = bytes(snapshot.download, decimals: min(1, decimals)); return (value.0, value.1.isEmpty ? "" : value.1 + "/s")
        default: return ("—", "")
        }
    }
}

import StatsCore

@MainActor final class IconCache {
    static let shared = IconCache()
    private var icons: [String: NSImage] = [:]
    func icon(for path: String) -> NSImage? {
        if let cached = icons[path] { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path); icons[path] = icon; return icon
    }
}

struct AppIcon: View {
    var path: String?
    var size: CGFloat = 28
    var body: some View {
        Group {
            if let path, let image = IconCache.shared.icon(for: path) { Image(nsImage: image).resizable().interpolation(.high) }
            else { Image(systemName: "terminal.fill").resizable().scaledToFit().padding(4).foregroundStyle(.secondary).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6)) }
        }.frame(width: size, height: size)
    }
}
