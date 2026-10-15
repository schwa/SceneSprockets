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
        .library(name: "MetalSprocketsSceneGraphRenderer", targets: ["MetalSprocketsSceneGraphRenderer"]),
        .library(name: "MetalSprocketsSceneGraphPBR", targets: ["MetalSprocketsSceneGraphPBR"]),
        .library(name: "MetalSprocketsSceneGraphUI", targets: ["MetalSprocketsSceneGraphUI"]),
        .library(name: "MetalSprocketsSceneGraphModelIO", targets: ["MetalSprocketsSceneGraphModelIO"]),
        .library(name: "MetalSprocketsSceneGraphGLTF", targets: ["MetalSprocketsSceneGraphGLTF"]),
        .library(name: "MetalSprocketsSceneGraphDemos", targets: ["MetalSprocketsSceneGraphDemos"]),
        .executable(name: "scenegraph-demos", targets: ["scenegraph-demos"]),
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/GeometryLite3D", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprockets", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprocketsAddOns", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftMesh", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSupport", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprocketsPBR", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprocketsGLTF", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftGLTF", branch: "main"),
        .package(url: "https://github.com/schwa/Interaction3D", branch: "main"),
        .package(url: "https://github.com/schwa/MetalCompilerPlugin", from: "0.4.1"),
        .package(url: "https://github.com/schwa/DemoKit", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftJolt.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "MetalSprocketsSceneGraph",
            dependencies: [
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprocketsAddOns", package: "MetalSprocketsAddOns"),
                .product(name: "MetalSprocketsAddOnsShaders", package: "MetalSprocketsAddOns"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(
            name: "MetalSprocketsSceneGraphRenderer",
            dependencies: [
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphShaders",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsSupport", package: "MetalSprockets"),
                .product(name: "MetalSprocketsAddOns", package: "MetalSprocketsAddOns"),
                .product(name: "MetalSprocketsAddOnsShaders", package: "MetalSprocketsAddOns"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(
            name: "MetalSprocketsSceneGraphPBR",
            dependencies: [
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphRenderer",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "MetalSprocketsPBRShaders", package: "MetalSprocketsPBR"),
                .product(name: "MetalSupport", package: "MetalSupport"),
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
        .target(
            name: "MetalSprocketsSceneGraphUI",
            dependencies: [
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphRenderer",
                "MetalSprocketsSceneGraphPBR",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "MetalSprocketsAddOnsShaders", package: "MetalSprocketsAddOns"),
            ]
        ),
        .target(
            name: "MetalSprocketsSceneGraphModelIO",
            dependencies: [
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphRenderer",
                "MetalSprocketsSceneGraphPBR",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprocketsAddOns", package: "MetalSprocketsAddOns"),
                .product(name: "MetalSprocketsAddOnsShaders", package: "MetalSprocketsAddOns"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(
            name: "MetalSprocketsSceneGraphGLTF",
            dependencies: [
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphPBR",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprocketsAddOnsShaders", package: "MetalSprocketsAddOns"),
                .product(name: "MetalSprocketsGLTF", package: "MetalSprocketsGLTF"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .target(
            name: "MetalSprocketsSceneGraphDemos",
            dependencies: [
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphRenderer",
                "MetalSprocketsSceneGraphPBR",
                "MetalSprocketsSceneGraphGLTF",
                "MetalSprocketsSceneGraphModelIO",
                "MetalSprocketsSceneGraphUI",
                .product(name: "DemoKit", package: "DemoKit"),
                .product(name: "JoltPhysics", package: "SwiftJolt"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "MetalSprocketsGLTF", package: "MetalSprocketsGLTF"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprocketsSupport", package: "MetalSprockets"),
                .product(name: "MetalSprocketsAddOns", package: "MetalSprocketsAddOns"),
                .product(name: "MetalSprocketsAddOnsShaders", package: "MetalSprocketsAddOns"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ],
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "scenegraph-demos",
            dependencies: [
                "MetalSprocketsSceneGraphDemos",
                .product(name: "DemoKit", package: "DemoKit"),
            ]
        ),
        .testTarget(
            name: "MetalSprocketsSceneGraphTests",
            dependencies: [
                "MetalSprocketsSceneGraph",
                "MetalSprocketsSceneGraphRenderer",
                "MetalSprocketsSceneGraphPBR",
                "MetalSprocketsSceneGraphDemos",
                "MetalSprocketsSceneGraphGLTF",
                "MetalSprocketsSceneGraphModelIO",
                "MetalSprocketsSceneGraphUI",
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsGLTF", package: "MetalSprocketsGLTF"),
                .product(name: "MetalSprocketsAddOns", package: "MetalSprocketsAddOns"),
                .product(name: "MetalSprocketsAddOnsShaders", package: "MetalSprocketsAddOns"),
                .product(name: "MetalSprocketsPBR", package: "MetalSprocketsPBR"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
    ]
)
