import AppKit
import Combine
import SwiftUI
import StatsCore

/// Owns panel sizing and anchors every tab to the status item.
@MainActor final class MenuBarController: NSObject, ObservableObject {
    private var panelSize = MenuPanel.size
    private var item: NSStatusItem?
    private var panel: MenuBarPanel?
    private var store: MonitorStore?
    private var subscription: AnyCancellable?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var openDashboard: (() -> Void)?
    private var openPreferences: (() -> Void)?
    private var dockVisible: Bool?
    private var rememberedPosition: Bool?
    private var displays: [StatusWidgetDisplay] = []
    private var anchorOffset: CGFloat?
    private lazy var statusUpdate = CoalescedUpdate(enqueue: { action in
        DispatchQueue.main.async { action() }
    }) { [weak self] in
        self?.updateStatus()
    }

    func start(store: MonitorStore, openDashboard: @escaping () -> Void, openPreferences: @escaping () -> Void) {
        self.openDashboard = openDashboard
        self.openPreferences = openPreferences
        guard item == nil else { return }
        self.store = store
        let item = NSStatusBar.system.statusItem(withLength: 64)
        self.item = item
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "zStats")
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(toggle(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("zStats system monitor")
        }
        let panel = MenuBarPanel(contentRect: NSRect(origin: .zero, size: MenuPanel.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "zStats Menu"
        panel.identifier = NSUserInterfaceItemIdentifier("menu-panel")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        let hosting = NSHostingView(rootView: MenuPanel(openDashboard: { [weak self] in
            self?.hide()
            self?.openDashboard?()
        }, onSelectionChange: { [weak self] metric in
            self?.panelSize = MenuPanel.size(for: metric, monitors: store.enabledMetrics)
            self?.positionPanel()
        }, openPreferences: { [weak self] in
            self?.hide(); self?.openPreferences?()
        }).environmentObject(store))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        subscription = store.objectWillChange.sink { [weak self] in
            MainActor.assumeIsolated { self?.statusUpdate.request() }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible else { return false }
                if event.type == .keyDown, event.keyCode == 53, event.window === panel {
                    self.hide(); return true
                }
                // Leave native settings menus alone; dismiss for clicks in ordinary app windows.
                if event.type != .keyDown, event.window !== panel, event.window?.level == .normal { self.hide() }
                return false
            }
            return handled ? nil : event
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        updateStatus()
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if panel?.isVisible == true { hide(); return }
        var clicked: Metric?
        if let event = NSApp.currentEvent, let store {
            let point = sender.convert(event.locationInWindow, from: nil)
            var x = (sender.bounds.width - (sender.image?.size.width ?? 0)) / 2
            for display in displays {
                if point.x >= x && point.x <= x + display.width {
                    anchorOffset = x + display.width / 2
                    if store.preferences.openClickedMonitor { clicked = display.metric }
                    break
                }
                x += display.width + store.preferences.widgetSpacing
            }
        }
        show(metric: clicked, fromClick: true)
    }

    func show(metric: Metric? = nil, fromClick: Bool = false) {
        if !fromClick { anchorOffset = nil }
        if let store {
            store.menuSelection = metric ?? Metric(rawValue: store.preferences.menuDefault) ?? .overview
            panelSize = MenuPanel.size(for: store.menuSelection, monitors: store.enabledMetrics)
        }
        positionPanel()
        panel?.makeKeyAndOrderFront(nil)
        item?.button?.highlight(true)
    }

    private func positionPanel() {
        guard let panel, let button = item?.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max((anchorOffset.map { anchor.minX + $0 } ?? anchor.midX) - panelSize.width / 2, available.minX + 8), available.maxX - panelSize.width - 8)
        let y = max(available.minY + 8, anchor.minY - panelSize.height - 5)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: panelSize), display: true)
    }

    private func hide() {
        panel?.orderOut(nil)
        item?.button?.highlight(false)
    }

    private func updateStatus() {
        guard let store, let button = item?.button else { return }
        displays = StatusWidgetRenderer.displays(store: store)
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let image = StatusWidgetRenderer.image(displays: displays, spacing: store.preferences.widgetSpacing, dark: dark)
        item?.length = image.size.width + 12
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = image
        let summary = displays.map(\.tooltip).joined(separator: " · ")
        button.toolTip = summary.isEmpty ? "zStats" : summary
        button.setAccessibilityValue(summary.isEmpty ? "zStats" : summary)
        if rememberedPosition != store.preferences.keepMenuBarPosition {
            rememberedPosition = store.preferences.keepMenuBarPosition
            item?.autosaveName = store.preferences.keepMenuBarPosition ? "zStats.MenuBarLayout" : nil
        }
        if dockVisible != store.preferences.showDockIcon {
            dockVisible = store.preferences.showDockIcon
            NSApp.setActivationPolicy(store.preferences.showDockIcon ? .regular : .accessory)
        }
        let size = MenuPanel.size(for: store.menuSelection, monitors: store.enabledMetrics)
        if panelSize != size { panelSize = size; if panel?.isVisible == true { positionPanel() } }
    }
}

private final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct DashboardScene: View {
    @ObservedObject var store: MonitorStore
    let menuBar: MenuBarController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        DashboardView().environmentObject(store).onAppear {
            let open = openWindow
            menuBar.start(store: store, openDashboard: {
                open(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }, openPreferences: {
                openSettings(); NSApp.activate(ignoringOtherApps: true)
            })
        }
    }
}
