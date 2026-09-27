import SwiftUI

/// Small outline glyphs matching the compact menu's proportions.
struct MenuGlyph: View {
    enum Kind { case memory, disk, window }
    let kind: Kind
    var body: some View {
        GlyphPath(kind: kind).stroke(.foreground, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            .frame(width: 12, height: 12).accessibilityHidden(true)
    }
    private struct GlyphPath: Shape {
        let kind: Kind
        func path(in rect: CGRect) -> Path {
            var path = Path()
            switch kind {
            case .memory:
                path.addRoundedRect(in: CGRect(x: 0.7, y: 2, width: 10.6, height: 6), cornerSize: CGSize(width: 1, height: 1))
                for x in [4.2, 7.8] { path.move(to: CGPoint(x: x, y: 2)); path.addLine(to: CGPoint(x: x, y: 8)) }
                for x in [2.5, 6.0, 9.5] { path.move(to: CGPoint(x: x, y: 8)); path.addLine(to: CGPoint(x: x, y: 10.6)) }
            case .disk:
                path.addRoundedRect(in: CGRect(x: 0.8, y: 1.7, width: 10.4, height: 8.6), cornerSize: CGSize(width: 1.5, height: 1.5))
                path.move(to: CGPoint(x: 1, y: 7)); path.addLine(to: CGPoint(x: 11, y: 7))
                path.move(to: CGPoint(x: 8.9, y: 8.7)); path.addLine(to: CGPoint(x: 9, y: 8.7))
            case .window:
                path.addRoundedRect(in: CGRect(x: 0.8, y: 1.2, width: 10.4, height: 9.6), cornerSize: CGSize(width: 1.6, height: 1.6))
                path.move(to: CGPoint(x: 1, y: 4.2)); path.addLine(to: CGPoint(x: 11, y: 4.2))
            }
            return path.applying(CGAffineTransform(scaleX: rect.width / 12, y: rect.height / 12))
        }
    }
}

struct MenuMetricIcon: View {
    let metric: Metric
    var body: some View {
        switch metric {
        case .memory: MenuGlyph(kind: .memory)
        case .disk: MenuGlyph(kind: .disk)
        default: Image(systemName: metric.menuSymbol).font(.system(size: 12, weight: .regular)).frame(width: 12, height: 12)
        }
    }
}
