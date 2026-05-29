// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentHUD",
    platforms: [.macOS(.v14)],   // TimelineView .animation(paused:), SMAppService, etc.
    targets: [
        .executableTarget(
            name: "AgentHUD",
            path: "Sources/AgentNotifier"   // source dir kept; product/binary is "AgentHUD"
        )
    ]
)
