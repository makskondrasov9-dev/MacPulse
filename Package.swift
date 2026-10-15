// swift-tools-version: 6.0
// MacPulse release 1.0.1 (build 18); bundle version is set by scripts/build-app.sh.
import PackageDescription

let package = Package(
    name: "iMacMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "iMacMonitor", targets: ["iMacMonitor"]),
        .executable(name: "MacPulseFanHelper", targets: ["MacPulseFanHelper"]),
        .library(name: "MonitorCore", targets: ["MonitorCore"])
    ],
    targets: [
        .target(name: "CSystem", publicHeadersPath: "include"),
        .target(name: "MonitorCore", dependencies: ["CSystem"],
                resources: [.process("Localization/Resources")],
                linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "MacPulseFanHelper", dependencies: ["MonitorCore"]),
        .executableTarget(name: "iMacMonitor", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore", "CSystem"])
    ],
    swiftLanguageModes: [.v6]
)
