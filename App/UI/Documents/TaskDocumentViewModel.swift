import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import TomafocoDomain
import TomafocoApplication
import TomafocoMarkdown

/// Janela do documento de UMA tarefa (FEAT-007). Uma instância por janela — o `WindowGroup(for:)`
/// garante uma janela por tarefa.
///
/// **Salva sozinho**: cada mudança agenda a gravação (`saveDelay`); fechar a janela ou sair do
/// app grava o que estiver pendente (`flush`). Não há rascunho/Cancelar — é documento, não
/// formulário. O parse para a visualização também é adiado (`parseDelay`) e só roda nos modos
/// que mostram a visualização.
@MainActor
final class TaskDocumentViewModel: ObservableObject {

    enum Mode: String, CaseIterable, Identifiable {
        case edit, split, preview
        var id: String { rawValue }
        var title: String {
            switch self {
            case .edit: "Editar"
            case .split: "Lado a lado"
            case .preview: "Visualizar"
            }
        }
        var showsEditor: Bool { self != .preview }
        var showsPreview: Bool { self != .edit }
    }

    enum Status: Equatable {
        case idle
        case pending
        case saved(Date)
        case failed(String)
    }

    let taskID: UUID
    @Published private(set) var taskTitle = ""
    @Published private(set) var parentTitle: String?
    /// A tarefa foi apagada com a janela aberta: o editor vira só leitura e nada é gravado.
    @Published private(set) var isTaskMissing = false
    /// O documento salvo não pôde ser lido ao abrir. Editor só leitura: tratar como "vazio"
    /// deixaria o usuário digitar por cima e o autosave substituiria o documento real.
    @Published private(set) var loadError: String?
    /// Nada é gravado: tarefa apagada ou documento que não abriu.
    var isReadOnly: Bool { isTaskMissing || loadError != nil }
    @Published var text: String {
        didSet {
            guard text != oldValue else { return }
            scheduleSave()
            scheduleParse()
        }
    }
    /// Lembrado entre janelas/aberturas (`UserDefaults`, chave `taskDocumentMode`).
    @Published var mode: Mode {
        didSet {
            defaults.set(mode.rawValue, forKey: Self.modeKey)
            if mode.showsPreview { parseNow() }
        }
    }
    @Published private(set) var blocks: [MarkdownBlock] = [] {
        didSet { blocksVersion &+= 1 }
    }
    /// Texto de onde saíram os `blocks` — as posições do checklist só valem para ele.
    private var parsedText = ""
    /// Identidade do parse para a `MarkdownView` equatable (não redesenha a cada tecla).
    private(set) var blocksVersion = 0
    @Published private(set) var status: Status = .idle

    /// Ponte para o `NSTextView` (barra de formatação e checklist com desfazer).
    let editor = MarkdownEditorController()

    private let documents: ManageTaskDocumentsUseCase
    private let tasks: ManageTasksUseCase
    private let defaults: UserDefaults
    /// O documento passou a existir ou deixou de existir — o selo das outras janelas muda.
    private let onPresenceChanged: () -> Void
    private var lastSavedText: String
    private var saveTask: Task<Void, Never>?
    private var parseTask: Task<Void, Never>?
    private var terminationObserver: AnyCancellable?
    private var resignKeyObserver: AnyCancellable?

    private static let modeKey = "taskDocumentMode"
    private static let saveDelay: UInt64 = 800_000_000
    private static let parseDelay: UInt64 = 150_000_000

    init(taskID: UUID, documents: ManageTaskDocumentsUseCase, tasks: ManageTasksUseCase,
         defaults: UserDefaults = .standard, onPresenceChanged: @escaping () -> Void) {
        self.taskID = taskID
        self.documents = documents
        self.tasks = tasks
        self.defaults = defaults
        self.onPresenceChanged = onPresenceChanged
        var saved: TaskDocument?
        do {
            saved = try documents.document(taskID: taskID)
        } catch {
            loadError = "Não foi possível abrir o documento (\(error.localizedDescription)). Feche e abra de novo."
        }
        text = saved?.markdown ?? ""
        lastSavedText = saved?.markdown ?? ""
        mode = defaults.string(forKey: Self.modeKey).flatMap(Mode.init(rawValue:)) ?? .split
        if let saved { status = .saved(saved.updatedAt) }
        refresh()
        if mode.showsPreview { parseNow() }
        // Sair do app (⌘Q) com gravação agendada: o `onDisappear` da janela não é garantido.
        // `assumeIsolated` é seguro AQUI: o AppKit posta `willTerminate` na main thread, de forma
        // síncrona — um `Task` não rodaria antes do processo acabar. (A regra "sem assumeIsolated"
        // vale para código chamado pelos ports, que não têm garantia de main.)
        terminationObserver = NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.flush() } }
        // Qualquer janela do app que perde o foco grava o pendente (barato: sem mudança é no-op).
        // Cobre clicar na lista/Kanban e concluir a diária antes do autosave — senão o clone
        // levaria o documento sem as últimas edições. Também postado na main pelo AppKit.
        resignKeyObserver = NotificationCenter.default
            .publisher(for: NSWindow.didResignKeyNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.flush() } }
    }

    // MARK: - Tarefa

    /// Relê título/pai/existência da tarefa — chamado pelo `TaskChangeRelay` quando as tarefas
    /// mudam em outra janela (renomeada, apagada).
    func refresh() {
        // Erro de leitura NÃO é "tarefa apagada": mantém o estado e tenta no próximo aviso.
        guard let all = try? tasks.allTasks() else { return }
        guard let task = all.first(where: { $0.id == taskID }) else {
            isTaskMissing = true
            saveTask?.cancel()
            return
        }
        let reappeared = isTaskMissing
        isTaskMissing = false
        if reappeared, text != lastSavedText { scheduleSave() }
        taskTitle = task.title
        parentTitle = TaskTree.parent(of: task, in: all)?.title
    }

    var windowTitle: String {
        taskTitle.isEmpty ? "Documento" : "Documento — \(taskTitle)"
    }

    // MARK: - Gravação

    /// Grava agora o que estiver pendente (fechar janela, sair do app, clique no checklist).
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    private func scheduleSave() {
        guard !isReadOnly else { return }
        status = .pending
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        guard !isReadOnly, text != lastSavedText else {
            if case .pending = status { status = lastSavedStatus }
            return
        }
        let snapshot = text
        do {
            let result = try documents.save(taskID: taskID, markdown: snapshot)
            switch result {
            case .saved(let document, _):
                lastSavedText = snapshot
                status = .saved(document.updatedAt)
            case .deleted, .unchanged:
                lastSavedText = snapshot
                status = .idle
            case .taskNotFound:
                isTaskMissing = true
                status = .failed("A tarefa foi apagada — o documento não foi salvo.")
            }
            if result.changesPresence { onPresenceChanged() }
        } catch DomainError.documentTooLarge(let maxBytes) {
            status = .failed("Documento passou do limite de \(maxBytes / 1_000_000) MB — reduza o texto para salvar.")
        } catch {
            status = .failed("Não foi possível salvar: \(error.localizedDescription)")
        }
    }

    private var lastSavedStatus: Status {
        if let updatedAt = (try? documents.document(taskID: taskID))?.updatedAt { return .saved(updatedAt) }
        return .idle
    }

    var statusText: String {
        switch status {
        case .idle: return text.isEmpty ? "Vazio" : ""
        case .pending: return "Editando…"
        case .saved(let date): return "Salvo às \(date.formatted(date: .omitted, time: .shortened))"
        case .failed(let message): return message
        }
    }

    var isStatusError: Bool {
        if case .failed = status { return true }
        return false
    }

    // MARK: - Visualização

    private func scheduleParse() {
        guard mode.showsPreview else { return }
        parseTask?.cancel()
        let snapshot = text
        // Parse FORA da main: medido ~50 ms para 120 KB (release) — na main, cada pausa na
        // digitação no modo lado a lado travaria o editor. O resultado só é aplicado se nenhuma
        // digitação nova cancelou esta passada.
        parseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.parseDelay)
            guard !Task.isCancelled else { return }
            let blocks = await Task.detached(priority: .userInitiated) {
                MarkdownRenderer.blocks(from: snapshot)
            }.value
            guard !Task.isCancelled, let self, self.text == snapshot else { return }
            self.parsedText = snapshot
            self.blocks = blocks
        }
    }

    private func parseNow() {
        parseTask?.cancel()
        parsedText = text
        blocks = MarkdownRenderer.blocks(from: text)
    }

    /// Clique no checklist da visualização: inverte o item no texto e grava na hora. Pelo
    /// `NSTextView` quando o editor está na tela (entra no desfazer); senão direto no texto.
    func toggleChecklist(at position: MarkdownSourcePosition) {
        guard !isReadOnly else { return }
        // Visualização atrasada em relação ao texto (parse ainda não chegou): a posição clicada
        // pode apontar para OUTRO item agora. Redesenha e ignora o clique.
        guard text == parsedText else {
            parseNow()
            return
        }
        guard let toggled = MarkdownChecklist.toggling(itemAt: position, in: text) else {
            parseNow() // texto mudou por baixo da visualização: só redesenha
            return
        }
        if !editor.replaceText(with: toggled) { text = toggled }
        parseNow()
        flush()
    }

    // MARK: - Copiar / exportar

    func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = Self.fileName(for: taskTitle)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            status = .failed("Não foi possível exportar: \(error.localizedDescription)")
        }
    }

    /// Nome de arquivo a partir do título: sem `/` e `:` (inválidos no Finder) e nunca vazio.
    static func fileName(for title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Documento" : cleaned) + ".md"
    }
}
