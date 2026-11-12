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
        .library(name: "SceneSprocketsGizmos", targets: ["SceneSprocketsGizmos"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/GeometryLite3D", .upToNextMinor(from: "0.3.1")),
        .package(url: "https://github.com/schwa/MetalSprockets", .upToNextMinor(from: "0.2.11")),
        .package(url: "https://github.com/schwa/SwiftMesh", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/schwa/MetalSupport", .upToNextMinor(from: "1.0.7")),
        .package(url: "https://github.com/schwa/MetalSprocketsPBR", .upToNextMinor(from: "0.1.2")),
        .package(url: "https://github.com/schwa/MetalSprocketsGLTF", .upToNextMinor(from: "0.0.7")),
        .package(url: "https://github.com/schwa/SwiftGLTF", .upToNextMinor(from: "1.0.6")),
        .package(url: "https://github.com/schwa/Interaction3D", .upToNextMinor(from: "0.2.1")),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", .upToNextMinor(from: "0.4.1")),
        .package(url: "https://github.com/schwa/SwiftJolt.git", .upToNextMinor(from: "0.0.1")),
        .package(url: "https://github.com/schwa/MetalSprocketsParticles", .upToNextMinor(from: "0.0.5")),
        .package(url: "https://github.com/schwa/MetalSprocketsAddOns", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftECS", .upToNextMinor(from: "0.1.1")),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "SceneSprockets",
            dependencies: [
                "SceneSprocketsAudio",
                "SceneSprocketsShaders",
                .product(name: "MetalSprocketsParticles", package: "MetalSprocketsParticles"),
                // Slug text for SceneText (#119).
                .product(name: "MetalSprocketsAddOns", package: "MetalSprocketsAddOns"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsSupport", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
                .product(name: "SwiftECS", package: "SwiftECS"),
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
        // Editor aids: transform gizmos drawn with MetalSprocketsAddOns' GraphicsContext3D (#154), and selection
        // outlines with its jump flood outline (#166).
        .target(
            name: "SceneSprocketsGizmos",
            dependencies: [
                "SceneSprockets",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsSupport", package: "MetalSprockets"),
                .product(name: "MetalSprocketsAddOns", package: "MetalSprocketsAddOns"),
                .product(name: "MetalSupport", package: "MetalSupport"),
            ]
        ),
        .testTarget(
            name: "SceneSprocketsGizmosTests",
            dependencies: [
                "SceneSprockets",
                "SceneSprocketsBlinnPhong",
                "SceneSprocketsGizmos",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
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
                .product(name: "MetalSupport", package: "MetalSupport"),
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
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
    ]
)
