// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GLTFViewerSupport",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "GLTFViewerSupport", targets: ["GLTFViewerSupport"])
    ],
    dependencies: [
        .package(path: "../../../.."),
        .package(url: "https://github.com/schwa/MetalSprockets", branch: "main"),
        .package(url: "https://github.com/schwa/SwiftGLTF", branch: "main"),
        .package(url: "https://github.com/schwa/Interaction3D", .upToNextMinor(from: "0.2.2")),
        .package(url: "https://github.com/schwa/SwiftMesh", branch: "main"),
        .package(url: "https://github.com/schwa/GeometryLite3D", .upToNextMinor(from: "0.3.0"))
    ],
    targets: [
        .target(
            name: "GLTFViewerSupport",
            dependencies: [
                .product(name: "MetalSprocketsPBR", package: "SceneSprockets"),
                .product(name: "MetalSprocketsGLTF", package: "SceneSprockets"),
                .product(name: "MetalSprocketsGLTFBasisU", package: "SceneSprockets"),
                .product(name: "MetalSprocketsGLTFMeshopt", package: "SceneSprockets"),
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsUI", package: "MetalSprockets"),
                .product(name: "Interaction3D", package: "Interaction3D"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF"),
                .product(name: "SwiftMesh", package: "SwiftMesh"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D")
            ],
            // Built by `just gltfviewer-basic-shapes` (repository root).
            resources: [.copy("Resources/BasicShapes")]
        ),
        .testTarget(
            name: "GLTFViewerSupportTests",
            dependencies: [
                "GLTFViewerSupport",
                .product(name: "MetalSprockets", package: "MetalSprockets"),
                .product(name: "MetalSprocketsGLTF", package: "SceneSprockets"),
                .product(name: "MetalSprocketsGLTFMeshopt", package: "SceneSprockets"),
                .product(name: "MetalSprocketsPBR", package: "SceneSprockets"),
                .product(name: "SwiftGLTF", package: "SwiftGLTF")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
