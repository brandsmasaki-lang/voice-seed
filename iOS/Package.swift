// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceSeedCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "VoiceSeedCore", targets: ["VoiceSeedCore"])],
    dependencies: [.package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", exact: "0.11.2")],
    targets: [
        .target(name: "VoiceSeedCore", path: "Core"),
        .testTarget(name: "VoiceSeedCoreTests", dependencies: ["VoiceSeedCore",
            .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter")], path: "CoreTests")
    ],
    swiftLanguageModes: [.v5]
)
