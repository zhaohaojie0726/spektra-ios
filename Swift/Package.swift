// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Spektra",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SpektraCore", targets: ["SpektraCore"]),
        .executable(name: "spektra-probe", targets: ["SpektraProbe"]),
        .executable(name: "spektra-cli", targets: ["SpektraCLI"]),
    ],
    targets: [
        .target(
            name: "SpektraCore",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "SpektraProbe",
            dependencies: ["SpektraCore"]
        ),
        .executableTarget(
            name: "SpektraCLI",
            dependencies: ["SpektraCore"]
        ),
        .testTarget(
            name: "SpektraCoreTests",
            dependencies: ["SpektraCore"]
        ),
    ],
    // Keep the package in Swift 5 language mode even under a Swift 6
    // toolchain: strict concurrency would reject the app's detached render
    // task, and none of the core is concurrent anyway.
    swiftLanguageVersions: [.v5]
)
