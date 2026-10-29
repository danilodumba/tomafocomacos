import Foundation
import os
import TomafocoDomain

/// Migração única dos arquivos JSON para o banco (FEAT-006, P5). Roda no lançamento, antes de
/// qualquer tela ler dados.
///
/// - **Idempotente:** o banco guarda `StoreMeta.importedFromJSONAt`; com ele presente, não faz nada.
/// - **Transacional:** tudo entra num único `save()`. Crash no meio → nada gravado → repete no
///   próximo lançamento.
/// - **Nunca apaga:** só depois do `save()` os JSON são renomeados para `*.json.migrated`
///   (diagnóstico e recuperação manual). JSON ilegível segue a regra antiga (`.bak`) e o resto
///   importa normalmente.
/// - **Banco recriado ou perdido:** sem `StoreMeta` e com `*.json.migrated` no disco, relê os
///   `.migrated` — dado antigo é melhor que começar vazio.
///
/// Os leitores são os `File*Store` de sempre, com o mesmo decode tolerante de versões antigas.
@MainActor
public final class JSONToSwiftDataImporter {

    public struct Report: Equatable, Sendable {
        public var skipped = false
        public var tasks = 0
        public var sessions = 0
        public var tags = 0
        public var importedBoard = false
        public var importedActiveSession = false
        /// Arquivos que não puderam ser lidos (preservados como `.bak`).
        public var unreadableFiles: [String] = []
    }

    /// Metadados do banco, numa linha única.
    struct StoreMeta: Codable, Equatable {
        var importedFromJSONAt: Date
        var importerVersion: Int
    }

    static let fileNames = ["tasks.json", "kanban.json", "history.json", "active-session.json"]
    private static let importerVersion = 1
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "JSONImporter")

    private let database: TomafocoDatabase
    private let tasks: SwiftDataTaskStore
    private let sessions: SwiftDataSessionStore
    private let tags: SwiftDataTagCatalog
    private let directory: URL
    private let legacyTags: UserDefaultsTagCatalog
    private let fileManager: FileManager
    private let now: () -> Date
    /// Só testes: o banco em memória é o próprio objeto sob teste.
    private let allowInMemory: Bool

    public init(database: TomafocoDatabase, tasks: SwiftDataTaskStore, sessions: SwiftDataSessionStore,
                tags: SwiftDataTagCatalog, directory: URL, legacyTags: UserDefaultsTagCatalog,
                fileManager: FileManager = .default, now: @escaping () -> Date,
                allowInMemory: Bool = false) {
        self.allowInMemory = allowInMemory
        self.database = database
        self.tasks = tasks
        self.sessions = sessions
        self.tags = tags
        self.directory = directory
        self.legacyTags = legacyTags
        self.fileManager = fileManager
        self.now = now
    }

    public enum ImportError: Error, Equatable {
        /// Banco em memória: importar renomearia os JSON sem ter gravado nada em disco.
        case databaseNotPersistent
    }

    @discardableResult
    public func run() throws -> Report {
        guard !database.isInMemory || allowInMemory else { throw ImportError.databaseNotPersistent }
        if try database.singleton(SingletonKey.storeMeta) != nil { return Report(skipped: true) }
        // Sem `StoreMeta` mas com `*.json.migrated`: o banco que recebeu a migração não existe
        // mais (recriado nesta execução — `wasReset` — ou perdido numa anterior que falhou ao
        // criar o novo). Decidido pelo disco, não por flag de processo: a única ação certa é
        // recuperar dos `.migrated`. Num banco já migrado nunca chega aqui (retorno acima).
        restoreMigratedFiles()

        var report = Report()
        // Tentativa anterior pode ter levado um arquivo ilegível a `.bak` e depois falhado no
        // `save()` (o rename não é transacional): sem isto a repetição "importaria" zero itens
        // sem avisar que o `.bak` existe.
        for name in Self.fileNames where !exists(name) && exists(name + ".bak") && !exists(name + ".migrated") {
            report.unreadableFiles.append(name)
        }
        try database.perform {
            let taskList = readTasks(&report)
            try tasks.saveTasks(taskList)
            report.tasks = taskList.count

            if let board = readBoard(&report) {
                try database.setSingleton(SingletonKey.kanbanBoard, payload: PayloadCoding.encoder.encode(board))
                report.importedBoard = true
            }

            let history = readHistory(&report)
            try sessions.insertHistory(history)
            report.sessions = history.count

            if let active = readActiveSession(&report) {
                try database.setSingleton(SingletonKey.activeSession, payload: PayloadCoding.encoder.encode(active))
                report.importedActiveSession = true
            }

            let catalog = legacyTags.loadTags()
            try tags.replace(with: catalog)
            report.tags = catalog.count

            let meta = StoreMeta(importedFromJSONAt: now(), importerVersion: Self.importerVersion)
            try database.setSingleton(SingletonKey.storeMeta, payload: PayloadCoding.encoder.encode(meta))
        }

        // Só depois do `save()`: antes disso, renomear deixaria uma falha sem volta.
        // O catálogo antigo fica no UserDefaults de propósito (como os `.migrated`): é a única
        // cópia para recuperar as tags órfãs se o banco precisar ser recriado (`wasReset`).
        markFilesAsMigrated()
        Self.logger.info("""
            Migração JSON → banco: \(report.tasks) tarefas, \(report.sessions) sessões, \(report.tags) tags, \
            quadro \(report.importedBoard), sessão ativa \(report.importedActiveSession), \
            ilegíveis \(report.unreadableFiles, privacy: .public)
            """)
        return report
    }

    // MARK: - Leitura

    private func readTasks(_ report: inout Report) -> [FocusTask] {
        let existed = exists("tasks.json")
        // `FileTaskStore` já trata ilegível: move para `.bak` e devolve vazio.
        let list = (try? FileTaskStore(directory: directory, fileManager: fileManager).loadTasks()) ?? []
        if existed && !exists("tasks.json") { report.unreadableFiles.append("tasks.json") }
        report.unreadableFiles = Array(Set(report.unreadableFiles)).sorted()
        return list
    }

    private func readBoard(_ report: inout Report) -> KanbanBoard? {
        let existed = exists("kanban.json")
        let board = try? FileKanbanStore(directory: directory, fileManager: fileManager).loadBoard()
        if existed && !exists("kanban.json") { report.unreadableFiles.append("kanban.json") }
        return board ?? nil
    }

    private func readHistory(_ report: inout Report) -> [SessionRecord] {
        do {
            return try FileSessionSnapshotStore(directory: directory, fileManager: fileManager).loadHistory()
        } catch {
            preserveUnreadable("history.json", &report)
            return []
        }
    }

    private func readActiveSession(_ report: inout Report) -> PomodoroSession? {
        do {
            return try FileSessionSnapshotStore(directory: directory, fileManager: fileManager).loadActive()
        } catch {
            preserveUnreadable("active-session.json", &report)
            return nil
        }
    }

    // MARK: - Arquivos

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    private func exists(_ name: String) -> Bool { fileManager.fileExists(atPath: url(name).path) }

    private func preserveUnreadable(_ name: String, _ report: inout Report) {
        let backup = url(name + ".bak")
        try? fileManager.removeItem(at: backup)
        try? fileManager.moveItem(at: url(name), to: backup)
        report.unreadableFiles.append(name)
    }

    private func markFilesAsMigrated() {
        for name in Self.fileNames where exists(name) {
            let target = url(name + ".migrated")
            try? fileManager.removeItem(at: target)
            do {
                try fileManager.moveItem(at: url(name), to: target)
            } catch {
                Self.logger.error("Não renomeou \(name, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Banco sem migração registrada: devolve os `*.json.migrated` ao nome original para os
    /// leitores (só onde o `.json` não existe). `markFilesAsMigrated` os renomeia de volta no fim.
    private func restoreMigratedFiles() {
        for name in Self.fileNames where !exists(name) && exists(name + ".migrated") {
            try? fileManager.copyItem(at: url(name + ".migrated"), to: url(name))
        }
    }
}
