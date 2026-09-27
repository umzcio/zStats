import SwiftUI
import AppKit

/// Renders view artifacts from reference data. Does not inspect windows or capture the desktop.
@MainActor enum PreviewRenderer {
    static func render(to directory: URL) throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        MachineModel.shared.info = MachineInfo.read()
        MachineModel.shared.refreshDisplays()
        for metric in Metric.allCases {
            let store = MonitorStore(startSampling: false)
            store.referenceMode = true
            store.selected = metric
            let view = DashboardView().environmentObject(store).frame(width: 1060, height: 720).environment(\.colorScheme, .dark)
            try capture(view, size: NSSize(width: 1060, height: 720), to: directory.appendingPathComponent(metric.rawValue.lowercased() + ".png"))
        }
        for metric in Metric.allCases.filter({ $0 != .machine }) {
            let store = MonitorStore(startSampling: false)
            store.referenceMode = true
            store.selected = metric
            store.menuSelection = metric
            let name = metric == .overview ? "menu-bar.png" : "menu-bar-\(metric.rawValue.lowercased()).png"
            try capture(MenuPanel().environmentObject(store).environment(\.colorScheme, .dark), size: MenuPanel.size(for: metric), to: directory.appendingPathComponent(name))
        }
        let settingsStore = MonitorStore(startSampling: false)
        try capture(SettingsView().environmentObject(settingsStore), size: NSSize(width: 800, height: 650), to: directory.appendingPathComponent("settings.png"))
        print("Rendered reference previews to \(directory.path)")
    }

    private static func capture<Content: View>(_ content: Content, size: NSSize, to url: URL) throws {
        // ImageRenderer omits AppKit-backed scroll views and controls. Lay out an
        // unshown hosting window instead; no running app or screen is captured.
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        window.close()
    }
}
