// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "dictype",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "dictype",
            path: "Sources"
        )
    ]
)
