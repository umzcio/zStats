import AppKit

// Package the official supplied artwork; never redraw or overwrite the exports.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let source = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("assets/brand/zStats Exports/zStats-iOS-Default-1024@1x.png")
guard let artwork = NSImage(contentsOf: source) else {
    fatalError("Missing official app icon: \(source.path)")
}
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    // The export already includes rounded corners. Only add the macOS outer margin.
    let scale = CGFloat(size) / 1024
    artwork.draw(in: NSRect(x: 60 * scale, y: 60 * scale, width: 904 * scale, height: 904 * scale),
                 from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
}
