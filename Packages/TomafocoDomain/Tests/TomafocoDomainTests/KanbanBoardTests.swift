import XCTest
@testable import TomafocoDomain

/// Quadro Kanban (FEAT-005): raia derivada da tarefa, invariantes das raias, prazo da Done e
/// escopo por tag.
final class KanbanBoardTests: XCTestCase {

    private var calendar: Calendar!
    private var board: KanbanBoard!
    private var todo: KanbanLane { board.lanes[0] }
    private var doing: KanbanLane { board.lanes[1] }
    private var done: KanbanLane { board.lanes[2] }

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        board = KanbanBoard.makeDefault(makeID: { UUID() })
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func task(
        _ title: String = "T", laneID: UUID? = nil, completedAt: Date? = nil, tags: [String] = []
    ) -> FocusTask {
        FocusTask(id: UUID(), title: title, source: .manual, createdAt: date(1, 9),
                  completedAt: completedAt, tags: tags, laneID: laneID)
    }

    // MARK: - Padrão e invariantes

    func test_makeDefault_tresRaiasComDoneNoFim() {
        XCTAssertEqual(board.lanes.map(\.title), ["A fazer", "Em andamento", "Concluído"])
        XCTAssertEqual(board.lanes.map(\.isDone), [false, false, true])
        XCTAssertEqual(board.doneRetentionDays, 7)
        XCTAssertEqual(board.taskScope, .all)
    }

    func test_init_reparaRaias_doneNoFim_doneExtraViraAberta_tituloVazio() {
        let a = UUID(), b = UUID(), c = UUID()
        let repaired = KanbanBoard(lanes: [
            KanbanLane(id: a, title: "Feito", isDone: true),
            KanbanLane(id: b, title: "  "),
            KanbanLane(id: c, title: "Outra Done", isDone: true),
        ])
        XCTAssertEqual(repaired.lanes.map(\.id), [b, c, a])
        XCTAssertEqual(repaired.lanes.map(\.isDone), [false, false, true])
        XCTAssertEqual(repaired.lanes[0].title, "Sem nome")
    }

    func test_init_semRaias_criaAbertaEDone() {
        let repaired = KanbanBoard(lanes: [])
        XCTAssertEqual(repaired.lanes.map(\.isDone), [false, true])
    }

    func test_init_retencaoForaDaFaixa_limita() {
        XCTAssertEqual(KanbanBoard(lanes: [], doneRetentionDays: 0).doneRetentionDays, 1)
        XCTAssertEqual(KanbanBoard(lanes: [], doneRetentionDays: 500).doneRetentionDays, 90)
        board.doneRetentionDays = 200
        XCTAssertEqual(board.doneRetentionDays, 90)
    }

    // MARK: - Raia derivada

    func test_laneFor_concluida_vaiParaDone_mesmoComLaneID() {
        XCTAssertEqual(board.lane(for: task(laneID: doing.id, completedAt: date(2, 9))), done)
    }

    func test_laneFor_aberta_respeitaLaneID() {
        XCTAssertEqual(board.lane(for: task(laneID: doing.id)), doing)
    }

    func test_laneFor_semLaneID_orfaOuApontandoParaDone_vaiParaPrimeira() {
        XCTAssertEqual(board.lane(for: task()), todo)
        XCTAssertEqual(board.lane(for: task(laneID: UUID())), todo)
        XCTAssertEqual(board.lane(for: task(laneID: done.id)), todo)
    }

    // MARK: - Mutadores

    func test_addLane_entraAntesDaDone_eRejeitaVazio() throws {
        let id = UUID()
        try board.addLane(id: id, title: "  Revisão ")
        XCTAssertEqual(board.lanes.map(\.title), ["A fazer", "Em andamento", "Revisão", "Concluído"])
        XCTAssertEqual(board.lanes[2].id, id)
        XCTAssertThrowsError(try board.addLane(id: UUID(), title: " ")) {
            XCTAssertEqual($0 as? DomainError, .emptyLaneTitle)
        }
    }

    func test_renameLane_inclusiveDone() throws {
        try board.renameLane(id: done.id, title: "Feito")
        XCTAssertEqual(board.doneLane.title, "Feito")
        XCTAssertThrowsError(try board.renameLane(id: todo.id, title: ""))
    }

    func test_moveOpenLane_reordenaAbertas_doneFica() {
        let doingID = doing.id
        board.moveOpenLane(id: doingID, to: 0)
        XCTAssertEqual(board.lanes[0].id, doingID)
        board.moveOpenLane(id: doingID, to: 99)
        XCTAssertEqual(board.lanes[1].id, doingID)
        XCTAssertTrue(board.lanes[2].isDone)
        let before = board.lanes
        board.moveOpenLane(id: board.doneLane.id, to: 0)
        XCTAssertEqual(board.lanes, before)
    }

    func test_removeLane_regras() throws {
        XCTAssertThrowsError(try board.removeLane(id: done.id)) {
            XCTAssertEqual($0 as? DomainError, .cannotDeleteDoneLane)
        }
        let removed = try board.removeLane(id: doing.id)
        XCTAssertEqual(removed?.title, "Em andamento")
        XCTAssertThrowsError(try board.removeLane(id: todo.id)) {
            XCTAssertEqual($0 as? DomainError, .cannotDeleteLastOpenLane)
        }
        XCTAssertNil(try board.removeLane(id: UUID()))
    }

    // MARK: - Prazo da Done

    func test_showsInDone_umDia_soConcluidasHoje() {
        board.doneRetentionDays = 1
        let now = date(27, 10)
        XCTAssertTrue(board.showsInDone(task(completedAt: date(27, 0, 1)), now: now, calendar: calendar))
        XCTAssertFalse(board.showsInDone(task(completedAt: date(26, 23, 59)), now: now, calendar: calendar))
        XCTAssertFalse(board.showsInDone(task(), now: now, calendar: calendar))
    }

    func test_showsInDone_seteDias_contaDiasDeCalendario() {
        let now = date(27, 10)
        XCTAssertTrue(board.showsInDone(task(completedAt: date(21, 0, 0)), now: now, calendar: calendar))
        XCTAssertFalse(board.showsInDone(task(completedAt: date(20, 23, 59)), now: now, calendar: calendar))
    }

    // MARK: - Colunas

    func test_columns_distribuiPorRaia_eCortaDoneVencida() {
        let open = task("aberta")
        let doingTask = task("andando", laneID: doing.id)
        let recent = task("recente", completedAt: date(26, 9))
        let old = task("antiga", completedAt: date(1, 9))
        let columns = board.columns(for: [open, doingTask, recent, old], now: date(27, 10), calendar: calendar)
        XCTAssertEqual(columns.map(\.lane), board.lanes)
        XCTAssertEqual(columns.map { $0.tasks.map(\.title) }, [["aberta"], ["andando"], ["recente"]])
    }

    func test_columns_escopoPorTag_escondeForaDoEscopoEmTodasAsRaias() {
        board.taskScope = .tags(["Trabalho"])
        let inScope = task("dentro", tags: ["trabalho"])
        let outOpen = task("fora", tags: ["casa"])
        let outDone = task("fora feita", completedAt: date(27, 9))
        let columns = board.columns(for: [inScope, outOpen, outDone], now: date(27, 10), calendar: calendar)
        XCTAssertEqual(columns.flatMap(\.tasks).map(\.title), ["dentro"])
    }

    /// FEAT-003: subtarefa sem tag entra no quadro se o pai estiver no escopo; pai fora do escopo
    /// não traz a filha, a não ser que ela mesma tenha a tag.
    func test_columns_escopoPorTag_subtarefaHerdaDoPai() {
        board.taskScope = .tags(["Trabalho"])
        let paiDentro = task("pai dentro", tags: ["trabalho"])
        let paiFora = task("pai fora", tags: ["casa"])
        var filhaHerda = task("filha herda"); filhaHerda.parentID = paiDentro.id
        var filhaFora = task("filha fora"); filhaFora.parentID = paiFora.id
        var filhaPropria = task("filha própria", tags: ["trabalho"]); filhaPropria.parentID = paiFora.id
        let columns = board.columns(for: [paiDentro, paiFora, filhaHerda, filhaFora, filhaPropria],
                                    now: date(27, 10), calendar: calendar)
        XCTAssertEqual(columns.flatMap(\.tasks).map(\.title), ["pai dentro", "filha herda", "filha própria"])
    }

    /// A UI passa em `for:` só o que sobrou dos filtros da barra; a herança do escopo procura o
    /// pai em `among:` (lista cheia) — buscar pelo nome da filha não pode tirá-la do quadro.
    func test_columns_among_herancaProcuraOPaiNaListaCheia() {
        board.taskScope = .tags(["Trabalho"])
        let pai = task("pai", tags: ["trabalho"])
        var filha = task("filha"); filha.parentID = pai.id
        let visible = [filha]
        XCTAssertEqual(board.columns(for: visible, among: [pai, filha], now: date(27, 10), calendar: calendar)
                           .flatMap(\.tasks).map(\.title), ["filha"])
        XCTAssertEqual(board.columns(for: visible, now: date(27, 10), calendar: calendar)
                           .flatMap(\.tasks), [], "sem a lista cheia o pai não é achado")
    }

    // MARK: - Codable

    func test_decode_semConfigDoQuadro_usaPadroes() throws {
        let json = """
        {"lanes":[{"id":"00000000-0000-0000-0000-0000000000A1","title":"A fazer","isDone":false},
                  {"id":"00000000-0000-0000-0000-0000000000A2","title":"Feito","isDone":true}]}
        """
        let decoded = try JSONDecoder().decode(KanbanBoard.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.lanes.map(\.title), ["A fazer", "Feito"])
        XCTAssertEqual(decoded.doneRetentionDays, 7)
        XCTAssertEqual(decoded.taskScope, .all)
    }

    func test_decode_retencaoForaDaFaixa_limitaSemLancar() throws {
        let json = #"{"lanes":[],"doneRetentionDays":500}"#
        XCTAssertEqual(try JSONDecoder().decode(KanbanBoard.self, from: Data(json.utf8)).doneRetentionDays, 90)
    }

    func test_roundtrip_preserva() throws {
        board.doneRetentionDays = 3
        board.taskScope = .tags(["Trabalho", "Estudo"])
        let decoded = try JSONDecoder().decode(KanbanBoard.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(decoded, board)
    }

    func test_decode_raiaMalformada_descartaSoEla() throws {
        let json = """
        {"lanes":[{"id":"00000000-0000-0000-0000-0000000000A1","title":"A fazer","isDone":false},
                  {"id":"nao-e-uuid","title":"Quebrada","isDone":false},
                  {"id":"00000000-0000-0000-0000-0000000000A3","title":"Feito","isDone":true}],
         "doneRetentionDays":3}
        """
        let decoded = try JSONDecoder().decode(KanbanBoard.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.lanes.map(\.title), ["A fazer", "Feito"])
        XCTAssertEqual(decoded.doneRetentionDays, 3)
    }

    func test_init_reparo_usaMakeIDInjetado() {
        let ids = [UUID(), UUID()]
        var next = ids.makeIterator()
        let repaired = KanbanBoard(lanes: [], makeID: { next.next()! })
        XCTAssertEqual(repaired.lanes.map(\.id), ids)
    }
}
