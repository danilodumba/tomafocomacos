import Foundation
import TomafocoDomain

/// `KanbanBoardRepository` em JSON (`kanban.json`) ao lado do `tasks.json` (FEAT-005) — mesmo
/// padrão do `FileTaskStore`: escrita atômica e arquivo ilegível preservado como `.bak`.
public final class FileKanbanStore: KanbanBoardRepository {

    private let boardURL: URL
    private let backupURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = directory ?? Self.defaultDirectory(fileManager)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.boardURL = base.appendingPathComponent("kanban.json")
        self.backupURL = base.appendingPathComponent("kanban.json.bak")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    public func loadBoard() throws -> KanbanBoard? {
        guard fileManager.fileExists(atPath: boardURL.path) else { return nil }
        do {
            return try decoder.decode(KanbanBoard.self, from: Data(contentsOf: boardURL))
        } catch {
            // Ilegível: preserva para diagnóstico e recomeça com o quadro padrão. As tarefas
            // ficam com `laneID` órfão e caem na primeira raia (`KanbanBoard.lane(for:)`).
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.moveItem(at: boardURL, to: backupURL)
            return nil
        }
    }

    public func saveBoard(_ board: KanbanBoard) throws {
        try encoder.encode(board).write(to: boardURL, options: .atomic)
    }

    private static func defaultDirectory(_ fm: FileManager) -> URL {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return support.appendingPathComponent("Tomafoco", isDirectory: true)
    }
}
