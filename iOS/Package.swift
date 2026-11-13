// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceSeedCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "VoiceSeedCore", targets: ["VoiceSeedCore"])],
    targets: [
        .target(name: "VoiceSeedCore", path: "Core"),
        .testTarget(name: "VoiceSeedCoreTests", dependencies: ["VoiceSeedCore"], path: "CoreTests")
    ],
    swiftLanguageModes: [.v5]
)
