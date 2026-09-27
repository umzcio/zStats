import AppKit

@MainActor enum AppAppearance {
    static func apply(_ preference: String) {
        let application = NSApplication.shared
        switch preference {
        case "Light": application.appearance = NSAppearance(named: .aqua)
        case "Dark": application.appearance = NSAppearance(named: .darkAqua)
        default: application.appearance = nil
        }
        // Windows and sheets must inherit the app setting. Clearing just a
        // SwiftUI preference can leave an earlier window override in place.
        for window in application.windows { window.appearance = nil }
    }
}
