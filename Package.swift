// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Parchmatte",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "WindowListBridge",
            path: "Sources/WindowListBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Parchmatte",
            dependencies: ["WindowListBridge"],
            path: "Sources/Parchmatte",
            exclude: ["AppBundleInfo.xml"],
            resources: [.copy("Textures")]
        ),
        // Logic and offscreen material/rendering tests: `swift test` on macOS.
        // The rendering tests use WindowServer/Metal without showing targets;
        // interactive GUI suites stay in Tests/Harness.
        .testTarget(
            name: "ParchmatteTests",
            dependencies: ["Parchmatte", "WindowListBridgeTestSupport"],
            path: "Tests/ParchmatteTests",
            exclude: ["Fixtures"]
        ),
        .target(
            name: "WindowListBridgeTestSupport",
            dependencies: ["WindowListBridge"],
            path: "Tests/WindowListBridgeTestSupport",
            publicHeadersPath: "include"
        ),
    ]
)
