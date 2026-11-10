// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SceneSprocketsComposerSupport",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "SceneSprocketsComposerSupport", targets: ["SceneSprocketsComposerSupport"]),
    ],
    dependencies: [
        // Local checkout so editor and engine can change together. SwiftPM names it after its folder.
        .package(path: "../../.."),
        .package(url: "https://github.com/schwa/GeometryLite3D", .upToNextMinor(from: "0.2.7")),
        .package(url: "https://github.com/schwa/Interaction3D", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/schwa/MetalSprockets", .upToNextMinor(from: "0.2.9")),
        .package(url: "https://github.com/schwa/MetalSprocketsAddOns", .upToNextMinor(from: "0.2.5")),
        .package(url: "https://github.com/schwa/MetalSprocketsPBR", .upToNextMinor(from: "0.0.3")),
        .package(url: "https://github.com/schwa/MetalSupport", .upToNextMinor(from: "1.0.7")),
        .package(url: "https://github.com/schwa/SwiftMesh", .upToNextMinor(from: "0.0.11")),
        .package(url: "https://github.com/schwa/SwiftFields", .upToNextMinor(from: "0.1.5")),
        .package(url: "https://github.com/schwa/CollaborationKit", from: "0.2.5"),
    ],
    targets: [
        .target(
            name: "SceneSprocketsComposerSupport",
            dependencies: [
                .product(name: "SceneSprockets", package: "SceneSprockets"),
                .product(name: "SceneSprocketsBlinnPhong", package: "SceneSprockets"),
                .product(name: "SceneSprocketsGizmos", package: "SceneSprockets"),
                .product(name: "SceneSprocketsPBR", package: "SceneSprockets"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "MetalSprocketsAddOns", package: "MetalSprocketsAddOns"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
                .product(name: "SwiftFields", package: "SwiftFields"),
                .product(name: "CollaborationKit", package: "CollaborationKit"),
                .product(name: "CollaborationKitUI", package: "CollaborationKit"),
            ]
        ),
        .testTarget(
            name: "SceneSprocketsComposerSupportTests",
            dependencies: ["SceneSprocketsComposerSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
