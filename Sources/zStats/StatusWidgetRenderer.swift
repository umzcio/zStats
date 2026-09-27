import AppKit
import SwiftUI
import StatsCore

struct StatusWidgetDisplay {
    var widget: StatusWidget
    var metric: Metric
    var label: String
    var text: String
    var second: String? = nil
    var tooltip: String
    var fraction: Double?
    var history: [Double?]
    var width: CGFloat
}

@MainActor enum StatusWidgetRenderer {
    static func temperature(_ celsius: Double?, preference: TemperatureUnit, units: Bool = true) -> String {
        guard let celsius, celsius.isFinite else { return "—" }
        let fahrenheit = preference == .fahrenheit || (preference == .system && UnitTemperature(forLocale: .autoupdatingCurrent) == .fahrenheit)
        return Format.number(preference.converted(celsius, systemUsesFahrenheit: UnitTemperature(forLocale: .autoupdatingCurrent) == .fahrenheit)) + (units ? (fahrenheit ? "°F" : "°C") : "°")
    }
    static func displays(store: MonitorStore) -> [StatusWidgetDisplay] {
        store.preferences.visibleWidgets.compactMap { widget in
            guard let metric = Metric(rawValue: widget.metric) else { return nil }
            let s = store.snapshot
            let labels: [Metric: String] = [.cpu: "CPU", .memory: "MEM", .disk: "SSD", .network: "NET", .gpu: "GPU", .battery: "BAT"]
            let label = widget.customLabel.isEmpty ? labels[metric] ?? widget.metric : widget.customLabel
            var fraction: Double?
            switch metric {
            case .cpu, .gpu, .battery: fraction = metric.value(in: s).map { $0 / 100 }
            case .memory: fraction = s.memoryTotal > 0 ? s.memoryUsed / s.memoryTotal : nil
            case .disk: fraction = s.diskTotal > 0 ? (s.diskTotal - s.diskFree) / s.diskTotal : nil
            default: fraction = nil
            }
            let value = Format.value(metric, s, decimals: store.preferences.preciseNumbers ? 2 : 0)
            var text = value.0 + (widget.showUnits ? (value.1 == "%" ? "" : " ") + value.1 : "")
            var second: String?
            var tooltip = "\(metric.rawValue): \(value.0) \(value.1)"
            if widget.reading == .percentage || widget.style == .bar || widget.style == .vertical {
                text = Format.number(fraction.map { $0 * 100 }) + (widget.showUnits ? "%" : "")
                tooltip = metric.rawValue + (metric == .disk || metric == .memory ? " used: " : ": ") + text
            }
            if widget.reading == .traffic || widget.reading == .diskIO {
                let first = widget.reading == .traffic ? s.upload : s.diskRead
                let last = widget.reading == .traffic ? s.download : s.diskWrite
                func rate(_ v: Double?) -> String { widget.showUnits ? Format.rate(v) : Format.bytes(v, decimals: 1).0 }
                text = (widget.reading == .traffic ? "↑ " : "R ") + rate(first)
                second = (widget.reading == .traffic ? "↓ " : "W ") + rate(last)
                tooltip = metric.rawValue + ": " + text + " · " + second!
            }
            if widget.reading == .temperature {
                let degrees = metric == .cpu ? s.cpuTemperature : metric == .gpu ? s.gpuTemperature : s.batteryTemperature
                text = temperature(degrees, preference: store.preferences.temperatureUnit, units: widget.showUnits)
                tooltip = metric.rawValue + (metric == .battery ? " temperature: " : " average temperature: ") + temperature(degrees, preference: store.preferences.temperatureUnit)
            }
            var history = store.referenceMode ? store.chartHistory(for: metric) : Array(store.recent.suffix(30)).map { metric.historyValue($0) }
            if metric == .memory && widget.reading == .percentage { history = history.map { $0.map { s.memoryTotal > 0 ? $0 / s.memoryTotal * 100 : 0 } } }
            if metric == .disk && (widget.style == .graph || widget.style == .histogram) { tooltip = "Disk writes: " + Format.rate(s.diskWrite) }
            let prefix: CGFloat = widget.label == .none ? 0 : widget.label == .icon ? 18 : 25
            let width: CGFloat
            switch widget.style {
            case .icon: width = 20
            case .figure: width = prefix + (second != nil ? 154 : metric == .network || widget.reading == .diskIO ? 94 : 66)
            case .stacked: width = second != nil ? widget.width + 36 + prefix : widget.width + 12
            case .bar: width = widget.width
            case .vertical: width = (widget.label == .none ? 0 : 15) + 15
            case .graph, .histogram: width = widget.width + (widget.label == .none ? 0 : 18)
            }
            return StatusWidgetDisplay(widget: widget, metric: metric, label: label, text: text, second: second, tooltip: tooltip, fraction: fraction, history: history, width: width)
        }
    }

    static func image(displays: [StatusWidgetDisplay], spacing: Double, dark: Bool) -> NSImage {
        let width = max(20, displays.reduce(0) { $0 + $1.width } + CGFloat(max(0, displays.count - 1)) * spacing)
        let monochrome = dark ? NSColor.white : .black
        let rendered = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            if displays.isEmpty {
                let rect = NSRect(x: 1, y: 3, width: 18, height: 16)
                BrandMark.draw(in: rect.insetBy(dx: -2, dy: -2), color: monochrome, compact: true)
            }
            var x: CGFloat = 0
            for d in displays {
                let ink = color(d.widget.color, metric: d.metric, mono: monochrome)
                draw(d, x: x, ink: ink, textInk: monochrome)
                x += d.width + spacing
            }
            return true
        }
        rendered.isTemplate = displays.allSatisfy { $0.widget.color == .monochrome }
        return rendered
    }
    private static func color(_ color: WidgetColor, metric: Metric, mono: NSColor) -> NSColor {
        switch color {
        case .monochrome: return mono
        case .metric: return NSColor(metric.color)
        case .blue: return NSColor(Color(hex: 0x529CF8))
        case .purple: return NSColor(Color(hex: 0xA28AE5))
        case .green: return NSColor(Color(hex: 0x66B951))
        case .orange: return NSColor(Color(hex: 0xE1A342))
        case .pink: return NSColor(Color(hex: 0xD9689D))
        }
    }
    private static func text(_ value: String, _ rect: NSRect, color: NSColor, size: CGFloat = 10, align: NSTextAlignment = .center) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = align
        var font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        while (value as NSString).size(withAttributes: [.font: font]).width > rect.width && font.pointSize > 7 {
            font = .monospacedDigitSystemFont(ofSize: font.pointSize - 0.5, weight: .medium)
        }
        (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    private static func icon(_ d: StatusWidgetDisplay, x: CGFloat, y: CGFloat, ink: NSColor, size: CGFloat = 13) {
        if d.metric == .cpu {
            BrandMark.draw(in: NSRect(x: x - 2, y: y - 2, width: size + 4, height: size + 4), color: ink, compact: true)
            return
        }
        guard let symbol = NSImage(systemSymbolName: d.metric.symbol, accessibilityDescription: nil) else { return }
        let tinted = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            symbol.draw(in: rect); ink.setFill(); rect.fill(using: .sourceAtop); return true
        }
        tinted.draw(in: NSRect(x: x, y: y, width: size, height: size))
    }
    private static func verticalLabel(_ d: StatusWidgetDisplay, x: CGFloat, ink: NSColor) {
        if d.widget.label == .icon { icon(d, x: x, y: 5, ink: ink, size: 12) }
        else if d.widget.label == .short {
            for (i, c) in d.label.prefix(3).enumerated() { text(String(c), NSRect(x: x, y: 14 - CGFloat(i) * 7, width: 12, height: 8), color: ink, size: 7) }
        }
    }
    private static func draw(_ d: StatusWidgetDisplay, x: CGFloat, ink: NSColor, textInk: NSColor) {
        let w = d.width
        switch d.widget.style {
        case .icon: icon(d, x: x + 2, y: 3, ink: ink, size: 16)
        case .figure:
            let prefix: CGFloat = d.widget.label == .none ? 0 : d.widget.label == .icon ? 18 : 25
            if d.widget.label == .icon { icon(d, x: x, y: 4, ink: ink) }
            else if d.widget.label == .short { text(d.label, NSRect(x: x, y: 5, width: 24, height: 13), color: textInk, size: 8) }
            text(d.text + (d.second.map { "  " + $0 } ?? ""), NSRect(x: x + prefix, y: 3, width: w - prefix, height: 16), color: ink, size: 12)
        case .stacked:
            if let second = d.second {
                let prefix: CGFloat = d.widget.label == .none ? 0 : d.widget.label == .icon ? 18 : 25
                if d.widget.label == .icon { icon(d, x: x, y: 4, ink: ink) }
                else if d.widget.label == .short { text(d.label, NSRect(x: x, y: 5, width: prefix, height: 13), color: textInk, size: 8) }
                text(d.text, NSRect(x: x + prefix, y: 11, width: w - prefix, height: 11), color: ink, size: 9)
                text(second, NSRect(x: x + prefix, y: 0, width: w - prefix, height: 11), color: ink, size: 9)
            } else {
                if d.widget.label == .icon { icon(d, x: x + (w - 10) / 2, y: 12, ink: textInk, size: 9) }
                else if d.widget.label == .short { text(d.label, NSRect(x: x, y: 11, width: w, height: 11), color: textInk, size: 9) }
                text(d.text, NSRect(x: x, y: d.widget.label == .none ? 4 : 0, width: w, height: 12), color: ink, size: 10)
            }
        case .bar:
            let labeled = d.widget.label != .none
            if d.widget.label == .icon { icon(d, x: x + (w - 10) / 2, y: 12, ink: textInk, size: 9) }
            else if labeled { text(d.label, NSRect(x: x, y: 11, width: w, height: 11), color: textInk, size: 9) }
            let rect = NSRect(x: x + 1, y: labeled ? 1 : 5, width: w - 2, height: 9)
            textInk.withAlphaComponent(0.55).setStroke(); let outline = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3); outline.lineWidth = 1; outline.stroke()
            if let fraction = d.fraction { ink.setFill(); NSBezierPath(roundedRect: NSRect(x: rect.minX + 2, y: rect.minY + 2, width: (rect.width - 4) * min(1, max(0, fraction)), height: 5), xRadius: 1.5, yRadius: 1.5).fill() }
            else { text("—", rect, color: textInk, size: 7) }
        case .vertical:
            verticalLabel(d, x: x, ink: textInk)
            let gx = x + (d.widget.label == .none ? 0 : 15)
            let rect = NSRect(x: gx + 1, y: 1, width: 11, height: 20)
            textInk.withAlphaComponent(0.22).setFill(); NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            if let fraction = d.fraction { ink.setFill(); NSBezierPath(roundedRect: NSRect(x: gx + 3, y: 3, width: 7, height: 16 * min(1, max(0, fraction))), xRadius: 1, yRadius: 1).fill() }
            else { text("—", rect, color: textInk, size: 7) }
        case .graph, .histogram:
            verticalLabel(d, x: x, ink: textInk)
            let gx = x + (d.widget.label == .none ? 0 : 18)
            let gw = d.widget.width
            let values = d.widget.style == .histogram ? Array(d.history.suffix(14)) : d.history
            guard values.contains(where: { $0 != nil }) else { text("—", NSRect(x: gx, y: 3, width: gw, height: 16), color: textInk); return }
            let ceiling = max(1, (values.compactMap { $0 }.max() ?? 1) * 1.15)
            ink.setStroke(); ink.setFill()
            let path = NSBezierPath(); path.lineWidth = 1.2
            var connected = false
            for (i, sample) in values.enumerated() {
                guard let sample, sample.isFinite else { connected = false; continue }
                let h = max(0, min(1, sample / ceiling)) * 18
                if d.widget.style == .histogram {
                    let step = gw / CGFloat(max(1, values.count))
                    NSRect(x: gx + CGFloat(i) * step, y: 2, width: max(1, step - 1), height: max(0.7, h)).fill()
                } else {
                    let point = NSPoint(x: gx + CGFloat(i) / CGFloat(max(1, values.count - 1)) * gw, y: 2 + h)
                    if connected { path.line(to: point) } else { path.move(to: point); connected = true }
                }
            }
            path.stroke()
        }
    }
}
