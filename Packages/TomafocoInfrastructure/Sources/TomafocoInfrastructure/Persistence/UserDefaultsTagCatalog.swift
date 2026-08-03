import Foundation
import TomafocoDomain

/// `TagCatalog` sobre `UserDefaults` (RF-09.5). Guarda as tags cadastradas — inclusive as que
/// ainda não estão em nenhuma tarefa — como um simples array de strings. Best-effort: sem lançar.
public final class UserDefaultsTagCatalog: TagCatalog {

    private enum Key {
        static let tags = "tomafoco.tagCatalog"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadTags() -> [String] {
        defaults.stringArray(forKey: Key.tags) ?? []
    }

    public func saveTags(_ tags: [String]) {
        defaults.set(tags, forKey: Key.tags)
    }
}
