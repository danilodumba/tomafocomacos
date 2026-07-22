// swift-tools-version: 5.9
import PackageDescription

// TomafocoApplication — casos de uso e máquina de estados.
// Depende SOMENTE de TomafocoDomain. Nenhum import de AppKit/SwiftUI.
let package = Package(
    name: "TomafocoApplication",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TomafocoApplication", targets: ["TomafocoApplication"])
    ],
    dependencies: [
        .package(path: "../TomafocoDomain"),
        .package(path: "../TomafocoTestSupport")
    ],
    targets: [
        .target(
            name: "TomafocoApplication",
            dependencies: ["TomafocoDomain"]
        ),
        .testTarget(
            name: "TomafocoApplicationTests",
            dependencies: ["TomafocoApplication", "TomafocoDomain", "TomafocoTestSupport"]
        )
    ]
)
