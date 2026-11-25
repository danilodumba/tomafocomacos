import Foundation
import SwiftUI
import TomafocoApplication

/// Quais tarefas têm documento (FEAT-007) — o selo da lista e do Kanban. Fonte única,
/// compartilhada pelas janelas: a lista e o quadro observam ESTE objeto direto (nested
/// ObservableObject não propaga), então o selo aparece/some sem reler as tarefas.
@MainActor
final class TaskDocumentIndex: ObservableObject {
    @Published private(set) var taskIDs: Set<UUID> = []

    private let useCase: ManageTaskDocumentsUseCase

    init(useCase: ManageTaskDocumentsUseCase) {
        self.useCase = useCase
        reload()
    }

    func contains(_ taskID: UUID) -> Bool { taskIDs.contains(taskID) }

    /// Releitura barata: o store mantém o conjunto em cache (não lê os textos).
    func reload() {
        let ids = (try? useCase.taskIDsWithDocument()) ?? []
        if ids != taskIDs { taskIDs = ids }
    }
}

/// Abre a janela do documento de uma tarefa (FEAT-007). Ponto único para o formulário, a linha da
/// lista e o cartão do Kanban — o `WindowGroup(for:)` reaproveita a janela já aberta da mesma
/// tarefa. `activate` porque o app pode estar `.accessory` (só barra de menus).
struct OpenTaskDocumentAction {
    let openWindow: OpenWindowAction

    func callAsFunction(_ taskID: UUID) {
        openWindow(id: TaskDocumentWindow.sceneID, value: taskID)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension OpenWindowAction {
    var taskDocument: OpenTaskDocumentAction { OpenTaskDocumentAction(openWindow: self) }
}

/// Selo "tem documento" da linha/cartão.
struct DocumentBadge: View {
    var body: some View {
        Label("Doc", systemImage: "doc.text")
            .font(.system(size: 10))
            .foregroundStyle(Brand.cyan)
            .help("Tem documento — menu de contexto › Abrir documento")
    }
}
