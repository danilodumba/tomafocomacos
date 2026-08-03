import Foundation
import TomafocoDomain

/// Catálogo de tags em memória — padrão do `ManageTasksUseCase` quando nenhum store persistente
/// é injetado (usado nos testes e como fallback). Some ao encerrar o processo; o app real injeta
/// a implementação de `UserDefaults` (Infrastructure).
public final class EphemeralTagCatalog: TagCatalog {
    private var tags: [String]

    public init(tags: [String] = []) {
        self.tags = tags
    }

    public func loadTags() -> [String] { tags }
    public func saveTags(_ tags: [String]) { self.tags = tags }
}
