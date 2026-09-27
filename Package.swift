// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "zStats",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "zStats", targets: ["zStats"])],
    targets: [
        .target(name: "StatsCore"),
        .target(name: "CStats", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .executableTarget(name: "zStats", dependencies: ["StatsCore", "CStats"], linkerSettings: [.linkedFramework("AppKit")]),
        .testTarget(name: "StatsCoreTests", dependencies: ["StatsCore"])
    ],
    swiftLanguageModes: [.v5]
)
