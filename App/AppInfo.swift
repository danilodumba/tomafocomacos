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

    /// "Tomafoco 1.0 (1)" — para menu e rodapé das configurações.
    static var display: String {
        "Tomafoco \(version) (\(build))"
    }
}
