import Foundation
import TomafocoInfrastructure

/// Produção × desenvolvimento (2026-11-27). O build Debug é o "Tomafoco Dev": bundle ID
/// `com.dsdumba.tomafoco.dev` e pasta de dados `Tomafoco-Dev` (`TomafocoDataFolder` no
/// Info.plist, definido por configuração no `project.yml`). Assim o desenvolvimento roda ao lado
/// do app instalado sem abrir o banco real, sem mexer nas preferências nem na senha dele.
struct AppEnvironment {
    let bundleIdentifier: String
    let dataFolder: String

    static let current = AppEnvironment(bundle: .main)

    init(bundle: Bundle) {
        bundleIdentifier = bundle.bundleIdentifier ?? "com.dsdumba.tomafoco"
        let folder = bundle.object(forInfoDictionaryKey: "TomafocoDataFolder") as? String
        dataFolder = (folder?.isEmpty == false) ? folder! : "Tomafoco"
    }

    var isDevelopment: Bool { bundleIdentifier.hasSuffix(".dev") }

    @MainActor var databaseURL: URL { TomafocoDatabase.defaultURL(folder: dataFolder) }

    /// Produção mantém o item de sempre (`com.dsdumba.tomafoco.unlock`).
    var keychainService: String { "\(bundleIdentifier).unlock" }
}
