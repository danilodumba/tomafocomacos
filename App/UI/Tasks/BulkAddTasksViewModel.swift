import Foundation
import TomafocoDomain
import TomafocoApplication

/// Criação de tarefas em lote (RF-09.8): passo 1 cola texto (1 linha = 1 tarefa), passo 2
/// ajusta título/prioridade/tags/vencimento num grid e cria tudo de uma vez (atômico).
/// `Identifiable` para ser apresentado via `.sheet(item:)` pelo `TasksViewModel`.
@MainActor
final class BulkAddTasksViewModel: ObservableObject, Identifiable {

    enum Step { case text, grid }

    /// Uma linha do grid — rascunho editável de uma tarefa.
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var priority: TaskPriority = .none
        /// Tags separadas por vírgula (mesmo formato dos outros campos de tag).
        var tags = ""
        var hasDueDate = false
        var dueDate: Date
    }

    @Published var step: Step = .text
    @Published var rawText = ""
    @Published var rows: [Row] = [] {
        didSet { if rows != oldValue { revalidate() } }
    }
    /// Problema de cada linha (mensagem pronta), por id da linha.
    @Published private(set) var issues: [Row.ID: String] = [:]
    /// Erro geral (falha de disco) — o de validação vai por linha em `issues`.
    @Published private(set) var feedback: String?

    let knownTags: [String]
    private let useCase: ManageTasksUseCase
    /// Chamado após criar: o `TasksViewModel` recarrega a lista e fecha o sheet.
    private let onCreated: (Int) -> Void
    private let onCancel: () -> Void

    init(useCase: ManageTasksUseCase, knownTags: [String],
         onCreated: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.useCase = useCase
        self.knownTags = knownTags
        self.onCreated = onCreated
        self.onCancel = onCancel
    }

    /// Quantas tarefas o texto atual gera (contador ao vivo do passo 1).
    var lineCount: Int { BulkTaskText.parseTitles(rawText).count }

    var canCreate: Bool { !rows.isEmpty && issues.isEmpty }

    /// Passo 1 → 2. Linha cujo título já estava no grid mantém prioridade/tags/vencimento
    /// ajustados — voltar para corrigir o texto não pode jogar fora o que foi editado.
    func goToGrid() {
        var previous = rows
        let dueDate = TasksViewModel.defaultDueDate()
        rows = BulkTaskText.parseTitles(rawText).map { title in
            if let idx = previous.firstIndex(where: { $0.title == title }) {
                return previous.remove(at: idx)
            }
            return Row(title: title, dueDate: dueDate)
        }
        feedback = nil
        revalidate()
        step = .grid
    }

    /// Passo 2 → 1. O texto é refeito com os títulos do grid (edições/remoções valem).
    func goBack() {
        rawText = rows.map(\.title).joined(separator: "\n")
        feedback = nil
        step = .text
    }

    func removeRow(_ id: Row.ID) {
        rows.removeAll { $0.id == id }
    }

    func cancel() { onCancel() }

    func create() {
        feedback = nil
        do {
            let created = try useCase.addTasks(drafts)
            onCreated(created.count)
        } catch is DomainError {
            revalidate() // estado mudou por fora (outra janela) — as linhas mostram o motivo
        } catch {
            feedback = "Não foi possível salvar: \(error.localizedDescription)"
        }
    }

    private var drafts: [NewTaskDraft] {
        rows.map {
            NewTaskDraft(
                title: $0.title,
                tags: TasksViewModel.parseTags($0.tags),
                dueDate: $0.hasDueDate ? $0.dueDate : nil,
                priority: $0.priority
            )
        }
    }

    private func revalidate() {
        let byIndex: [Int: DomainError]
        do {
            byIndex = try useCase.validateNewTasks(drafts)
        } catch {
            feedback = "Não foi possível ler as tarefas: \(error.localizedDescription)"
            return
        }
        var result: [Row.ID: String] = [:]
        for (index, error) in byIndex where rows.indices.contains(index) {
            result[rows[index].id] = Self.message(for: error)
        }
        if result != issues { issues = result }
    }

    private static func message(for error: DomainError) -> String {
        switch error {
        case .emptyTaskTitle: return "Informe um título."
        case .duplicateEntry: return "Título repetido (no lote ou numa tarefa ativa)."
        default: return "Linha inválida."
        }
    }
}
