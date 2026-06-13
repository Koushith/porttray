// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PortTray",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PortTray",
            path: "Sources/PortTray"
        )
    ]
)
