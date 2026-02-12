// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouseManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MouseManager", targets: ["MouseManager"])
    ],
    targets: [
        .executableTarget(
            name: "MouseManager",
            path: "Sources"
        )
    ]
)

