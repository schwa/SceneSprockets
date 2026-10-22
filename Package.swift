// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SceneSprockets",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "SceneSprockets", targets: ["SceneSprockets"]),
        .library(name: "SceneSprocketsPhysics", targets: ["SceneSprocketsPhysics"]),
        .library(name: "SceneSprocketsPBR", targets: ["SceneSprocketsPBR"]),
        .library(name: "SceneSprocketsBlinnPhong", targets: ["SceneSprocketsBlinnPhong"]),
        .library(name: "SceneSprocketsShaderMaterial", targets: ["SceneSprocketsShaderMaterial"]),
        .library(name: "SceneSprocketsAudio", targets: ["SceneSprocketsAudio"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/GeometryLite3D", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprockets", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftMesh", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSupport", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprocketsPBR", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprocketsGLTF", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftGLTF", branch: "main"),
        .package(url: "https://github.com/schwa/Interaction3D", branch: "main"),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", .upToNextMinor(from: "0.4.1")),
        .package(url: "https://github.com/schwa/SwiftJolt.git", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprocketsParticles", branch: "main"),
    ],
    targets: [
        .target(
            name: "SceneSprockets",
            dependencies: [
                "SceneSprocketsAudio",
                "SceneSprocketsShaders",
                .product(name: "MetalSprocketsParticles", package: "MetalSprocketsParticles"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsSupport", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        // PBR materials and the loaders that make them (glTF, Model I/O). Model I/O can also make Blinn-Phong materials.
        .target(
            name: "SceneSprocketsPBR",
            dependencies: [
                "SceneSprockets",
                "SceneSprocketsBlinnPhong",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsGLTF", package: "MetalSprocketsGLTF"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "MetalSprocketsPBRShaders", package: "MetalSprocketsPBR"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(
            name: "SceneSprocketsBlinnPhong",
            dependencies: [
                "SceneSprockets",
                "SceneSprocketsShaders",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(
            name: "SceneSprocketsShaderMaterial",
            dependencies: [
                "SceneSprockets",
                "SceneSprocketsShaders",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(name: "SceneSprocketsAudio"),
        .testTarget(name: "SceneSprocketsAudioTests", dependencies: ["SceneSprocketsAudio"]),
        .target(
            name: "SceneSprocketsPhysics",
            dependencies: [
                "SceneSprockets",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "JoltPhysics", package: "SwiftJolt"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .testTarget(
            name: "SceneSprocketsPhysicsTests",
            dependencies: [
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                "SceneSprockets",
                "SceneSprocketsPhysics",
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(
            name: "SceneSprocketsShaders",
            exclude: ["Metal"],
            plugins: [
                .plugin(name: "MetalCompilerPlugin", package: "MetalCompilerPlugin")
            ]
        ),
        .testTarget(
            name: "SceneSprocketsTests",
            dependencies: [
                "SceneSprocketsAudio",
                "SceneSprockets",
                "SceneSprocketsBlinnPhong",
                "SceneSprocketsPBR",
                "SceneSprocketsShaderMaterial",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsGLTF", package: "MetalSprocketsGLTF"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "MetalSprocketsPBRShaders", package: "MetalSprocketsPBR"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
    ]
)
