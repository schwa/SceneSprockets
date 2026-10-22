// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SceneSprocketDemos",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "SceneSprocketDemos", targets: ["SceneSprocketDemos"]),
        .executable(name: "scenesprocket-demos", targets: ["scenesprocket-demos"]),
    ],
    dependencies: [
        // The repository root. Its package identity is the folder name: change "MetalSprocketsSceneGraph" below to "SceneSprocket" when the folder is renamed.
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
            name: "SceneSprocketDemos",
            dependencies: [
                .product(name: "SceneSprocket", package: "MetalSprocketsSceneGraph"),
                .product(name: "SceneSprocketPhysics", package: "MetalSprocketsSceneGraph"),
                .product(name: "MetalSprocketsParticles", package: "MetalSprocketsParticles"),
                .product(name: "MetalSprocketsParticlesSamples", package: "MetalSprocketsParticles"),
                .product(name: "SceneSprocketPBR", package: "MetalSprocketsSceneGraph"),
                .product(name: "SceneSprocketBlinnPhong", package: "MetalSprocketsSceneGraph"),
                .product(name: "SceneSprocketShaderMaterial", package: "MetalSprocketsSceneGraph"),
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
            name: "scenesprocket-demos",
            dependencies: [
                "SceneSprocketDemos",
                .product(name: "DemoKit", package: "DemoKit"),
            ]
        ),
        .testTarget(
            name: "SceneSprocketDemosTests",
            dependencies: [
                "SceneSprocketDemos",
                .product(name: "SceneSprocket", package: "MetalSprocketsSceneGraph"),
                .product(name: "SceneSprocketBlinnPhong", package: "MetalSprocketsSceneGraph"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "GoldenImage", package: "GoldenImage"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "DemoKit", package: "DemoKit"),
            ],
            resources: [.copy("Golden Images")]
        ),
    ]
)
