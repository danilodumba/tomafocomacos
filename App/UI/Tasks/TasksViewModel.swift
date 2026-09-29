import Foundation
import SwiftUI
import TomafocoDomain
import TomafocoApplication

/// ViewModel da aba Tarefas (RF-09): CRUD manual + importação do Lembretes.
@MainActor
final class TasksViewModel: ObservableObject {

    /// Critério de ordenação da lista de ativas (item 5).
    enum SortOrder: String, CaseIterable, Identifiable {
        case createdAt, dueDate, dueTime, priority
        var id: String { rawValue }
        var label: String {
            switch self {
            case .createdAt: return "Criação"
            case .dueDate: return "Data"
            case .dueTime: return "Hora"
            case .priority: return "Prioridade"
            }
        }
    }

    @Published private(set) var activeTasks: [FocusTask] = []
    @Published private(set) var completedTasks: [FocusTask] = []
    /// Todas as tags conhecidas (uso + catálogo) — alimenta autocomplete, filtro e o gestor.
    @Published private(set) var knownTags: [String] = []
    @Published var newTitle = ""
    /// Tags da nova tarefa, digitadas separadas por vírgula.
    @Published var newTags = ""
    /// Tarefa aberta no formulário de edição (RF-09.6) + rascunho dos campos. Enquanto o sheet
    /// está aberto nada é gravado: só `saveEdit()` toca o repositório.
    @Published var editingTask: FocusTask?
    @Published var editTitle = ""
    /// Tags do rascunho, separadas por vírgula (mesmo formato do campo de criação).
    @Published var editTags = ""
    /// Vencimento é opcional: o toggle liga/desliga o `DatePicker` e desligado grava `nil`.
    @Published var editHasDueDate = false
    @Published var editDueDate = Date()
    @Published var editPriority: TaskPriority = .none
    /// Erro do formulário — separado de `feedback` porque o sheet cobre a lista.
    @Published var editFeedback: String?
    /// Histórico da tarefa aberta no formulário (FEAT-001), mais recente primeiro.
    /// Diferente dos outros campos do sheet, o histórico **não** é rascunho: acrescentar/apagar
    /// grava na hora (é log). "Cancelar" não desfaz entrada já adicionada.
    @Published private(set) var editingHistory: [TaskHistoryEntry] = []
    /// Texto da entrada de histórico em digitação.
    @Published var newHistoryText = ""

    // Ordenação + filtros da lista de ativas (itens 5 e 7).
    /// Persistida: a última ordenação escolhida volta na próxima abertura da janela/app.
    /// Filtros e busca NÃO são persistidos de propósito — recorte é da sessão; ordenação e
    /// exibição de concluídas são preferência.
    @Published var sortOrder: SortOrder = .createdAt {
        didSet { defaults.set(sortOrder.rawValue, forKey: Self.sortOrderKey) }
    }
    /// Persistida: mostrar/ocultar concluídas é preferência de exibição, como a ordenação.
    /// Chave ausente → `false` (concluídas escondidas, comportamento antigo).
    @Published var showsCompleted: Bool = false {
        didSet { defaults.set(showsCompleted, forKey: Self.showsCompletedKey) }
    }
    @Published var searchText = ""
    @Published var tagFilter: String?
    @Published var priorityFilter: TaskPriority?
    /// Abre a tela de gestão de tags (item 1).
    @Published var showsTagManager = false
    /// Mensagem de resultado/erro exibida sob a toolbar (some na próxima ação).
    @Published var feedback: String?
    /// Acesso ao Lembretes negado — a UI mostra o atalho para os Ajustes de Privacidade.
    @Published private(set) var accessDenied = false
    @Published private(set) var isImporting = false

    /// Sheet de escolha individual dos lembretes a importar (RF-09.3).
    @Published var showsImportSheet = false
    /// Lembretes não concluídos disponíveis para escolha (todas as listas).
    @Published private(set) var availableReminders: [ImportedReminder] = []
    /// Texto de busca por título dentro do sheet.
    @Published var reminderSearch = ""
    /// `reminderID`s com tarefa **ativa** — só essas linhas ficam marcadas/desabilitadas.
    @Published private(set) var importedReminderIDs: Set<String> = []
    /// `reminderID`s cuja tarefa já foi concluída aqui. Continuam importáveis (lembrete
    /// recorrente: concluir a ocorrência de hoje não pode barrar a de amanhã) — a linha só
    /// avisa que é uma reimportação.
    @Published private(set) var reimportableReminderIDs: Set<String> = []

    /// Lembretes filtrados pela busca por título (case-insensitive).
    var filteredReminders: [ImportedReminder] {
        let query = reminderSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return availableReminders }
        return availableReminders.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private let defaults: UserDefaults
    /// Chave da ordenação salva. Valor inválido/ausente cai em `.createdAt`.
    private static let sortOrderKey = "tasksSortOrder"
    private static let showsCompletedKey = "tasksShowsCompleted"

    private let useCase: ManageTasksUseCase
    /// Avisa o timer que a lista mudou (o seletor de tarefa precisa recarregar).
    private let onTasksChanged: () -> Void

    init(useCase: ManageTasksUseCase, defaults: UserDefaults = .standard,
         onTasksChanged: @escaping () -> Void) {
        self.useCase = useCase
        self.defaults = defaults
        self.onTasksChanged = onTasksChanged
        sortOrder = Self.storedSortOrder(in: defaults)
        showsCompleted = defaults.bool(forKey: Self.showsCompletedKey)
        reload()
    }

    func reload() {
        let all = (try? useCase.allTasks()) ?? []
        activeTasks = all.filter { !$0.isCompleted }
        completedTasks = all.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        importedReminderIDs = Set(activeTasks.compactMap(\.reminderID))
        reimportableReminderIDs = Set(completedTasks.compactMap(\.reminderID))
            .subtracting(importedReminderIDs)
        knownTags = (try? useCase.allTags()) ?? []
        onTasksChanged()
    }

    /// Lista para exibição: ativas buscadas/filtradas/ordenadas (itens 5 e 7) e, com
    /// `showsCompleted`, as concluídas em bloco no fim — na ordem de conclusão do `reload()`,
    /// não no `sortComparator` (vencimento/prioridade/atraso não dizem nada de tarefa finalizada).
    var displayedTasks: [FocusTask] {
        var result = applyFilters(activeTasks).sorted(by: sortComparator)
        if showsCompleted {
            result += applyFilters(completedTasks) // já vêm por completedAt desc do reload()
        }
        return result
    }

    /// Busca por título + filtros de tag/prioridade — valem para ativas e concluídas.
    private func applyFilters(_ tasks: [FocusTask]) -> [FocusTask] {
        var tasks = tasks
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            tasks = tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        if let tag = tagFilter {
            tasks = tasks.filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        }
        if let priority = priorityFilter {
            tasks = tasks.filter { TaskPriority(rawPriority: $0.priority) == priority }
        }
        return tasks
    }

    /// Ordenação salva; `rawValue` desconhecido (versão antiga/futura) volta ao padrão.
    private static func storedSortOrder(in defaults: UserDefaults) -> SortOrder {
        guard let raw = defaults.string(forKey: sortOrderKey) else { return .createdAt }
        return SortOrder(rawValue: raw) ?? .createdAt
    }

    /// Comparador conforme `sortOrder`. Empates caem para o mais recente primeiro.
    private func sortComparator(_ a: FocusTask, _ b: FocusTask) -> Bool {
        switch sortOrder {
        case .createdAt:
            return a.createdAt > b.createdAt
        case .dueDate:
            return byOptionalDate(a.dueDate, b.dueDate, a, b)
        case .dueTime:
            return byOptionalDate(timeOfDay(a.dueDate), timeOfDay(b.dueDate), a, b)
        case .priority:
            // Prioridade menor = mais urgente; sem prioridade vai para o fim.
            let pa = a.priority ?? Int.max
            let pb = b.priority ?? Int.max
            if pa != pb { return pa < pb }
            return a.createdAt > b.createdAt
        }
    }

    /// Ordena por data opcional (nil por último); empate → mais recente primeiro.
    private func byOptionalDate(_ da: Date?, _ db: Date?, _ a: FocusTask, _ b: FocusTask) -> Bool {
        switch (da, db) {
        case let (x?, y?): return x != y ? x < y : a.createdAt > b.createdAt
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return a.createdAt > b.createdAt
        }
    }

    /// Segundos desde a meia-noite de uma data — base para ordenar por "hora" do vencimento.
    private func timeOfDay(_ date: Date?) -> Date? {
        guard let date else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let seconds = (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
        return Date(timeIntervalSinceReferenceDate: TimeInterval(seconds))
    }

    /// Tarefa vencida: tem data de vencimento no passado e não está concluída (item 6).
    func isOverdue(_ task: FocusTask) -> Bool {
        guard !task.isCompleted, let due = task.dueDate else { return false }
        return due < Date()
    }

    func addTask() {
        feedback = nil
        do {
            try useCase.addTask(title: newTitle, tags: Self.parseTags(newTags))
            newTitle = ""
            newTags = ""
            reload()
        } catch DomainError.emptyTaskTitle {
            feedback = "Informe um título para a tarefa."
        } catch DomainError.duplicateEntry(let title) {
            feedback = "Já existe uma tarefa ativa chamada \"\(title)\"."
        } catch {
            feedback = "Não foi possível salvar: \(error.localizedDescription)"
        }
    }

    func setCompleted(_ task: FocusTask, _ completed: Bool) {
        feedback = nil
        Task {
            do {
                let outcome = completed
                    ? try await useCase.completeTask(id: task.id)
                    : try await useCase.reopenTask(id: task.id)
                reload()
                // Falha de espelhamento não desfaz a mudança local, mas precisa aparecer:
                // sem aviso, o usuário só descobre abrindo o Lembretes.
                if outcome == .failed {
                    feedback = "Tarefa atualizada aqui, mas não foi possível refletir no Lembretes"
                        + " (lembrete apagado ou acesso negado em Ajustes › Privacidade › Lembretes)."
                }
            } catch {
                feedback = "Não foi possível atualizar: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Edição completa (RF-09.6)

    /// Abre o formulário com os valores atuais da tarefa.
    func beginEditing(_ task: FocusTask) {
        feedback = nil
        editFeedback = nil
        editTitle = task.title
        editTags = task.tags.joined(separator: ", ")
        editHasDueDate = task.dueDate != nil
        editDueDate = task.dueDate ?? Self.defaultDueDate()
        editPriority = TaskPriority(rawPriority: task.priority)
        editingHistory = Self.sortedHistory(task)
        newHistoryText = ""
        editingTask = task
    }

    func cancelEditing() {
        editingTask = nil
        editFeedback = nil
        newHistoryText = ""
    }

    /// Grava o rascunho. Erro de validação mantém o sheet aberto com a mensagem.
    func saveEdit() {
        guard let task = editingTask else { return }
        editFeedback = nil
        do {
            try useCase.editTask(
                id: task.id,
                title: editTitle,
                tags: Self.parseTags(editTags),
                dueDate: editHasDueDate ? editDueDate : nil,
                priority: editPriority
            )
            // Texto digitado no histórico sem clicar "Adicionar" entra junto ao salvar — não
            // descartar em silêncio o que o usuário escreveu.
            if !newHistoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try useCase.addHistoryEntry(taskID: task.id, text: newHistoryText)
            }
            editingTask = nil
            newHistoryText = ""
            reload()
        } catch DomainError.emptyTaskTitle {
            editFeedback = "Informe um título para a tarefa."
        } catch DomainError.duplicateEntry(let title) {
            editFeedback = "Já existe uma tarefa ativa chamada \"\(title)\"."
        } catch {
            editFeedback = "Não foi possível salvar: \(error.localizedDescription)"
        }
    }

    // MARK: - Histórico da tarefa (FEAT-001)

    /// Acrescenta a entrada digitada. **Grava na hora**, fora do rascunho do formulário —
    /// histórico é log, e o botão "Cancelar" não desfaz o que já foi registrado.
    func addHistoryEntry() {
        guard let task = editingTask else { return }
        editFeedback = nil
        do {
            guard let updated = try useCase.addHistoryEntry(taskID: task.id, text: newHistoryText) else { return }
            editingHistory = Self.sortedHistory(updated)
            newHistoryText = ""
            reload()
        } catch DomainError.emptyHistoryEntry {
            editFeedback = "Escreva algo antes de adicionar ao histórico."
        } catch {
            editFeedback = "Não foi possível salvar a entrada: \(error.localizedDescription)"
        }
    }

    /// Apaga UMA entrada (não há edição — é log).
    func deleteHistoryEntry(_ entry: TaskHistoryEntry) {
        guard let task = editingTask else { return }
        editFeedback = nil
        do {
            guard let updated = try useCase.deleteHistoryEntry(taskID: task.id, entryID: entry.id) else { return }
            editingHistory = Self.sortedHistory(updated)
            reload()
        } catch {
            editFeedback = "Não foi possível apagar a entrada: \(error.localizedDescription)"
        }
    }

    /// Ordem de exibição: mais recente primeiro (o Domain guarda na ordem de inclusão).
    private static func sortedHistory(_ task: FocusTask) -> [TaskHistoryEntry] {
        task.history.sorted { $0.createdAt > $1.createdAt }
    }

    /// Sugestão ao ligar o vencimento numa tarefa que não tinha: hoje na próxima hora cheia
    /// (data crua com segundos do "agora" viraria um horário estranho no picker).
    private static func defaultDueDate() -> Date {
        let calendar = Calendar.current
        let next = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        var parts = calendar.dateComponents([.year, .month, .day, .hour], from: next)
        parts.minute = 0
        parts.second = 0
        return calendar.date(from: parts) ?? next
    }

    /// Divide o texto do campo em tags cruas (por vírgula) — a normalização final é do Domain.
    static func parseTags(_ text: String) -> [String] {
        text.split(separator: ",").map(String.init)
    }

    // MARK: - Prioridade (item 4)

    func setPriority(_ task: FocusTask, _ priority: TaskPriority) {
        feedback = nil
        do {
            try useCase.setPriority(id: task.id, priority: priority)
            reload()
        } catch {
            feedback = "Não foi possível definir a prioridade: \(error.localizedDescription)"
        }
    }

    // MARK: - Cadastro de tags (item 1)

    /// Quantas tarefas usam cada tag — mostrado no gestor de tags.
    func taskCount(forTag tag: String) -> Int {
        (activeTasks + completedTasks).filter {
            $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }.count
    }

    func createTag(_ name: String) {
        feedback = nil
        do { try useCase.createTag(name); reload() }
        catch { feedback = "Não foi possível criar a tag: \(error.localizedDescription)" }
    }

    func renameTag(from oldName: String, to newName: String) {
        feedback = nil
        do {
            try useCase.renameTag(from: oldName, to: newName)
            if tagFilter?.caseInsensitiveCompare(oldName) == .orderedSame { tagFilter = newName }
            reload()
        } catch {
            feedback = "Não foi possível renomear a tag: \(error.localizedDescription)"
        }
    }

    func deleteTag(_ name: String) {
        feedback = nil
        do {
            try useCase.deleteTag(name)
            if tagFilter?.caseInsensitiveCompare(name) == .orderedSame { tagFilter = nil }
            reload()
        } catch {
            feedback = "Não foi possível apagar a tag: \(error.localizedDescription)"
        }
    }

    func delete(_ task: FocusTask) {
        feedback = nil
        do {
            try useCase.deleteTask(id: task.id)
            reload()
        } catch {
            feedback = "Não foi possível apagar: \(error.localizedDescription)"
        }
    }

    /// Abre o picker: carrega os lembretes não concluídos (todas as listas) e mostra o sheet.
    func prepareImport() async {
        feedback = nil
        accessDenied = false
        reminderSearch = ""
        isImporting = true
        defer { isImporting = false }

        switch await useCase.loadImportableReminders() {
        case .failure(.accessDenied):
            accessDenied = true
            feedback = "Acesso ao Lembretes negado."
        case .failure(.fetchFailed):
            feedback = "Não foi possível ler o Lembretes. Tente novamente."
        case .success(let reminders):
            availableReminders = reminders.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            reload()  // atualiza importedReminderIDs para marcar os já importados
            showsImportSheet = true
        }
    }

    /// Importa um único lembrete escolhido no picker. Dedup segue no use case.
    func importOne(_ reminder: ImportedReminder) async {
        feedback = nil
        let result = await useCase.importReminder(reminder)
        switch result.failure {
        case .accessDenied:
            accessDenied = true
            feedback = "Acesso ao Lembretes negado."
        case .fetchFailed:
            feedback = "Não foi possível salvar. Tente novamente."
        case nil:
            reload()
            if let title = result.importedTitles.first {
                feedback = "Importada: \(title)"
            } else if result.skippedCount > 0 {
                feedback = "\"\(reminder.title)\" já existia."
            }
        }
    }

    /// Ajustes do Sistema › Privacidade e Segurança › Lembretes.
    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
        NSWorkspace.shared.open(url)
    }
}
