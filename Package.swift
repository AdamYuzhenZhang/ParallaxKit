// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ParallaxKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ParallaxKit", targets: ["ParallaxKit"]),
        .library(name: "ParallaxARKit", targets: ["ParallaxARKit"]),
        .library(name: "ParallaxMotion", targets: ["ParallaxMotion"]),
        .library(name: "ParallaxRealityKit", targets: ["ParallaxRealityKit"]),
    ],
    targets: [
        .target(name: "ParallaxKit"),
        .target(name: "ParallaxARKit", dependencies: ["ParallaxKit"]),
        .target(name: "ParallaxMotion", dependencies: ["ParallaxKit"]),
        .target(name: "ParallaxRealityKit", dependencies: ["ParallaxKit"]),
        .testTarget(name: "ParallaxKitTests", dependencies: ["ParallaxKit"]),
    ]
)
