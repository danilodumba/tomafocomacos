import Foundation
import SwiftUI
import TomafocoDomain
import TomafocoApplication

/// ViewModel da aba Tarefas (RF-09): CRUD manual + importação do Lembretes.
@MainActor
final class TasksViewModel: ObservableObject {

    @Published private(set) var activeTasks: [FocusTask] = []
    @Published private(set) var completedTasks: [FocusTask] = []
    @Published var newTitle = ""
    /// Tags da nova tarefa, digitadas separadas por vírgula.
    @Published var newTags = ""
    /// Tarefa em edição de tags (popover) + texto do campo.
    @Published var editingTagsTask: FocusTask?
    @Published var editingTagsText = ""
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
    /// `reminderID`s já presentes na lista de tarefas — linhas ficam marcadas/desabilitadas.
    @Published private(set) var importedReminderIDs: Set<String> = []

    /// Lembretes filtrados pela busca por título (case-insensitive).
    var filteredReminders: [ImportedReminder] {
        let query = reminderSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return availableReminders }
        return availableReminders.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private let defaults: UserDefaults

    private let useCase: ManageTasksUseCase
    /// Avisa o timer que a lista mudou (o seletor de tarefa precisa recarregar).
    private let onTasksChanged: () -> Void

    init(useCase: ManageTasksUseCase, defaults: UserDefaults = .standard,
         onTasksChanged: @escaping () -> Void) {
        self.useCase = useCase
        self.defaults = defaults
        self.onTasksChanged = onTasksChanged
        reload()
    }

    func reload() {
        let all = (try? useCase.allTasks()) ?? []
        activeTasks = all.filter { !$0.isCompleted }.sorted { $0.createdAt > $1.createdAt }
        completedTasks = all.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        importedReminderIDs = Set(all.compactMap(\.reminderID))
        onTasksChanged()
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
                if completed { try await useCase.completeTask(id: task.id) }
                else { try await useCase.reopenTask(id: task.id) }
                reload()
            } catch {
                feedback = "Não foi possível atualizar: \(error.localizedDescription)"
            }
        }
    }

    /// Abre o popover de edição de tags com as tags atuais pré-preenchidas.
    func beginEditingTags(_ task: FocusTask) {
        feedback = nil
        editingTagsText = task.tags.joined(separator: ", ")
        editingTagsTask = task
    }

    func saveEditingTags() {
        guard let task = editingTagsTask else { return }
        editingTagsTask = nil
        do {
            try useCase.setTags(id: task.id, tags: Self.parseTags(editingTagsText))
            reload()
        } catch {
            feedback = "Não foi possível salvar as tags: \(error.localizedDescription)"
        }
    }

    /// Divide o texto do campo em tags cruas (por vírgula) — a normalização final é do Domain.
    static func parseTags(_ text: String) -> [String] {
        text.split(separator: ",").map(String.init)
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
