// swift-tools-version: 5.9
import PackageDescription

// TomafocoInfrastructure — adapters do macOS que implementam os ports do Domain.
// Depende de TomafocoDomain. Os adapters que usam AppKit são compilados condicionalmente
// (`#if canImport(AppKit)`) para que a lógica pura (ex.: BrowserScript) também construa em CI Linux.
let package = Package(
    name: "TomafocoInfrastructure",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TomafocoInfrastructure", targets: ["TomafocoInfrastructure"])
    ],
    dependencies: [
        .package(path: "../TomafocoDomain")
    ],
    targets: [
        .target(
            name: "TomafocoInfrastructure",
            dependencies: ["TomafocoDomain"]
        ),
        .testTarget(
            name: "TomafocoInfrastructureTests",
            dependencies: ["TomafocoInfrastructure", "TomafocoDomain"]
        )
    ]
)
