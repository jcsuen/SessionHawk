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
        // Everything except the @main entry lives in the library so the test
        // runner can import it (executable targets can't be imported).
        .target(
            name: "SessionHawkCore",
            dependencies: [],
            path: "Sources",
            exclude: ["App"]
        ),
        .executableTarget(
            name: "SessionHawk",
            dependencies: ["SessionHawkCore"],
            path: "Sources/App"
        ),
        // Plain executable runner, not XCTest: this machine has only CLT
        // (no XCTest); `swift run SessionHawkTests` works locally and on CI.
        .executableTarget(
            name: "SessionHawkTests",
            dependencies: ["SessionHawkCore"],
            path: "Tests"
        )
    ]
)
