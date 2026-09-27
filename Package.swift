// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "zStats",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "zStats", targets: ["zStats"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "StatsCore"),
        .target(name: "CStats", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .executableTarget(name: "zStats", dependencies: ["StatsCore", "CStats", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.linkedFramework("AppKit"), .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "StatsCoreTests", dependencies: ["StatsCore"])
    ],
    swiftLanguageModes: [.v5]
)
