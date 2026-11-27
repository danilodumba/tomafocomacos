import Foundation

/// Versão do app lida do bundle — fonte única é o `project.yml`
/// (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// Nome visível do bundle — "Tomafoco", ou "Tomafoco Dev" no build de desenvolvimento.
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Tomafoco"
    }

    /// "Tomafoco 1.19 (20)" — menu da engrenagem e rodapé das configurações.
    static var display: String {
        "\(name) \(version) (\(build))"
    }

    /// "v1.19 · build 20" — rodapé do popover, onde o nome do app já é óbvio.
    static var short: String {
        "v\(version) · build \(build)"
    }
}
