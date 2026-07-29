// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DicType",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DicType",
            path: "Sources/DicType"
        ),
        // Covers the typewriter's revision state machine, which decides when to
        // emit backspaces. Getting that wrong deletes text the user typed, so it
        // is worth testing on every change.
        .testTarget(
            name: "DicTypeTests",
            dependencies: ["DicType"],
            path: "Tests/DicTypeTests"
        )
    ]
)
