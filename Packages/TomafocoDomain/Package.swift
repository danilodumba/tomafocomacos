// swift-tools-version: 5.9
import PackageDescription

// TomafocoDomain — núcleo puro do Tomafoco.
// REGRA: nenhuma dependência externa e nenhum import de AppKit/SwiftUI/UserNotifications.
// Se este pacote passar a importar algo do macOS, a fronteira da Clean Architecture foi violada.
let package = Package(
    name: "TomafocoDomain",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TomafocoDomain", targets: ["TomafocoDomain"])
    ],
    targets: [
        .target(name: "TomafocoDomain"),
        .testTarget(
            name: "TomafocoDomainTests",
            dependencies: ["TomafocoDomain"]
        )
    ]
)
