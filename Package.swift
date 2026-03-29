// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmartScreenShot",
    platforms: [.macOS(.v13)],
    targets: [
        // Naming brain CLI — test slugs against any image
        .executableTarget(
            name: "sst",
            dependencies: ["SmartScreenShotCore"],
            path: "Sources/CLI"
        ),
        // Background daemon — watches screenshot folder and renames automatically
        .executableTarget(
            name: "ssd",
            dependencies: ["SmartScreenShotCore"],
            path: "Sources/Daemon"
        ),
        // Shared library — all naming tiers, daemon types, slug logic
        .target(
            name: "SmartScreenShotCore",
            path: "Sources/Core"
        )
    ]
)
