// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StrideKit",
    platforms: [.iOS(.v18), .watchOS(.v11)],
    products: [
        .library(name: "StrideKit", targets: ["StrideKit"]),
        .library(name: "StrideUI", targets: ["StrideUI"]),
    ],
    targets: [
        .target(name: "StrideKit"),
        .target(name: "StrideUI", dependencies: ["StrideKit"]),
        .testTarget(name: "StrideKitTests", dependencies: ["StrideKit"]),
    ]
)
