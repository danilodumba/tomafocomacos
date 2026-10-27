import Foundation

/// Trava das ações que tiram uma tarefa do lugar (concluir/reabrir/apagar na lista, mover no
/// Kanban). Sem ela, cliques repetidos acertavam a tarefa que sobe para o lugar da que sumiu e
/// concluíam/apagavam tarefas sem querer (2026-10-01).
@MainActor
protocol TaskRowActionRunning: AnyObject {
    /// Tarefas com ação em andamento — a UI mostra loading no lugar dos controles.
    var busyTaskIDs: Set<UUID> { get set }
    var feedback: String? { get set }
}

extension TaskRowActionRunning {
    /// Trava global: enquanto uma ação roda (e por `taskActionCooldown` depois) nenhuma outra começa.
    var isMutatingTask: Bool { !busyTaskIDs.isEmpty }

    /// Executa a ação com loading na tarefa e trava global: clique enquanto outra ação roda —
    /// ou logo depois, dentro do cooldown — é ignorado.
    func runRowAction(
        _ taskID: UUID,
        _ action: @escaping () async throws -> Void,
        onError: @escaping (Error) -> String
    ) {
        guard !isMutatingTask else { return }
        feedback = nil
        busyTaskIDs.insert(taskID)
        Task {
            do {
                try await action()
            } catch {
                feedback = onError(error)
            }
            try? await Task.sleep(for: taskActionCooldown)
            busyTaskIDs.remove(taskID)
        }
    }
}

private let taskActionCooldown: Duration = .milliseconds(400)
