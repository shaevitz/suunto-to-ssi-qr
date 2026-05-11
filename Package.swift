// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SuuntoToSSIQR",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SuuntoToSSIQRCore", targets: ["SuuntoToSSIQRCore"]),
        .executable(name: "SuuntoToSSIQRApp", targets: ["SuuntoToSSIQRApp"]),
    ],
    targets: [
        .target(name: "SuuntoToSSIQRCore"),
        .executableTarget(
            name: "SuuntoToSSIQRApp",
            dependencies: ["SuuntoToSSIQRCore"]
        ),
        .testTarget(
            name: "SuuntoToSSIQRCoreTests",
            dependencies: ["SuuntoToSSIQRCore"],
            resources: [
                .copy("Fixtures/synthetic-dive.fit")
            ]
        ),
    ]
)
