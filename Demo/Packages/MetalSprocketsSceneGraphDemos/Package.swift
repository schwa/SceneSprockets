// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MetalSprocketsSceneGraphDemos",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "MetalSprocketsSceneGraphDemos", targets: ["MetalSprocketsSceneGraphDemos"]),
        .executable(name: "scenegraph-demos", targets: ["scenegraph-demos"]),
    ],
    dependencies: [
        .package(path: "../../.."),
        .package(url: "https://github.com/schwa/GeometryLite3D", from: "0.2.3"),
        .package(url: "https://github.com/schwa/MetalSprockets", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftMesh", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSupport", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprocketsPBR", branch: "main"),
        .package(url: "https://github.com/schwa/MetalSprocketsGLTF", branch: "main"),
        .package(url: "https://github.com/schwa/Interaction3D", branch: "main"),
        .package(url: "https://github.com/schwa/DemoKit", branch: "main"),
        .package(url: "https://github.com/schwa/GoldenImage", from: "0.1.5"),
    ],
    targets: [
        .target(
            name: "MetalSprocketsSceneGraphDemos",
            dependencies: [
                .product(name: "MetalSprocketsSceneGraph", package: "MetalSprocketsSceneGraph"),
                .product(name: "MetalSprocketsSceneGraphPhysics", package: "MetalSprocketsSceneGraph"),
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
            name: "scenegraph-demos",
            dependencies: [
                "MetalSprocketsSceneGraphDemos",
                .product(name: "DemoKit", package: "DemoKit"),
            ]
        ),
        .testTarget(
            name: "MetalSprocketsSceneGraphDemosTests",
            dependencies: [
                "MetalSprocketsSceneGraphDemos",
                .product(name: "MetalSprocketsSceneGraph", package: "MetalSprocketsSceneGraph"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "GoldenImage", package: "GoldenImage"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "DemoKit", package: "DemoKit"),
            ],
            resources: [.copy("Golden Images")]
        ),
    ]
)
