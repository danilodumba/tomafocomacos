import Foundation

/// Abas das Configurações. A selecionada fica em `UserDefaults` para que outras telas possam
/// abrir as Configurações já numa aba (o Kanban abre na aba Kanban — FEAT-005). Efeito
/// colateral aceito: as Configurações reabrem na última aba usada.
enum SettingsTab: String {
    case pomodoro, sites, apps, kanban

    static let storageKey = "settingsTab"

    static func select(_ tab: SettingsTab, defaults: UserDefaults = .standard) {
        defaults.set(tab.rawValue, forKey: storageKey)
    }
}
