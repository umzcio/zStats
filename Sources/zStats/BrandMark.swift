import AppKit

// One vector master for the app icon, exported artwork and status-bar mark.
enum BrandMark {
    private static let top: [CGPoint] = [
        .init(x: 230, y: 190), .init(x: 812, y: 190),
        .init(x: 606, y: 458), .init(x: 600, y: 270),
        .init(x: 550, y: 302), .init(x: 174, y: 302)
    ]
    private static let bottom: [CGPoint] = [
        .init(x: 350, y: 552), .init(x: 208, y: 846),
        .init(x: 738, y: 846), .init(x: 794, y: 734),
        .init(x: 361, y: 734), .init(x: 376, y: 712)
    ]
    private static func pulse(compact: Bool) -> [CGPoint] {
        [
            .init(x: 100, y: 530), .init(x: 326, y: 510),
            .init(x: 390, y: 418), .init(x: 411, y: 590),
            .init(x: 578, y: 302), .init(x: 578, y: 554),
            .init(x: 617, y: 498), .init(x: 924, y: 516),
            .init(x: 634, y: compact ? 554 : 539),
            .init(x: 548, y: 674), .init(x: 548, y: compact ? 475 : 446),
            .init(x: 390, y: 706), .init(x: 364, y: compact ? 510 : 490),
            .init(x: 341, y: 548)
        ]
    }
    private static func path(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }
    static func draw(in rect: CGRect, color: NSColor, compact: Bool = false) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / 1024, y: -rect.height / 1024)
        context.setFillColor(color.cgColor)
        for points in [top, bottom, pulse(compact: compact)] {
            context.addPath(path(points))
            context.fillPath()
        }
        context.restoreGState()
    }
    static func svg(color: String, compact: Bool = false, tile: Bool = false) -> String {
        func data(_ points: [CGPoint]) -> String {
            points.enumerated().map { "\($0.offset == 0 ? "M" : "L")\(Int($0.element.x)) \(Int($0.element.y))" }.joined(separator: " ") + " Z"
        }
        let backdrop = tile ? "<rect x=\"60\" y=\"60\" width=\"904\" height=\"904\" rx=\"210\" fill=\"#19191d\" stroke=\"#39393e\" stroke-width=\"3\"/>" : ""
        let paths = [top, bottom, pulse(compact: compact)].map { "<path d=\"\(data($0))\"/>" }.joined(separator: "\n    ")
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="zStats Z and pulse logo">
          \(backdrop)
          <g fill="\(color)">
            \(paths)
          </g>
        </svg>
        """
    }
}
