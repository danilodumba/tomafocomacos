import Foundation

/// Quadro Kanban (FEAT-005): raias + configuração do quadro, persistidos juntos (`kanban.json`).
///
/// Invariantes garantidas por `init`/decode e preservadas pelos mutadores: **exatamente uma**
/// raia Done, sempre a última, e pelo menos uma raia aberta antes dela. Arquivo editado à mão
/// ou corrompido é reparado em vez de derrubar o quadro.
public struct KanbanBoard: Equatable, Codable, Sendable {
    public static let defaultDoneRetentionDays = 7
    public static let doneRetentionRange = 1...90

    public private(set) var lanes: [KanbanLane]
    /// Por quantos dias de calendário uma tarefa concluída continua visível na raia Done
    /// (1 = só as concluídas hoje). Sempre dentro de `doneRetentionRange`.
    public var doneRetentionDays: Int {
        didSet { doneRetentionDays = Self.clampRetention(doneRetentionDays) }
    }
    public var taskScope: TaskScope

    /// `makeID` só é usado se faltar raia aberta ou Done (reparo). Injetado como todo ID do
    /// projeto; o default existe para o decode, que não tem Composition Root.
    public init(
        lanes: [KanbanLane],
        doneRetentionDays: Int = KanbanBoard.defaultDoneRetentionDays,
        taskScope: TaskScope = .all,
        makeID: () -> UUID = { UUID() }
    ) {
        self.lanes = Self.repaired(lanes, makeID: makeID)
        self.doneRetentionDays = Self.clampRetention(doneRetentionDays)
        self.taskScope = taskScope
    }

    /// Quadro inicial: A fazer · Em andamento · Concluído.
    public static func makeDefault(makeID: () -> UUID) -> KanbanBoard {
        KanbanBoard(lanes: [
            KanbanLane(id: makeID(), title: "A fazer"),
            KanbanLane(id: makeID(), title: "Em andamento"),
            KanbanLane(id: makeID(), title: "Concluído", isDone: true),
        ])
    }

    public var openLanes: [KanbanLane] { lanes.filter { !$0.isDone } }
    // As invariantes garantem que existem; `lanes` nunca fica vazio.
    public var doneLane: KanbanLane { lanes[lanes.count - 1] }
    public var firstOpenLane: KanbanLane { lanes[0] }

    public func lane(id: UUID) -> KanbanLane? { lanes.first { $0.id == id } }

    // MARK: - Onde a tarefa aparece

    /// Raia derivada da tarefa — a conclusão manda, não o `laneID`:
    /// concluída → Done; aberta com `laneID` de raia aberta → ela; senão → primeira raia.
    /// Assim lista e quadro nunca divergem.
    public func lane(for task: FocusTask) -> KanbanLane {
        if task.isCompleted { return doneLane }
        if let laneID = task.laneID, let lane = lane(id: laneID), !lane.isDone { return lane }
        return firstOpenLane
    }

    /// Concluída dentro do prazo da raia Done, contado em dias de calendário:
    /// `completedAt >= início de hoje − (N − 1) dias`.
    public func showsInDone(_ task: FocusTask, now: Date, calendar: Calendar) -> Bool {
        guard let completedAt = task.completedAt else { return false }
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(doneRetentionDays - 1), to: today) ?? today
        return completedAt >= start
    }

    /// Colunas do quadro, na ordem das raias: aplica o escopo por tag e o prazo da Done.
    /// A ordem das tarefas dentro de cada coluna é da UI (mesma ordenação da lista).
    /// Subtarefa (FEAT-003) herda o escopo do pai (`TaskScope.includes(_:in:)`).
    public func columns(for tasks: [FocusTask], now: Date, calendar: Calendar) -> [KanbanColumn] {
        columns(for: tasks, among: tasks, now: now, calendar: calendar)
    }

    /// Mesma distribuição, mas a herança de escopo procura o pai em `all` (lista completa), não
    /// só em `tasks`: a UI passa em `tasks` o que sobrou dos filtros da barra, e uma busca que
    /// casa a filha mas não o pai não pode tirar a filha do quadro.
    public func columns(for tasks: [FocusTask], among all: [FocusTask], now: Date, calendar: Calendar) -> [KanbanColumn] {
        var byLane: [UUID: [FocusTask]] = [:]
        for task in tasks where taskScope.includes(task, in: all) {
            if task.isCompleted && !showsInDone(task, now: now, calendar: calendar) { continue }
            byLane[lane(for: task).id, default: []].append(task)
        }
        return lanes.map { KanbanColumn(lane: $0, tasks: byLane[$0.id] ?? []) }
    }

    // MARK: - Raias

    /// Nova raia aberta, logo antes da Done.
    @discardableResult
    public mutating func addLane(id: UUID, title: String) throws -> KanbanLane {
        let lane = KanbanLane(id: id, title: try Self.validTitle(title))
        lanes.insert(lane, at: lanes.count - 1)
        return lane
    }

    /// Renomeia qualquer raia, inclusive a Done. Raia inexistente é no-op.
    public mutating func renameLane(id: UUID, title: String) throws {
        let valid = try Self.validTitle(title)
        guard let idx = lanes.firstIndex(where: { $0.id == id }) else { return }
        lanes[idx].title = valid
    }

    /// Reposiciona uma raia aberta entre as abertas (índice limitado à faixa). A Done não se move.
    public mutating func moveOpenLane(id: UUID, to index: Int) {
        var open = openLanes
        guard let from = open.firstIndex(where: { $0.id == id }) else { return }
        let lane = open.remove(at: from)
        open.insert(lane, at: min(max(index, 0), open.count))
        lanes = open + [doneLane]
    }

    /// Remove uma raia aberta e a devolve. A Done e a última aberta não saem.
    /// Raia inexistente devolve `nil`.
    @discardableResult
    public mutating func removeLane(id: UUID) throws -> KanbanLane? {
        guard let lane = lane(id: id) else { return nil }
        if lane.isDone { throw DomainError.cannotDeleteDoneLane }
        guard openLanes.count > 1 else { throw DomainError.cannotDeleteLastOpenLane }
        lanes.removeAll { $0.id == id }
        return lane
    }

    // MARK: - Invariantes

    private static func validTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.emptyLaneTitle }
        return trimmed
    }

    private static func clampRetention(_ days: Int) -> Int {
        min(max(days, doneRetentionRange.lowerBound), doneRetentionRange.upperBound)
    }

    /// Repara uma lista de raias qualquer: título vazio ganha nome, Done extra vira aberta
    /// (mesmo `id`, então tarefas que apontavam para ela continuam lá), falta de aberta ou de
    /// Done cria a raia que falta, e a Done vai para o fim.
    private static func repaired(_ lanes: [KanbanLane], makeID: () -> UUID) -> [KanbanLane] {
        var open: [KanbanLane] = []
        var done: KanbanLane?
        for lane in lanes {
            let title = lane.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if lane.isDone && done == nil {
                done = KanbanLane(id: lane.id, title: title.isEmpty ? "Concluído" : title, isDone: true)
            } else {
                open.append(KanbanLane(id: lane.id, title: title.isEmpty ? "Sem nome" : title))
            }
        }
        if open.isEmpty { open.append(KanbanLane(id: makeID(), title: "A fazer")) }
        return open + [done ?? KanbanLane(id: makeID(), title: "Concluído", isDone: true)]
    }

    // Decode manual: arquivo de versão anterior sem a config do quadro abre com os padrões, e
    // valor fora da faixa é limitado em vez de lançar (lançar descartaria o quadro inteiro).
    // Raia malformada (ex.: `id` inválido num arquivo editado à mão) é descartada sozinha —
    // `repaired` completa o que faltar; o resto do arquivo sobrevive.
    private enum CodingKeys: String, CodingKey { case lanes, doneRetentionDays, taskScope }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lanes = try c.decodeIfPresent([LenientLane].self, forKey: .lanes) ?? []
        self.init(
            lanes: lanes.compactMap(\.lane),
            doneRetentionDays: try c.decodeIfPresent(Int.self, forKey: .doneRetentionDays)
                ?? Self.defaultDoneRetentionDays,
            taskScope: try c.decodeIfPresent(TaskScope.self, forKey: .taskScope) ?? .all
        )
    }
}

/// Raia que decodifica como `nil` em vez de lançar — uma entrada quebrada não derruba o quadro.
private struct LenientLane: Decodable {
    let lane: KanbanLane?
    init(from decoder: Decoder) throws {
        lane = try? KanbanLane(from: decoder)
    }
}

/// Uma coluna pronta para exibir: a raia e as tarefas que caem nela.
public struct KanbanColumn: Equatable, Sendable, Identifiable {
    public let lane: KanbanLane
    public let tasks: [FocusTask]

    public var id: UUID { lane.id }

    public init(lane: KanbanLane, tasks: [FocusTask]) {
        self.lane = lane
        self.tasks = tasks
    }
}
