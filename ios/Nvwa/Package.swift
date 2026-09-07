// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Nvwa",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "Nvwa", targets: ["Nvwa"])
    ],
    targets: [
        .target(
            name: "Nvwa",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NvwaTests",
            dependencies: ["Nvwa"]
        )
    ]
)
