import SwiftUI
import TomafocoDomain
import TomafocoApplication

/// Quadros Kanban existentes (FEAT-008), para os menus que abrem um quadro: engrenagem do
/// popover e menu Janela. Um objeto só, no `AppContainer`, relido pelo `TaskChangeRelay` a cada
/// mudança — os menus observam direto (nested ObservableObject não propaga).
@MainActor
final class KanbanBoardList: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    @Published private(set) var items: [Item] = []

    private let useCase: ManageKanbanUseCase

    init(useCase: ManageKanbanUseCase) {
        self.useCase = useCase
        reload()
    }

    func reload() {
        let next = ((try? useCase.boards()) ?? []).map { Item(id: $0.id, name: $0.name) }
        if next != items { items = next }
    }
}

/// Último quadro usado (FEAT-008): ⌥⌘K e o "Kanban…" abrem nele. Gravado pela janela quando
/// aparece ou troca de quadro.
enum KanbanLastBoard {
    private static let key = "kanbanLastBoardID"

    static func load(defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    static func save(_ id: UUID, defaults: UserDefaults = .standard) {
        defaults.set(id.uuidString, forKey: key)
    }
}

/// Quadro que a aba Kanban das Configurações está configurando (FEAT-008). "Configurar
/// quadro…" na janela grava o quadro dela antes de abrir as Configurações; a notificação faz a
/// aba trocar de quadro mesmo se as Configurações já estiverem abertas.
enum KanbanSettingsBoard {
    static let didChange = Notification.Name("KanbanSettingsBoard.didChange")
    private static let key = "kanbanSettingsBoardID"

    static func load(defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    static func save(_ id: UUID, defaults: UserDefaults = .standard) {
        defaults.set(id.uuidString, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

extension OpenWindowAction {
    /// Abre a janela de um quadro (FEAT-008) e traz o app à frente — como app `.accessory` a
    /// janela abriria atrás sem o `activate`. Sem `boardID`, abre o último usado; o
    /// `WindowGroup(for:)` reaproveita a janela já aberta do mesmo quadro.
    func kanbanBoard(_ boardID: UUID? = nil, fallback: [KanbanBoardList.Item] = []) {
        if let id = boardID ?? KanbanLastBoard.load() ?? fallback.first?.id {
            callAsFunction(id: KanbanBoardWindow.sceneID, value: id)
        } else {
            // Nunca aberto e lista vazia (não deveria acontecer): janela sem valor, que escolhe
            // o primeiro quadro sozinha.
            callAsFunction(id: KanbanBoardWindow.sceneID)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Itens de menu dos quadros: um por quadro. Usado no menu da engrenagem e no menu Janela.
struct KanbanBoardMenuItems: View {
    @ObservedObject var boards: KanbanBoardList
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(boards.items) { item in
            Button(item.name) { openWindow.kanbanBoard(item.id) }
        }
    }
}
