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
    /// Repetição (FEAT-004, generalizada no RF-09.21): concluir **fecha** a tarefa como qualquer
    /// outra e cria um **clone** (`nextOccurrence`) com vencimento na próxima data da regra. A
    /// concluída fica no histórico e nunca é reaberta pelo app. `nil` = não repete.
    public var recurrence: TaskRecurrence?
    /// Atalho da época da diária (FEAT-004): "repete de algum jeito". Ligar sem regra = todo dia;
    /// desligar = não repete. Mantido porque lista, Kanban e testes falam em "diária".
    public var repeatsDaily: Bool {
        get { recurrence != nil }
        set { recurrence = newValue ? (recurrence ?? .everyDay) : nil }
    }
    /// Legado da 1ª versão da diária (até 2026-10-27), em que a mesma tarefa seguia aberta e
    /// cada conclusão entrava aqui. Hoje nada mais grava neste log — ele continua sendo lido
    /// (`CompletedTaskOccurrence`) para o relatório não perder as conclusões antigas.
    public var completionLog: [Date]
    /// Raias do Kanban onde a tarefa aberta está — **uma por quadro** (FEAT-005, FEAT-008).
    /// IDs de raia são únicos entre quadros, então cada quadro usa o primeiro id que é raia
    /// aberta dele e ignora os demais; sem nenhum → primeira raia daquele quadro. Não decide
    /// conclusão: tarefa concluída fica sempre na raia Done (`KanbanBoard.lane(for:)`), e os ids
    /// são mantidos para reabrir pela lista devolver a tarefa às raias onde estava.
    /// Era `laneID: UUID?` (um quadro só) até a FEAT-008 — o decode ainda lê a chave antiga.
    public var laneIDs: [UUID]
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
    /// Código da tarefa (RF-09.22), ex.: "PSC0001" — gerado pelo projeto (`Project.takeNextTaskCode`)
    /// ao criar/associar, ou digitado pelo usuário. Só tarefa de topo ganha código gerado.
    public var code: String?

    public var isCompleted: Bool { completedAt != nil }

    /// "PSC0001 - Título" com código; só o título sem. É o que as listas mostram.
    public var displayTitle: String {
        guard let code else { return title }
        return "\(code) - \(title)"
    }

    /// Código digitado: trim; vazio vira `nil`. Livre — o usuário escolhe o que quiser.
    public static func normalizeCode(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

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
        recurrence: TaskRecurrence? = nil,
        completionLog: [Date] = [],
        laneIDs: [UUID] = [],
        isUrgent: Bool = false,
        parentID: UUID? = nil,
        projectID: UUID? = nil,
        code: String? = nil
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
        self.recurrence = recurrence?.normalized ?? (repeatsDaily ? .everyDay : nil)
        self.completionLog = completionLog
        self.laneIDs = laneIDs
        self.isUrgent = isUrgent
        self.parentID = parentID
        self.projectID = projectID
        self.code = code
    }

    // Decode manual por causa de `tags` e dos campos ricos de importação: JSON gravado antes
    // desses campos não tem a chave, e Codable sintetizado exigiria a chave. `decodeIfPresent`
    // mantém retrocompatibilidade sem migração. `encode(to:)` continua sintetizado.
    private enum CodingKeys: String, CodingKey {
        case id, title, source, reminderID, createdAt, completedAt, tags
        case notes, dueDate, priority, sourceURL, history
        case recurrence, completionLog, laneIDs, isUrgent, parentID, projectID, code
    }

    /// Chave da versão de um quadro só (FEAT-005, até a FEAT-008) — só lida, nunca gravada.
    /// `laneID`: quadro único (FEAT-005, até a FEAT-008). `repeatsDaily`: diária (FEAT-004, até o
    /// RF-09.21) — `true` vira repetição todo dia.
    private enum LegacyCodingKeys: String, CodingKey { case laneID, repeatsDaily }

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
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        if let recurrence = try? c.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence) {
            self.recurrence = recurrence
        } else {
            let wasDaily = (try? legacy.decodeIfPresent(Bool.self, forKey: .repeatsDaily)) ?? false
            self.recurrence = wasDaily ? .everyDay : nil
        }
        self.completionLog = try c.decodeIfPresent([Date].self, forKey: .completionLog) ?? []
        if let laneIDs = try c.decodeIfPresent([UUID].self, forKey: .laneIDs) {
            self.laneIDs = laneIDs
        } else {
            self.laneIDs = try legacy.decodeIfPresent(UUID.self, forKey: .laneID).map { [$0] } ?? []
        }
        self.isUrgent = try c.decodeIfPresent(Bool.self, forKey: .isUrgent) ?? false
        self.parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        self.projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        self.code = try c.decodeIfPresent(String.self, forKey: .code)
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

    // MARK: - Duplicar (RF-09.19)

    /// Cópia da tarefa para "duplicar": tarefa **nova e aberta** (`id` próprio, `createdAt = now`)
    /// com título, tags, nota, link, vencimento, prioridade, urgência, diária, pai, projeto e
    /// raias do Kanban (a cópia aparece ao lado da original em cada quadro). **Não** leva
    /// histórico (é log da original), conclusão nem o vínculo com o Lembretes — a cópia é manual:
    /// concluí-la não pode riscar o lembrete da original, e o `reminderID` repetido confundiria a
    /// deduplicação da importação.
    public func duplicated(id: UUID, title: String, parentID: UUID?, now: Date) -> FocusTask {
        FocusTask(
            id: id, title: title, source: .manual, createdAt: now,
            tags: tags, notes: notes, dueDate: dueDate, priority: priority, sourceURL: sourceURL,
            recurrence: recurrence, laneIDs: laneIDs, isUrgent: isUrgent,
            parentID: parentID, projectID: projectID)
    }

    /// Título da cópia: "X (cópia)", ou "X (cópia 2)", "X (cópia 3)"… até `isTaken` devolver
    /// `false`. Duplicar uma cópia não empilha sufixos — "X (cópia)" vira "X (cópia 2)".
    public static func duplicateTitle(for title: String, isTaken: (String) -> Bool) -> String {
        var base = title
        if let range = base.range(of: #" \(cópia( \d+)?\)$"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        var candidate = "\(base) (cópia)"
        var n = 2
        while isTaken(candidate) {
            candidate = "\(base) (cópia \(n))"
            n += 1
        }
        return candidate
    }

    // MARK: - Repetição (FEAT-004 / RF-09.21)

    /// Clone da tarefa que repete, criado ao concluí-la: tarefa **nova** (`id` próprio,
    /// `createdAt = now`, aberta, **sem histórico** — decisão do usuário em 2026-10-27, não
    /// copiar), com os mesmos título, tags, nota, link, prioridade, urgência, pai, origem (o
    /// `reminderID` vai junto — concluir o clone espelha a próxima ocorrência do lembrete
    /// recorrente), projeto (FEAT-006), código (RF-09.22) e **a mesma regra**. Vencimento = `nextOccurrenceDueDate`.
    /// Sem raia (`laneIDs` vazio): a próxima ocorrência começa na primeira raia de cada quadro.
    public func nextOccurrence(id: UUID, now: Date, calendar: Calendar) -> FocusTask {
        FocusTask(
            id: id,
            title: title,
            source: source,
            reminderID: reminderID,
            createdAt: now,
            tags: tags,
            notes: notes,
            dueDate: nextOccurrenceDueDate(now: now, calendar: calendar),
            priority: priority,
            sourceURL: sourceURL,
            recurrence: recurrence ?? .everyDay,
            isUrgent: isUrgent,
            parentID: parentID,
            projectID: projectID,
            // Mesma tarefa, próxima ocorrência: mantém o código (RF-09.22) em vez de gastar um
            // número do projeto a cada repetição.
            code: code
        )
    }

    /// Vencimento do clone: o **próximo dia da regra** depois do dia de `now`
    /// (`TaskRecurrence.nextDay`; sem regra = amanhã), no mesmo horário do vencimento atual. Sem
    /// vencimento → 23:59, para não aparecer atrasada antes de o dia acabar.
    public func nextOccurrenceDueDate(now: Date, calendar: Calendar) -> Date {
        let day = (recurrence ?? .everyDay).nextDay(after: now, calendar: calendar)
        let time = dueDate.map { calendar.dateComponents([.hour, .minute, .second], from: $0) }
            ?? DateComponents(hour: 23, minute: 59, second: 0)
        return calendar.date(
            bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day
        ) ?? day
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
