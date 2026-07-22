// swift-tools-version: 5.9
import PackageDescription

// TomafocoTestSupport — fakes/spies compartilhados dos ports do Domain (LSP verificável, RNF-05).
// Depende apenas de TomafocoDomain.
let package = Package(
    name: "TomafocoTestSupport",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TomafocoTestSupport", targets: ["TomafocoTestSupport"])
    ],
    dependencies: [
        .package(path: "../TomafocoDomain")
    ],
    targets: [
        .target(
            name: "TomafocoTestSupport",
            dependencies: ["TomafocoDomain"]
        )
    ]
)
