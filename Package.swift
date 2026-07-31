// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SessionHawk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SessionHawk", targets: ["SessionHawk"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SessionHawk",
            dependencies: [],
            path: "Sources"
        )
    ]
)
