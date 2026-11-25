// swift-tools-version: 5.9
import PackageDescription

// TomafocoMarkdown — leitura do markdown do Documento da tarefa (FEAT-007, ADR-12).
// Converte o texto num modelo de render puro (`MarkdownBlock`) e faz as transformações de texto
// (checklist, barra de formatação). Sem SwiftUI/AppKit: as Views ficam no App/, que não tem
// target de teste — por isso a lógica mora aqui. Depende do Domain só para implementar o port
// `ChecklistResetting`; Domain e Application continuam sem o swift-markdown.
let package = Package(
    name: "TomafocoMarkdown",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TomafocoMarkdown", targets: ["TomafocoMarkdown"])
    ],
    dependencies: [
        .package(path: "../TomafocoDomain"),
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "TomafocoMarkdown",
            dependencies: [
                "TomafocoDomain",
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .testTarget(
            name: "TomafocoMarkdownTests",
            dependencies: ["TomafocoMarkdown", "TomafocoDomain"]
        )
    ]
)
