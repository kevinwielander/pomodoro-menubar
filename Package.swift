// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PomodoroBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PomodoroCore"),
        .executableTarget(name: "PomodoroBar", dependencies: ["PomodoroCore"]),
        .testTarget(name: "PomodoroCoreTests", dependencies: ["PomodoroCore"]),
    ]
)
