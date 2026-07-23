import Foundation
import TomafocoDomain

/// `TaskRepository` que persiste as tarefas como JSON em Application Support, com escrita
/// atômica — mesmo padrão do `FileSessionSnapshotStore` (RNF-02).
public final class FileTaskStore: TaskRepository {

    private let tasksURL: URL
    /// Destino do arquivo corrompido — preservado em vez de apagado, como o histórico.
    private let backupURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = directory ?? Self.defaultDirectory(fileManager)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.tasksURL = base.appendingPathComponent("tasks.json")
        self.backupURL = base.appendingPathComponent("tasks.json.bak")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadTasks() throws -> [FocusTask] {
        guard fileManager.fileExists(atPath: tasksURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: tasksURL)
            return try decoder.decode([FocusTask].self, from: data)
        } catch {
            // Arquivo ilegível não pode travar o app nem ser sobrescrito em silêncio:
            // preserva como .bak para diagnóstico e recomeça vazio.
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.moveItem(at: tasksURL, to: backupURL)
            return []
        }
    }

    public func saveTasks(_ tasks: [FocusTask]) throws {
        let data = try encoder.encode(tasks)
        try data.write(to: tasksURL, options: .atomic)
    }

    private static func defaultDirectory(_ fm: FileManager) -> URL {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return support.appendingPathComponent("Tomafoco", isDirectory: true)
    }
}
