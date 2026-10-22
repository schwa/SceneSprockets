// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SceneSprocketsDemos",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "SceneSprocketsDemos", targets: ["SceneSprocketsDemos"]),
        .executable(name: "scenesprockets-demos", targets: ["scenesprockets-demos"]),
    ],
    dependencies: [
        // The repository root. SwiftPM names a local package after its folder, "SceneSprockets".
        .package(path: "../../.."),
        .package(url: "https://github.com/schwa/GeometryLite3D", .upToNextMinor(from: "0.2.4")),
        .package(url: "https://github.com/schwa/MetalSprockets", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftMesh", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSupport", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprocketsPBR", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprocketsGLTF", branch: "main"),
        .package(url: "https://github.com/schwa/Interaction3D", branch: "main"),
        .package(url: "https://github.com/schwa/DemoKit", branch: "main"),
        .package(url: "https://github.com/schwa/GoldenImage", .upToNextMinor(from: "0.1.6")),
        .package(url: "https://github.com/schwa/MetalSprocketsParticles", branch: "main"),
    ],
    targets: [
        .target(
            name: "SceneSprocketsDemos",
            dependencies: [
                .product(name: "SceneSprockets", package: "SceneSprockets"),
                .product(name: "SceneSprocketsPhysics", package: "SceneSprockets"),
                .product(name: "MetalSprocketsParticles", package: "MetalSprocketsParticles"),
                .product(name: "MetalSprocketsParticlesSamples", package: "MetalSprocketsParticles"),
                .product(name: "SceneSprocketsPBR", package: "SceneSprockets"),
                .product(name: "SceneSprocketsBlinnPhong", package: "SceneSprockets"),
                .product(name: "SceneSprocketsShaderMaterial", package: "SceneSprockets"),
                .product(name: "SceneSprocketsGizmos", package: "SceneSprockets"),
                .product(name: "DemoKit", package: "DemoKit"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "MetalSprocketsGLTF", package: "MetalSprocketsGLTF"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprocketsSupport", package: "MetalSprockets"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ],
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "scenesprockets-demos",
            dependencies: [
                "SceneSprocketsDemos",
                .product(name: "DemoKit", package: "DemoKit"),
            ]
        ),
        .testTarget(
            name: "SceneSprocketsDemosTests",
            dependencies: [
                "SceneSprocketsDemos",
                .product(name: "SceneSprockets", package: "SceneSprockets"),
                .product(name: "SceneSprocketsBlinnPhong", package: "SceneSprockets"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "GoldenImage", package: "GoldenImage"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "DemoKit", package: "DemoKit"),
            ],
            resources: [.copy("Golden Images")]
        ),
    ]
)
