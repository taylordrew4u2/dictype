// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DicType",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DicType",
            path: "Sources/DicType"
        )
    ]
)
