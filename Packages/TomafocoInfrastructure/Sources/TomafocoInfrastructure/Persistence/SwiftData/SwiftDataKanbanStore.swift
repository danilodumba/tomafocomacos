import Foundation
import os
import TomafocoDomain

/// `KanbanBoardRepository` sobre o banco (FEAT-006): o quadro é uma linha única, lido e gravado
/// inteiro (é pequeno e sempre usado inteiro).
@MainActor
public final class SwiftDataKanbanStore: KanbanBoardRepository {

    private let database: TomafocoDatabase
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "SwiftDataKanbanStore")

    public init(database: TomafocoDatabase) {
        self.database = database
    }

    /// Ilegível → `nil` (quadro padrão), como o `.bak` do `kanban.json`: as tarefas ficam com
    /// `laneID` órfão e caem na primeira raia. A linha só é sobrescrita no próximo `saveBoard`.
    public func loadBoard() throws -> KanbanBoard? {
        guard let record = try database.singleton(SingletonKey.kanbanBoard) else { return nil }
        do {
            return try PayloadCoding.decoder.decode(KanbanBoard.self, from: record.payload)
        } catch {
            Self.logger.error("Quadro ilegível no banco: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    public func saveBoard(_ board: KanbanBoard) throws {
        try database.setSingleton(SingletonKey.kanbanBoard, payload: PayloadCoding.encoder.encode(board))
        try database.commit()
    }
}
