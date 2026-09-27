import Foundation
import StatsCore

/// Resolve bundle display names once instead of showing executable/bundle identifiers.
final class AppNameResolver {
    private var names: [String: String] = [:]
    func name(for app: AppReading) -> String {
        if let path = app.bundlePath {
            if let cached = names[path] { return cached }
            let bundle = Bundle(path: path)
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? app.name
            names[path] = name
            return name
        }
        switch app.name {
        case "com.apple.WebKit.WebContent": return "Web Content"
        case "com.apple.WebKit.Networking": return "Web Networking"
        case "com.apple.WebKit.GPU": return "Web Graphics"
        default: return app.name
        }
    }
}
