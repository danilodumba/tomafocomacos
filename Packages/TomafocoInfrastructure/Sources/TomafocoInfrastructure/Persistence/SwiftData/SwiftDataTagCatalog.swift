import Foundation
import os
import SwiftData
import TomafocoDomain

/// `TagCatalog` sobre o banco (FEAT-006). O port é best-effort (não lança): falha de banco é
/// logada e a leitura cai em lista vazia — as tags em uso pelas tarefas continuam sendo a fonte
/// primária (`ManageTasksUseCase.allTags`).
@MainActor
public final class SwiftDataTagCatalog: TagCatalog {

    private let database: TomafocoDatabase
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "SwiftDataTagCatalog")

    public init(database: TomafocoDatabase) {
        self.database = database
    }

    public func loadTags() -> [String] {
        do {
            return try database.context
                .fetch(FetchDescriptor<TagRecord>(sortBy: [SortDescriptor(\.position)]))
                .map(\.name)
        } catch {
            Self.logger.error("Catálogo de tags não leu: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    public func saveTags(_ tags: [String]) {
        do {
            try replace(with: tags)
            try database.commit()
        } catch {
            Self.logger.error("Catálogo de tags não gravou: \(String(describing: error), privacy: .public)")
        }
    }

    /// Deixa o catálogo igual a `tags` (ordem inclusive) sem gravar — o importador usa dentro da
    /// transação dele. Nome é único no banco: duplicata na entrada fica só na 1ª posição.
    func replace(with tags: [String]) throws {
        let existing = try database.context.fetch(FetchDescriptor<TagRecord>())
        var byName = Dictionary(existing.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        for (position, name) in tags.enumerated() where seen.insert(name).inserted {
            if let record = byName.removeValue(forKey: name) {
                if record.position != position { record.position = position }
            } else {
                database.context.insert(TagRecord(name: name, position: position))
            }
        }
        byName.values.forEach { database.context.delete($0) }
    }
}
