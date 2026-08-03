// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LinkRouterCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LinkRouterCore", targets: ["LinkRouterCore"])
    ],
    targets: [
        .target(name: "LinkRouterCore"),
        .testTarget(
            name: "LinkRouterCoreTests",
            dependencies: ["LinkRouterCore"]
        )
    ]
)
