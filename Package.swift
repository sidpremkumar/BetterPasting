// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BetterPasting",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "BetterPasting", targets: ["BetterPasting"])
    ],
    targets: [
        .executableTarget(
            name: "BetterPasting",
            path: "BetterPasting/Sources",
            resources: [
                .process("../Resources")
            ]
        ),
        .testTarget(
            name: "BetterPastingTests",
            dependencies: ["BetterPasting"],
            path: "BetterPasting/Tests"
        )
    ]
)
