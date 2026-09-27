import SwiftUI

struct BarHistory: View {
    var values: [Double?]
    var color: Color
    var ceiling: Double? = nil
    var body: some View {
        Canvas { context, size in
            let data = values; let maxValue = max(ceiling ?? data.compactMap { $0 }.max() ?? 1, 1)
            let count = max(56, data.count); let step = size.width / CGFloat(count)
            for (index, value) in data.enumerated() {
                guard let value else { continue }
                let height = max(2, min(1, max(0, value) / maxValue) * (size.height - 5))
                let x = CGFloat(index + count - data.count) * step
                let rect = CGRect(x: x, y: size.height - height, width: max(1, step - 1.5), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(0.88)))
            }
        }.padding(6).background(color.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Recent history, \(values.count) samples")
    }
}

struct AreaHistory: View {
    var values: [Double?]
    var color: Color
    var ceiling: Double? = nil
    var body: some View {
        Canvas { context, size in
            for fraction in [0.0, 0.33, 0.66, 1.0] {
                var grid = Path(); grid.move(to: CGPoint(x: 0, y: size.height * fraction)); grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(grid, with: .color(.secondary.opacity(0.14)), lineWidth: 0.7)
            }
            guard values.count > 1 else { return }
            let maxValue = max(ceiling ?? (values.compactMap { $0 }.max() ?? 1) * 1.15, 1)
            var segments: [[CGPoint]] = []
            var current: [CGPoint] = []
            for (index, value) in values.enumerated() {
                guard let value else {
                    if !current.isEmpty { segments.append(current); current = [] }
                    continue
                }
                current.append(CGPoint(x: size.width * Double(index) / Double(values.count - 1), y: size.height * (1 - min(1, max(0, value) / maxValue))))
            }
            if !current.isEmpty { segments.append(current) }
            for segment in segments {
                guard let first = segment.first, let last = segment.last else { continue }
                if segment.count == 1 {
                    context.fill(Path(ellipseIn: CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4)), with: .color(color)); continue
                }
                var line = Path(); line.addLines(segment)
                var area = line
                area.addLine(to: CGPoint(x: last.x, y: size.height)); area.addLine(to: CGPoint(x: first.x, y: size.height)); area.closeSubpath()
                context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.3), color.opacity(0.02)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            }
        }.overlay {
            if values.compactMap({ $0 }).count < 2 { Text("Collecting history…").font(.system(size: 11)).foregroundStyle(.secondary) }
        }.accessibilityLabel("History chart with \(values.count) samples")
    }
}

struct DonutSegment { var value: Double; var color: Color }
struct Donut: View {
    var segments: [DonutSegment]
    var value: String
    var subtitle: String
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.06), lineWidth: 10)
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                Circle().trim(from: start(index), to: max(start(index), end(index) - 0.012))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 10, lineCap: .butt)).rotationEffect(.degrees(-90))
            }
            VStack(spacing: 3) {
                Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                Text(subtitle).font(.system(size: 8)).foregroundStyle(.secondary)
            }.padding(10)
        }.padding(6).frame(width: 94, height: 94)
    }
    private var total: Double { max(segments.reduce(0) { $0 + max(0, $1.value) }, 1) }
    private func start(_ index: Int) -> Double { segments.prefix(index).reduce(0) { $0 + max(0, $1.value) } / total }
    private func end(_ index: Int) -> Double { start(index) + max(0, segments[index].value) / total }
}
