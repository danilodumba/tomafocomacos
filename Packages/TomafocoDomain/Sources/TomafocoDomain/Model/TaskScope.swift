import Foundation

/// Quais tarefas entram numa tela: o quadro Kanban (FEAT-005, Configurações › Kanban) e o
/// seletor de tarefas do foco (RF-09.15, Configurações › Pomodoro). Era `KanbanTaskScope` até
/// 2026-10-27; virou compartilhado quando o seletor do timer ganhou o mesmo filtro.
///
/// Modo explícito em vez de "lista vazia = todas": apagar a última tag marcada não pode virar
/// "mostrar tudo" em silêncio — `tags([])` não inclui nada e a UI avisa.
public enum TaskScope: Equatable, Sendable {
    case all
    /// Tarefa entra se tiver **qualquer** uma das tags (OU), sem distinção de caixa.
    case tags([String])

    public func includes(_ task: FocusTask) -> Bool {
        switch self {
        case .all:
            return true
        case .tags(let selected):
            return task.tags.contains { tag in
                selected.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
        }
    }

    /// Escopo com herança da subtarefa (FEAT-003): a filha entra se ela OU o pai (procurado em
    /// `tasks`) está no escopo — senão criar uma subtarefa sem tag a faria sumir de onde o pai
    /// está. Mesma regra para quadro e seletor do foco.
    public func includes(_ task: FocusTask, in tasks: [FocusTask]) -> Bool {
        includes(task) || TaskTree.parent(of: task, in: tasks).map(includes) == true
    }

    /// Tags marcadas (vazio no modo `all`).
    public var selectedTags: [String] {
        if case .tags(let selected) = self { return selected }
        return []
    }

    // MARK: - Edição nas Configurações (quadro e seletor do foco usam as mesmas regras)

    public var isByTag: Bool {
        if case .tags = self { return true }
        return false
    }

    /// A tag está marcada (sem caixa). Sempre `false` no modo `all`.
    public func contains(_ tag: String) -> Bool {
        selectedTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// Tags que a UI oferece para marcar: as conhecidas + as já marcadas — uma tag do escopo
    /// pode não estar mais em tarefa nenhuma e não pode sumir da lista enquanto marcada.
    /// Normalizadas (sem duplicata por caixa) e ordenadas.
    public func selectableTags(knownTags: [String]) -> [String] {
        FocusTask.normalizeTags(knownTags + selectedTags)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Marca/desmarca uma tag. Sempre devolve o modo `tags` (marcar a partir de `all` entra
    /// no modo por tag só com ela), normalizado.
    public func settingTag(_ tag: String, selected: Bool) -> TaskScope {
        var tags = selectedTags
        tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        if selected { tags.append(tag) }
        return .tags(FocusTask.normalizeTags(tags))
    }

    /// "Todas" ↔ "Só com as tags". Ao entrar no modo por tag começa sem nenhuma marcada;
    /// `nil` quando já está no modo pedido (nada a gravar).
    public func switchingByTag(_ byTag: Bool) -> TaskScope? {
        guard byTag != isByTag else { return nil }
        return byTag ? .tags([]) : .all
    }

    /// Reflete a renomeação de uma tag (RF-09.5) na seleção. Sem efeito no modo `all`.
    public func renamingTag(from oldName: String, to newName: String) -> TaskScope {
        guard case .tags(let selected) = self else { return self }
        let renamed = selected.map { $0.caseInsensitiveCompare(oldName) == .orderedSame ? newName : $0 }
        return .tags(FocusTask.normalizeTags(renamed))
    }

    /// Tira uma tag apagada da seleção. Continua no modo `tags` mesmo se ficar vazia.
    public func removingTag(_ name: String) -> TaskScope {
        guard case .tags(let selected) = self else { return self }
        return .tags(selected.filter { $0.caseInsensitiveCompare(name) != .orderedSame })
    }
}

// Codable manual (`mode` + `tags`): JSON legível e estável, sem o formato aninhado que o
// Codable sintetizado gera para enum com valor associado. Modo desconhecido → `all`.
extension TaskScope: Codable {
    private enum CodingKeys: String, CodingKey { case mode, tags }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decodeIfPresent(String.self, forKey: .mode) {
        case "tags":
            self = .tags(FocusTask.normalizeTags(try c.decodeIfPresent([String].self, forKey: .tags) ?? []))
        default:
            self = .all
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all:
            try c.encode("all", forKey: .mode)
        case .tags(let selected):
            try c.encode("tags", forKey: .mode)
            try c.encode(selected, forKey: .tags)
        }
    }
}
