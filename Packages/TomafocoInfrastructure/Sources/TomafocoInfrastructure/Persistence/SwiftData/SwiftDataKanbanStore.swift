import Foundation
import os
import TomafocoDomain

/// `KanbanBoardRepository` sobre o banco (FEAT-006): os quadros (FEAT-008) são uma linha única
/// com a lista inteira, lida e gravada de uma vez (é pequena e sempre usada inteira). Fica num
/// `SingletonRecord` de propósito: nenhum `@Model` mudou, então não há versão nova do esquema.
@MainActor
public final class SwiftDataKanbanStore: KanbanBoardRepository {

    private let database: TomafocoDatabase
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "SwiftDataKanbanStore")

    public init(database: TomafocoDatabase) {
        self.database = database
    }

    /// Lista gravada; sem ela, migra o quadro único de antes da FEAT-008 (`kanbanBoard`) para uma
    /// lista de um quadro — grava a lista e apaga a linha antiga no mesmo commit (idempotente).
    /// Ilegível → `[]` (quadro padrão), como o `.bak` do `kanban.json`: as tarefas ficam com
    /// `laneIDs` órfãos e caem na primeira raia. A linha só é sobrescrita no próximo `saveBoards`.
    public func loadBoards() throws -> [KanbanBoard] {
        if let record = try database.singleton(SingletonKey.kanbanBoards) {
            do {
                return try PayloadCoding.decoder.decode([LenientBoard].self, from: record.payload)
                    .compactMap(\.board)
            } catch {
                Self.logger.error("Quadros ilegíveis no banco: \(String(describing: error), privacy: .public)")
                return []
            }
        }
        return try migrateLegacyBoard()
    }

    public func saveBoards(_ boards: [KanbanBoard]) throws {
        try database.setSingleton(SingletonKey.kanbanBoards, payload: PayloadCoding.encoder.encode(boards))
        try database.commit()
    }

    private func migrateLegacyBoard() throws -> [KanbanBoard] {
        guard let record = try database.singleton(SingletonKey.kanbanBoard) else { return [] }
        let board: KanbanBoard
        do {
            board = try PayloadCoding.decoder.decode(KanbanBoard.self, from: record.payload)
        } catch {
            Self.logger.error("Quadro antigo ilegível no banco: \(String(describing: error), privacy: .public)")
            return []
        }
        try database.perform {
            try database.setSingleton(SingletonKey.kanbanBoards, payload: PayloadCoding.encoder.encode([board]))
            try database.deleteSingleton(SingletonKey.kanbanBoard)
        }
        Self.logger.info("Quadro único migrado para a lista de quadros (FEAT-008)")
        return [board]
    }
}

/// Quadro que decodifica como `nil` em vez de lançar — um quadro quebrado não derruba os outros.
private struct LenientBoard: Decodable {
    let board: KanbanBoard?
    init(from decoder: Decoder) throws {
        board = try? KanbanBoard(from: decoder)
    }
}
