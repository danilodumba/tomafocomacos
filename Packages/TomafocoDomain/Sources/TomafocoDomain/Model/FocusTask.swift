import Foundation

/// Tarefa em que o usuário foca (RF-09). Chama `FocusTask` — não `Task` — para não colidir
/// com `Swift.Task` (Concurrency), que é importado em praticamente todo arquivo.
public struct FocusTask: Equatable, Codable, Sendable, Identifiable {
    public enum Source: String, Equatable, Codable, Sendable {
        case manual
        case reminders  // importada do app Lembretes (EventKit)
    }

    public let id: UUID
    public var title: String
    public let source: Source
    /// `calendarItemIdentifier` do lembrete de origem — chave de dedup na reimportação.
    public let reminderID: String?
    public let createdAt: Date
    public var completedAt: Date?
    /// Rótulos livres do usuário (ex.: "trabalho", "estudo"). Sempre normalizados
    /// (`normalizeTags`): sem vazios, sem duplicata por caixa, ordem de entrada preservada.
    public var tags: [String]
    /// Nota livre da tarefa (RF-09.13): digitada no formulário ou vinda do lembrete de origem
    /// (`EKReminder.notes`). `nil` = sem nota (o use case normaliza vazio para `nil`).
    public var notes: String?
    /// Data de vencimento do lembrete de origem (`EKReminder.dueDateComponents`).
    public var dueDate: Date?
    /// Prioridade do lembrete (`EKReminder.priority`, 1–9; menor = mais urgente).
    /// `nil` = sem prioridade (o EventKit usa 0 para "nenhuma" — normalizado para `nil` na importação).
    public var priority: Int?
    /// Link da tarefa (RF-09.13): digitado no formulário ou anexado ao lembrete de origem
    /// (`EKReminder.url`). NÃO é deep-link para o app Lembretes (EventKit não expõe isso).
    /// Sempre com esquema (`normalizeLink`), então `URL(string:)` abre direto.
    public var sourceURL: String?
    /// Histórico da tarefa (FEAT-001): entradas com data de inclusão e descrição, na ordem em
    /// que foram acrescentadas. É log — só acrescenta e apaga, nunca edita.
    public var history: [TaskHistoryEntry]
    /// Tarefa diária (FEAT-004): concluir **fecha** a tarefa como qualquer outra e cria um
    /// **clone** (`nextDailyOccurrence`) com vencimento no dia seguinte. A concluída fica no
    /// histórico e nunca é reaberta pelo app; o clone é a ocorrência de amanhã.
    public var repeatsDaily: Bool
    /// Legado da 1ª versão da diária (até 2026-10-27), em que a mesma tarefa seguia aberta e
    /// cada conclusão entrava aqui. Hoje nada mais grava neste log — ele continua sendo lido
    /// (`CompletedTaskOccurrence`) para o relatório não perder as conclusões antigas.
    public var completionLog: [Date]
    /// Raia do Kanban onde a tarefa aberta está (FEAT-005). `nil` = primeira raia. Não decide
    /// conclusão: tarefa concluída fica sempre na raia Done (`KanbanBoard.lane(for:)`), e o valor
    /// é mantido para reabrir pela lista devolver a tarefa à raia onde estava.
    public var laneID: UUID?
    /// Urgente (RF-09.13): destaque forte na lista e no quadro e vai para o topo da ordenação.
    /// Independente da prioridade — prioridade é importância, urgente é "agora".
    public var isUrgent: Bool
    /// Tarefa pai (FEAT-003 / RF-09.14): subtarefa é uma tarefa completa (tags, prioridade,
    /// vencimento, foco, histórico…) que aponta para o pai. **Um nível só**: quem tem pai não
    /// pode ter filhos — a regra é do use case (`subtaskNestingNotAllowed`). `nil` = tarefa de topo.
    /// Helpers de árvore (filhos, progresso, título "Pai › Filha") em `TaskTree`.
    public var parentID: UUID?
    /// Projeto da tarefa (FEAT-006). `nil` = sem projeto. Subtarefa tem sempre o projeto do pai
    /// — a regra é do use case (herança na criação e propagação na edição do pai).
    public var projectID: UUID?

    public var isCompleted: Bool { completedAt != nil }

    public var isSubtask: Bool { parentID != nil }

    public init(
        id: UUID,
        title: String,
        source: Source,
        reminderID: String? = nil,
        createdAt: Date,
        completedAt: Date? = nil,
        tags: [String] = [],
        notes: String? = nil,
        dueDate: Date? = nil,
        priority: Int? = nil,
        sourceURL: String? = nil,
        history: [TaskHistoryEntry] = [],
        repeatsDaily: Bool = false,
        completionLog: [Date] = [],
        laneID: UUID? = nil,
        isUrgent: Bool = false,
        parentID: UUID? = nil,
        projectID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.reminderID = reminderID
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.tags = FocusTask.normalizeTags(tags)
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.sourceURL = sourceURL
        self.history = history
        self.repeatsDaily = repeatsDaily
        self.completionLog = completionLog
        self.laneID = laneID
        self.isUrgent = isUrgent
        self.parentID = parentID
        self.projectID = projectID
    }

    // Decode manual por causa de `tags` e dos campos ricos de importação: JSON gravado antes
    // desses campos não tem a chave, e Codable sintetizado exigiria a chave. `decodeIfPresent`
    // mantém retrocompatibilidade sem migração. `encode(to:)` continua sintetizado.
    private enum CodingKeys: String, CodingKey {
        case id, title, source, reminderID, createdAt, completedAt, tags
        case notes, dueDate, priority, sourceURL, history
        case repeatsDaily, completionLog, laneID, isUrgent, parentID, projectID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.source = try c.decode(Source.self, forKey: .source)
        self.reminderID = try c.decodeIfPresent(String.self, forKey: .reminderID)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        self.tags = FocusTask.normalizeTags(try c.decodeIfPresent([String].self, forKey: .tags) ?? [])
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        self.sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        self.history = try c.decodeIfPresent([TaskHistoryEntry].self, forKey: .history) ?? []
        self.repeatsDaily = try c.decodeIfPresent(Bool.self, forKey: .repeatsDaily) ?? false
        self.completionLog = try c.decodeIfPresent([Date].self, forKey: .completionLog) ?? []
        self.laneID = try c.decodeIfPresent(UUID.self, forKey: .laneID)
        self.isUrgent = try c.decodeIfPresent(Bool.self, forKey: .isUrgent) ?? false
        self.parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        self.projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
    }

    // MARK: - Nota e link (RF-09.13)

    /// Nota limpa: trim; vazia vira `nil`.
    public static func normalizeNotes(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Link limpo: trim; vazio vira `nil`; sem esquema ganha `https://` (quem cola `globo.com`
    /// quer abrir o site). Lança `invalidLink` se nem assim `URL` aceitar (espaço, sem host).
    public static func normalizeLink(_ raw: String?) throws -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), let host = url.host, !host.isEmpty else {
            throw DomainError.invalidLink(trimmed)
        }
        return withScheme
    }

    // MARK: - Tarefa diária (FEAT-004)

    /// Clone da diária para o dia seguinte, criado ao concluí-la: tarefa **nova** (`id` próprio,
    /// `createdAt = now`, aberta, **sem histórico** — decisão do usuário em 2026-10-27, não
    /// copiar), com os mesmos título, tags, nota, link, prioridade, urgência, pai e origem (o
    /// `reminderID` vai junto — concluir o clone amanhã espelha a próxima ocorrência do lembrete
    /// recorrente) e o projeto (FEAT-006). Vencimento = `nextDailyDueDate`. Sem raia (`laneID = nil`): o dia novo
    /// começa na primeira raia do Kanban.
    public func nextDailyOccurrence(id: UUID, now: Date, calendar: Calendar) -> FocusTask {
        FocusTask(
            id: id,
            title: title,
            source: source,
            reminderID: reminderID,
            createdAt: now,
            tags: tags,
            notes: notes,
            dueDate: nextDailyDueDate(now: now, calendar: calendar),
            priority: priority,
            sourceURL: sourceURL,
            repeatsDaily: true,
            isUrgent: isUrgent,
            parentID: parentID,
            projectID: projectID
        )
    }

    /// Vencimento do clone da diária: **amanhã** (dia seguinte ao de `now`), no mesmo horário
    /// do vencimento atual. Sem vencimento → amanhã 23:59, para não aparecer atrasada antes de
    /// o dia acabar.
    public func nextDailyDueDate(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        let time = dueDate.map { calendar.dateComponents([.hour, .minute, .second], from: $0) }
            ?? DateComponents(hour: 23, minute: 59, second: 0)
        return calendar.date(
            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: tomorrow
        ) ?? tomorrow
    }

    /// Limpa uma lista de tags crua: trim, descarta vazias, deduplica por caixa (mantém a
    /// primeira ocorrência e sua grafia). Núcleo puro — reusado por CRUD e parsing de UI.
    public static func normalizeTags(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in raw {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}
