// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MetalSprocketsSceneGraph",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "MetalSprocketsSceneGraph", targets: ["MetalSprocketsSceneGraph"]),
        .library(name: "MetalSprocketsSceneGraphPhysics", targets: ["MetalSprocketsSceneGraphPhysics"]),
        .library(name: "MetalSprocketsSceneGraphPBR", targets: ["MetalSprocketsSceneGraphPBR"]),
        .library(name: "MetalSprocketsSceneGraphBlinnPhong", targets: ["MetalSprocketsSceneGraphBlinnPhong"]),
        .library(name: "MetalSprocketsSceneGraphShaderMaterial", targets: ["MetalSprocketsSceneGraphShaderMaterial"]),
        .library(name: "MetalSprocketsAudio", targets: ["MetalSprocketsAudio"]),
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
            name: "MetalSprocketsSceneGraph",
            dependencies: [
                "MetalSprocketsAudio",
                "MetalSprocketsSceneGraphShaders",
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
            name: "MetalSprocketsSceneGraphPBR",
            dependencies: [
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphBlinnPhong",
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
            name: "MetalSprocketsSceneGraphBlinnPhong",
            dependencies: [
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphShaders",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(
            name: "MetalSprocketsSceneGraphShaderMaterial",
            dependencies: [
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphShaders",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(name: "MetalSprocketsAudio"),
        .testTarget(name: "MetalSprocketsAudioTests", dependencies: ["MetalSprocketsAudio"]),
        .target(
            name: "MetalSprocketsSceneGraphPhysics",
            dependencies: [
                "MetalSprocketsSceneGraph",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "JoltPhysics", package: "SwiftJolt"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .testTarget(
            name: "MetalSprocketsSceneGraphPhysicsTests",
            dependencies: [
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphPhysics",
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(
            name: "MetalSprocketsSceneGraphShaders",
            exclude: ["Metal"],
            plugins: [
                .plugin(name: "MetalCompilerPlugin", package: "MetalCompilerPlugin")
            ]
        ),
        .testTarget(
            name: "MetalSprocketsSceneGraphTests",
            dependencies: [
                "MetalSprocketsAudio",
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphBlinnPhong",
                "MetalSprocketsSceneGraphPBR",
                "MetalSprocketsSceneGraphShaderMaterial",
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
