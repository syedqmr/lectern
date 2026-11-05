// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lectern",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lectern",
            path: "Sources/Lectern"
        )
    ]
)
