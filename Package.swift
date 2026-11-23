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
        // MaterialX (.mtlx) loading into PBR materials (#528).
        .library(name: "SceneSprocketsMaterialX", targets: ["SceneSprocketsMaterialX"]),
        .library(name: "SceneSprocketsBlinnPhong", targets: ["SceneSprocketsBlinnPhong"]),
        .library(name: "SceneSprocketsShaderMaterial", targets: ["SceneSprocketsShaderMaterial"]),
        .library(name: "SceneSprocketsAudio", targets: ["SceneSprocketsAudio"]),
        .library(name: "SceneSprocketsGizmos", targets: ["SceneSprocketsGizmos"]),
        // Bounding volume hierarchies for culling, hit testing and spatial queries (#337).
        .library(name: "SceneSprocketsBVH", targets: ["SceneSprocketsBVH"]),
        // For other packages' shaders that use the scene's lighting headers, such as BlinnPhongLighting.h.
        .library(name: "SceneSprocketsShaders", targets: ["SceneSprocketsShaders"]),
        // Lights, shadows, environment and tone mapping shared by every renderer (#547).
        .library(name: "MetalSprocketsLighting", targets: ["MetalSprocketsLighting"]),
        // Animation blending, playback and state machines shared by glTF and the scene graph (#589).
        .library(name: "MetalSprocketsAnimation", targets: ["MetalSprocketsAnimation"]),
        .library(name: "MetalSprocketsLightingShaders", targets: ["MetalSprocketsLightingShaders"]),
        // glTF 2.0 PBR renderer.
        .library(name: "MetalSprocketsPBR", targets: ["MetalSprocketsPBR"]),
        .library(name: "MetalSprocketsPBRShaders", targets: ["MetalSprocketsPBRShaders"]),
        // glTF loading for MetalSprocketsPBR.
        .library(name: "MetalSprocketsGLTF", targets: ["MetalSprocketsGLTF"]),
        .library(name: "MetalSprocketsGLTFBasisU", targets: ["MetalSprocketsGLTFBasisU"]),
        .library(name: "MetalSprocketsGLTFMeshopt", targets: ["MetalSprocketsGLTFMeshopt"]),
        .executable(name: "ms-gltf-render", targets: ["ms-gltf-render"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/GeometryLite3D", .upToNextMinor(from: "0.3.1")),
        .package(url: "https://github.com/schwa/MetalSprockets", .upToNextMinor(from: "0.3.10")),
        .package(url: "https://github.com/schwa/SwiftMesh", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/schwa/MetalSupport", .upToNextMinor(from: "1.0.7")),
        .package(url: "https://github.com/schwa/SwiftGLTF", .upToNextMinor(from: "1.0.7")),
        .package(url: "https://github.com/schwa/Interaction3D", .upToNextMinor(from: "0.2.2")),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", .upToNextMinor(from: "0.4.1")),
        .package(url: "https://github.com/schwa/SwiftJolt.git", .upToNextMinor(from: "0.0.4")),
        .package(url: "https://github.com/schwa/MetalSprocketsParticles", .upToNextMinor(from: "0.1.0")),
        .package(url: "https://github.com/schwa/MetalSprocketsAddOns", .upToNextMinor(from: "0.3.2")),
        .package(url: "https://github.com/schwa/SwiftECS", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/schwa/GoldenImage", .upToNextMinor(from: "0.1.7")),
        .package(url: "https://github.com/schwa/BasisUniversalMetal", .upToNextMinor(from: "0.0.3")),
        // No release tag yet (#665).
        .package(url: "https://github.com/schwa/MetalSprocketsMaterialX", branch: "main"),
    ],
    targets: [
        // MARK: MetalSprocketsLighting

        .target(
            name: "MetalSprocketsLightingShaders",
            exclude: ["Metal"],
            plugins: [
                .plugin(name: "MetalCompilerPlugin", package: "MetalCompilerPlugin")
            ]
        ),
        .target(
            name: "MetalSprocketsLighting",
            dependencies: [
                "MetalSprocketsLightingShaders",
                .product(name: "MetalSupport", package: "MetalSupport")
            ]
        ),
        .testTarget(
            name: "MetalSprocketsLightingTests",
            dependencies: ["MetalSprocketsLighting"]
        ),

        // MARK: MetalSprocketsAnimation

        .target(name: "MetalSprocketsAnimation"),

        // MARK: MetalSprocketsPBR

        .target(
            name: "MetalSprocketsPBRShaders",
            dependencies: [
                .product(name: "MetalSprocketsShaders", package: "MetalSprockets"),
                "MetalSprocketsLightingShaders",
                // MXShadingContext.h, for MaterialX surface functions (#666).
                .product(name: "MaterialXMetalShaders", package: "MetalSprocketsMaterialX")
            ],
            exclude: ["Metal"],
            plugins: [
                .plugin(name: "MetalCompilerPlugin", package: "MetalCompilerPlugin")
            ]
        ),
        .target(
            name: "MetalSprocketsPBR",
            dependencies: [
                "MetalSprocketsPBRShaders",
                "MetalSprocketsLighting",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D")
            ]
        ),
        .testTarget(
            name: "MetalSprocketsPBRTests",
            dependencies: [
                "MetalSprocketsPBR",
                "MetalSprocketsPBRShaders",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "GoldenImage", package: "GoldenImage"),
                .product(name: "MaterialX", package: "MetalSprocketsMaterialX"),
                .product(name: "MaterialXMetal", package: "MetalSprocketsMaterialX")
            ],
            resources: [
                .copy("GoldenImages")
            ]
        ),

        // MARK: MetalSprocketsGLTF

        .target(
            name: "MetalSprocketsGLTF",
            dependencies: [
                "MetalSprocketsAnimation",
                "MetalSprocketsPBR",
                "MetalSprocketsPBRShaders",
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
                .product(name: "SwiftMeshMikkTSpace", package: "SwiftMesh"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "MetalSupport", package: "MetalSupport")
            ]
        ),
        .executableTarget(
            name: "ms-gltf-render",
            dependencies: [
                "MetalSprocketsGLTF",
                "MetalSprocketsGLTFBasisU",
                "MetalSprocketsGLTFMeshopt",
                "MetalSprocketsPBR",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "MetalSprocketsGLTFBasisU",
            dependencies: [
                "MetalSprocketsGLTF",
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "BasisUniversalMetal", package: "BasisUniversalMetal")
            ]
        ),
        // meshoptimizer's decoder (vendored, MIT; see Sources/CMeshoptimizer/VERSION).
        .target(
            name: "CMeshoptimizer",
            exclude: ["LICENSE.md", "VERSION"]
        ),
        .target(
            name: "MetalSprocketsGLTFMeshopt",
            dependencies: [
                "CMeshoptimizer",
                .product(name: "SwiftGLTF", package: "SwiftGLTF")
            ]
        ),
        .testTarget(
            name: "MetalSprocketsGLTFMeshoptTests",
            dependencies: [
                "MetalSprocketsGLTFMeshopt",
                "MetalSprocketsGLTF",
                "MetalSprocketsPBR",
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "GoldenImage", package: "GoldenImage")
            ]
        ),
        .testTarget(
            name: "MetalSprocketsGLTFBasisUTests",
            dependencies: [
                "MetalSprocketsGLTFBasisU",
                "MetalSprocketsGLTF",
                "MetalSprocketsPBR",
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "GoldenImage", package: "GoldenImage")
            ],
            // Plain ASTC KTX2 images for EXT_texture_astc, from BasisUniversalMetal's tests: astc_6x6_srgb (one level)
            // and astc_8x8_srgb_zstd (full mip chain).
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "MetalSprocketsGLTFTests",
            dependencies: [
                "MetalSprocketsPBR",
                "MetalSprocketsPBRShaders",
                "MetalSprocketsGLTF",
                // The malformed-input tests also import into a scene graph, and encode meshopt data to decode.
                "SceneSprocketsPBR",
                "MetalSprocketsGLTFMeshopt",
                "CMeshoptimizer",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "GoldenImage", package: "GoldenImage")
            ],
            resources: [
                .copy("GoldenImages")
            ]
        ),

        // MARK: SceneSprockets

        .target(
            name: "SceneSprockets",
            dependencies: [
                "SceneSprocketsAudio",
                "SceneSprocketsBVH",
                "SceneSprocketsShaders",
                "MetalSprocketsAnimation",
                "MetalSprocketsLighting",
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
                "MetalSprocketsGLTF",
                "MetalSprocketsPBR",
                "MetalSprocketsPBRShaders",
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(
            name: "SceneSprocketsMaterialX",
            dependencies: [
                "SceneSprocketsPBR",
                "MetalSprocketsPBR",
                "MetalSprocketsPBRShaders",
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "MaterialX", package: "MetalSprocketsMaterialX"),
            ]
        ),
        .testTarget(
            name: "SceneSprocketsMaterialXTests",
            dependencies: [
                "SceneSprocketsMaterialX",
                "SceneSprocketsPBR",
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
                "MetalSprocketsLighting",
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
                "MetalSprocketsLighting",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(name: "SceneSprocketsAudio"),
        .testTarget(name: "SceneSprocketsAudioTests", dependencies: ["SceneSprocketsAudio"]),
        .target(name: "SceneSprocketsBVH", dependencies: [.product(name: "GeometryLite3D", package: "GeometryLite3D")]),
        .testTarget(name: "SceneSprocketsBVHTests", dependencies: ["SceneSprocketsBVH", .product(name: "GeometryLite3D", package: "GeometryLite3D")]),
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
            dependencies: [
                "MetalSprocketsLightingShaders"
            ],
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
                "MetalSprocketsGLTF",
                "MetalSprocketsPBR",
                "MetalSprocketsPBRShaders",
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
    ]
)
