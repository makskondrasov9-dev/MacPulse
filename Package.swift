// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iMacMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "iMacMonitor", targets: ["iMacMonitor"]),
        .library(name: "MonitorCore", targets: ["MonitorCore"])
    ],
    targets: [
        .target(name: "CSystem", publicHeadersPath: "include"),
        .target(name: "MonitorCore", dependencies: ["CSystem"],
                linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "iMacMonitor", dependencies: ["MonitorCore"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore", "CSystem"])
    ],
    swiftLanguageModes: [.v6]
)
