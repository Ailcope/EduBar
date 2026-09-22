// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EduBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "EduBarCore"),
        .executableTarget(name: "EduBar", dependencies: ["EduBarCore"]),
        .testTarget(
            name: "EduBarCoreTests",
            dependencies: ["EduBarCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
