import Foundation

/// Resultado da seleção de aplicativos pelo usuário (T-20).
public struct ApplicationPickResult: Equatable, Sendable {
    /// Apps escolhidos cujo bundle ID pôde ser lido.
    public let apps: [BlockedApp]
    /// Nomes dos itens escolhidos sem bundle ID legível — a UI avisa o usuário em vez de ignorar em silêncio.
    public let unreadableNames: [String]

    public init(apps: [BlockedApp] = [], unreadableNames: [String] = []) {
        self.apps = apps
        self.unreadableNames = unreadableNames
    }

    /// `true` quando o usuário cancelou o seletor.
    public var isEmpty: Bool { apps.isEmpty && unreadableNames.isEmpty }
}

/// Seleção de aplicativos instalados (RF-03.2, T-20).
/// Implementado por `NSOpenPanelApplicationPicker` na Infrastructure; o Domain não conhece AppKit.
public protocol ApplicationPicking: Sendable {
    /// Apresenta o seletor de aplicativos. Devolve resultado vazio se o usuário cancelar.
    func pickApplications() async -> ApplicationPickResult

    /// Resolve URLs já conhecidas (drag-and-drop de `.app`) sem abrir painel.
    func applications(at urls: [URL]) -> ApplicationPickResult
}
