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
    /// Notas do lembrete de origem (`EKReminder.notes`). `nil` para tarefa manual ou sem notas.
    public var notes: String?
    /// Data de vencimento do lembrete de origem (`EKReminder.dueDateComponents`).
    public var dueDate: Date?
    /// Prioridade do lembrete (`EKReminder.priority`, 1–9; menor = mais urgente).
    /// `nil` = sem prioridade (o EventKit usa 0 para "nenhuma" — normalizado para `nil` na importação).
    public var priority: Int?
    /// URL anexada ao lembrete pelo usuário (`EKReminder.url`). NÃO é deep-link para o app
    /// Lembretes (EventKit não expõe isso) — é o link que o próprio lembrete carrega.
    public var sourceURL: String?
    /// Histórico da tarefa (FEAT-001): entradas com data de inclusão e descrição, na ordem em
    /// que foram acrescentadas. É log — só acrescenta e apaga, nunca edita.
    public var history: [TaskHistoryEntry]
    /// Tarefa diária (FEAT-004): concluir não fecha a tarefa — registra a conclusão (log +
    /// histórico) e empurra o vencimento para o dia seguinte. Mesmo `id`: o foco acumula nela.
    public var repeatsDaily: Bool
    /// Datas em que a tarefa diária foi concluída, na ordem. A diária nunca fica com
    /// `completedAt` preenchido, então é daqui que o relatório tira as conclusões.
    public var completionLog: [Date]

    public var isCompleted: Bool { completedAt != nil }

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
        completionLog: [Date] = []
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
    }

    // Decode manual por causa de `tags` e dos campos ricos de importação: JSON gravado antes
    // desses campos não tem a chave, e Codable sintetizado exigiria a chave. `decodeIfPresent`
    // mantém retrocompatibilidade sem migração. `encode(to:)` continua sintetizado.
    private enum CodingKeys: String, CodingKey {
        case id, title, source, reminderID, createdAt, completedAt, tags
        case notes, dueDate, priority, sourceURL, history
        case repeatsDaily, completionLog
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
    }

    // MARK: - Tarefa diária (FEAT-004)

    /// Próximo vencimento ao concluir a diária: **amanhã** (dia seguinte ao de `now`), no mesmo
    /// horário do vencimento atual. Sem vencimento → amanhã 23:59, para não aparecer atrasada
    /// antes de o dia acabar.
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
