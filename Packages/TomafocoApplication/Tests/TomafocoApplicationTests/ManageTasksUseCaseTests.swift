import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

@MainActor
final class ManageTasksUseCaseTests: XCTestCase {

    private var repo: InMemoryTaskRepository!
    private var importer: StubTaskImporter!
    private var sut: ManageTasksUseCase!
    private let now = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        super.setUp()
        repo = InMemoryTaskRepository()
        importer = StubTaskImporter()
        sut = ManageTasksUseCase(tasks: repo, importer: importer, now: { self.now })
    }

    // MARK: criação manual

    func test_addTask_normalizaTituloEPersiste() throws {
        let task = try sut.addTask(title: "  Revisar PR  ")
        XCTAssertEqual(task.title, "Revisar PR")
        XCTAssertEqual(task.source, .manual)
        XCTAssertEqual(repo.tasks.count, 1)
    }

    func test_addTask_normalizaTagsEPersiste() throws {
        let task = try sut.addTask(title: "Deploy", tags: ["  Trabalho ", "urgente", "trabalho", "  "])
        // trim + descarta vazia + dedup por caixa (mantém a primeira grafia).
        XCTAssertEqual(task.tags, ["Trabalho", "urgente"])
        XCTAssertEqual(try repo.loadTasks().first?.tags, ["Trabalho", "urgente"])
    }

    func test_setTags_substituiENormaliza() throws {
        let task = try sut.addTask(title: "Estudar", tags: ["antiga"])
        try sut.setTags(id: task.id, tags: ["nova", "NOVA", " outra "])
        XCTAssertEqual(try repo.loadTasks().first?.tags, ["nova", "outra"])
    }

    func test_setTags_idInexistente_naoLanca() throws {
        XCTAssertNoThrow(try sut.setTags(id: UUID(), tags: ["x"]))
    }

    func test_allTags_uniaoOrdenadaSemDuplicata() throws {
        try sut.addTask(title: "A", tags: ["Zebra", "alpha"])
        try sut.addTask(title: "B", tags: ["alpha", "beta"])
        XCTAssertEqual(try sut.allTags(), ["alpha", "beta", "Zebra"])
    }

    // MARK: prioridade (RF-09 / item 4)

    func test_setPriority_gravaValorCanonico() throws {
        let task = try sut.addTask(title: "Boleto")
        try sut.setPriority(id: task.id, priority: .high)
        XCTAssertEqual(try repo.loadTasks().first?.priority, 1)
        try sut.setPriority(id: task.id, priority: .none)
        XCTAssertNil(try repo.loadTasks().first?.priority)
    }

    // MARK: edição completa (RF-09.6)

    func test_editTask_gravaTodosOsCampos() throws {
        let task = try sut.addTask(title: "Rascunho", tags: ["antiga"])
        let due = Date(timeIntervalSince1970: 2_000_000)
        let edited = try sut.editTask(
            id: task.id, title: "  Relatório final ", tags: ["Trabalho", "trabalho", " "],
            dueDate: due, priority: .medium
        )
        XCTAssertEqual(edited?.title, "Relatório final")
        let stored = try XCTUnwrap(try repo.loadTasks().first)
        XCTAssertEqual(stored.title, "Relatório final")
        XCTAssertEqual(stored.tags, ["Trabalho"])
        XCTAssertEqual(stored.dueDate, due)
        XCTAssertEqual(stored.priority, 5)
    }

    func test_editTask_dataEPrioridadePodemSerLimpas() throws {
        let task = try sut.addTask(title: "Boleto")
        try sut.editTask(id: task.id, title: "Boleto", tags: [],
                         dueDate: Date(timeIntervalSince1970: 3_000), priority: .high)
        try sut.editTask(id: task.id, title: "Boleto", tags: [],
                         dueDate: nil, priority: .none)
        let stored = try XCTUnwrap(try repo.loadTasks().first)
        XCTAssertNil(stored.dueDate)
        XCTAssertNil(stored.priority)
    }

    /// A forma curta do `editTask` é parcial: nota, link e urgente importados/gravados sobrevivem.
    func test_editTask_formaCurta_preservaNotaLinkEUrgente() throws {
        var all = try repo.loadTasks()
        let task = FocusTask(id: UUID(), title: "Conta", source: .manual,
                             createdAt: Date(timeIntervalSince1970: 0), notes: "conta de luz",
                             sourceURL: "https://conta.com", isUrgent: true)
        all.append(task)
        try repo.saveTasks(all)
        try sut.editTask(id: task.id, title: "Conta paga", tags: [], dueDate: nil, priority: .none)
        let stored = try XCTUnwrap(try repo.loadTasks().first)
        XCTAssertEqual(stored.notes, "conta de luz")
        XCTAssertEqual(stored.sourceURL, "https://conta.com")
        XCTAssertTrue(stored.isUrgent)
    }

    // MARK: nota, link e urgente (RF-09.13)

    func test_editTask_completo_gravaNotaLinkEUrgente() throws {
        let task = try sut.addTask(title: "Conta")
        try sut.editTask(id: task.id, TaskEdit(
            title: "Conta", notes: "  pagar até dia 10 ", link: " globo.com/esportes ", isUrgent: true))
        let stored = try XCTUnwrap(try repo.loadTasks().first)
        XCTAssertEqual(stored.notes, "pagar até dia 10")
        XCTAssertEqual(stored.sourceURL, "https://globo.com/esportes")
        XCTAssertTrue(stored.isUrgent)
    }

    func test_editTask_completo_notaELinkEmBrancoViramNil_eUrgenteDesliga() throws {
        let task = try sut.addTask(title: "Conta")
        try sut.editTask(id: task.id, TaskEdit(title: "Conta", notes: "x", link: "a.com", isUrgent: true))
        try sut.editTask(id: task.id, TaskEdit(title: "Conta", notes: "   ", link: "", isUrgent: false))
        let stored = try XCTUnwrap(try repo.loadTasks().first)
        XCTAssertNil(stored.notes)
        XCTAssertNil(stored.sourceURL)
        XCTAssertFalse(stored.isUrgent)
    }

    func test_editTask_linkComEsquema_ficaComoEsta() throws {
        let task = try sut.addTask(title: "Conta")
        try sut.editTask(id: task.id, TaskEdit(title: "Conta", link: "http://intranet.local/x?y=1"))
        XCTAssertEqual(try repo.loadTasks().first?.sourceURL, "http://intranet.local/x?y=1")
    }

    /// Link que já estava gravado (ex.: `mailto:` ou `file://` vindos do Lembretes) não passa
    /// pela normalização quando não mudou — senão `mailto:x` viraria `https://mailto:x` e
    /// `file://` (sem host) impediria salvar qualquer outro campo.
    func test_editTask_linkInalterado_naoRenormalizaNemValida() throws {
        for raw in ["mailto:joao@x.com", "file:///Users/me/doc.pdf", "tel:+5511999999999"] {
            let task = FocusTask(id: UUID(), title: "Importada \(raw)", source: .reminders,
                                 createdAt: now, sourceURL: raw)
            try repo.saveTasks(try repo.loadTasks() + [task])

            try sut.editTask(id: task.id, TaskEdit(title: "Mudou \(raw)", link: raw))
            XCTAssertEqual(try stored(task.id).sourceURL, raw)
            XCTAssertEqual(try stored(task.id).title, "Mudou \(raw)")

            try sut.editTask(id: task.id, title: "Curta \(raw)", tags: [], dueDate: nil, priority: .none)
            XCTAssertEqual(try stored(task.id).sourceURL, raw)
        }
    }

    func test_editTask_linkAlterado_continuaValidando() throws {
        let task = FocusTask(id: UUID(), title: "Importada", source: .reminders, createdAt: now,
                             sourceURL: "mailto:joao@x.com")
        try repo.saveTasks([task])
        XCTAssertThrowsError(try sut.editTask(id: task.id, TaskEdit(title: "Importada", link: "isso não é link")))
        try sut.editTask(id: task.id, TaskEdit(title: "Importada", link: "globo.com"))
        XCTAssertEqual(try stored(task.id).sourceURL, "https://globo.com")
    }

    func test_editTask_gravaUmaVezSo() throws {
        let task = try sut.addTask(title: "Conta")
        let before = repo.saveCallCount
        try sut.editTask(id: task.id, TaskEdit(title: "Conta paga", link: "a.com"))
        XCTAssertEqual(repo.saveCallCount - before, 1)
        try sut.editTask(id: task.id, title: "Conta quitada", tags: [], dueDate: nil, priority: .none)
        XCTAssertEqual(repo.saveCallCount - before, 2)
    }

    func test_editTask_linkInvalido_lancaENaoGrava() throws {
        let task = try sut.addTask(title: "Conta")
        XCTAssertThrowsError(try sut.editTask(id: task.id, TaskEdit(title: "Mudou", link: "isso não é link"))) {
            XCTAssertEqual($0 as? DomainError, .invalidLink("isso não é link"))
        }
        XCTAssertEqual(try repo.loadTasks().first?.title, "Conta")
    }

    func test_setUrgent_ligaEDesliga() throws {
        let task = try sut.addTask(title: "Conta")
        try sut.setUrgent(id: task.id, true)
        XCTAssertTrue(try XCTUnwrap(repo.loadTasks().first).isUrgent)
        try sut.setUrgent(id: task.id, false)
        XCTAssertFalse(try XCTUnwrap(repo.loadTasks().first).isUrgent)
        XCTAssertNoThrow(try sut.setUrgent(id: UUID(), true))
    }

    func test_editTask_tituloVazio_lanca() throws {
        let task = try sut.addTask(title: "Algo")
        XCTAssertThrowsError(
            try sut.editTask(id: task.id, title: "   ", tags: [],
                             dueDate: nil, priority: .none)
        ) { XCTAssertEqual($0 as? DomainError, .emptyTaskTitle) }
    }

    func test_editTask_tituloDeOutraAtiva_lancaDuplicata() throws {
        try sut.addTask(title: "Existente")
        let task = try sut.addTask(title: "Outra")
        XCTAssertThrowsError(
            try sut.editTask(id: task.id, title: "existente", tags: [],
                             dueDate: nil, priority: .none)
        ) { XCTAssertEqual($0 as? DomainError, .duplicateEntry("existente")) }
    }

    // Salvar sem mexer no título não pode acusar duplicata contra a própria tarefa.
    func test_editTask_mesmoTitulo_naoAcusaDuplicata() throws {
        let task = try sut.addTask(title: "Manter")
        XCTAssertNoThrow(
            try sut.editTask(id: task.id, title: "Manter", tags: ["x"],
                             dueDate: nil, priority: .low)
        )
    }

    func test_editTask_idInexistente_devolveNilSemGravar() throws {
        try sut.addTask(title: "Intacta")
        let result = try sut.editTask(id: UUID(), title: "Nova", tags: [],
                                      dueDate: nil, priority: .none)
        XCTAssertNil(result)
        XCTAssertEqual(try repo.loadTasks().first?.title, "Intacta")
    }

    func test_editTask_tagsEntramNoCatalogo() throws {
        let task = try sut.addTask(title: "A")
        try sut.editTask(id: task.id, title: "A", tags: ["Faturamento"],
                         dueDate: nil, priority: .none)
        try sut.deleteTask(id: task.id)
        XCTAssertEqual(try sut.allTags(), ["Faturamento"])
    }

    // MARK: histórico (FEAT-001)

    func test_addHistoryEntry_usaNowEMakeIDInjetados() throws {
        let entryID = UUID(uuidString: "00000000-0000-0000-0000-0000000000EE")!
        // `addTask` também puxa do `makeID` — o 1º da fila é a tarefa, o 2º é a entrada.
        var ids = [UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, entryID]
        let sut = ManageTasksUseCase(
            tasks: repo, importer: importer, now: { self.now },
            makeID: { ids.isEmpty ? UUID() : ids.removeFirst() })
        let task = try sut.addTask(title: "Cliente")

        let updated = try sut.addHistoryEntry(taskID: task.id, text: "  liguei pro cliente  ")

        XCTAssertEqual(updated?.history.count, 1)
        XCTAssertEqual(updated?.history.first?.id, entryID)
        XCTAssertEqual(updated?.history.first?.createdAt, now)
        // Descrição é trimada no use case — a UI não precisa se preocupar.
        XCTAssertEqual(updated?.history.first?.text, "liguei pro cliente")
        XCTAssertEqual(try repo.loadTasks().first?.history.first?.text, "liguei pro cliente")
    }

    func test_addHistoryEntry_textoEmBranco_lanca() throws {
        let task = try sut.addTask(title: "Cliente")
        XCTAssertThrowsError(try sut.addHistoryEntry(taskID: task.id, text: "   \n ")) { error in
            XCTAssertEqual(error as? DomainError, .emptyHistoryEntry)
        }
        XCTAssertEqual(try repo.loadTasks().first?.history, [])
    }

    func test_addHistoryEntry_acrescentaNoFimPreservandoAsAnteriores() throws {
        let task = try sut.addTask(title: "Cliente")
        try sut.addHistoryEntry(taskID: task.id, text: "primeira")
        try sut.addHistoryEntry(taskID: task.id, text: "segunda")
        XCTAssertEqual(try repo.loadTasks().first?.history.map(\.text), ["primeira", "segunda"])
    }

    func test_addHistoryEntry_tarefaInexistente_devolveNilSemGravar() throws {
        try sut.addTask(title: "Intacta")
        XCTAssertNil(try sut.addHistoryEntry(taskID: UUID(), text: "x"))
        XCTAssertEqual(try repo.loadTasks().first?.history, [])
    }

    func test_deleteHistoryEntry_removeSoAEntradaAlvo() throws {
        let task = try sut.addTask(title: "Cliente")
        try sut.addHistoryEntry(taskID: task.id, text: "primeira")
        let segunda = try sut.addHistoryEntry(taskID: task.id, text: "segunda")
        let alvo = try XCTUnwrap(segunda?.history.last?.id)

        let updated = try sut.deleteHistoryEntry(taskID: task.id, entryID: alvo)

        XCTAssertEqual(updated?.history.map(\.text), ["primeira"])
        XCTAssertEqual(try repo.loadTasks().first?.history.map(\.text), ["primeira"])
    }

    func test_deleteHistoryEntry_entradaOuTarefaInexistente_naoLanca() throws {
        let task = try sut.addTask(title: "Cliente")
        try sut.addHistoryEntry(taskID: task.id, text: "unica")
        XCTAssertNoThrow(try sut.deleteHistoryEntry(taskID: task.id, entryID: UUID()))
        XCTAssertNil(try sut.deleteHistoryEntry(taskID: UUID(), entryID: UUID()))
        XCTAssertEqual(try repo.loadTasks().first?.history.count, 1)
    }

    /// `editTask` muta só os campos do formulário — histórico não pode ser zerado por salvar
    /// a tarefa (o formulário não carrega o histórico no rascunho).
    func test_editTask_preservaOHistorico() throws {
        let task = try sut.addTask(title: "Cliente")
        try sut.addHistoryEntry(taskID: task.id, text: "liguei")
        try sut.editTask(id: task.id, title: "Cliente novo", tags: ["x"],
                         dueDate: nil, priority: .high)
        XCTAssertEqual(try repo.loadTasks().first?.history.map(\.text), ["liguei"])
    }

    // MARK: subtarefas (FEAT-003)

    private func stored(_ id: UUID) throws -> FocusTask {
        try XCTUnwrap(repo.tasks.first { $0.id == id })
    }

    func test_addSubtask_criaTarefaCompletaComPaiETrimaUsandoNowEMakeID() throws {
        let childID = UUID(uuidString: "00000000-0000-0000-0000-0000000000EE")!
        var ids = [UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, childID]
        let sut = ManageTasksUseCase(
            tasks: repo, importer: importer, now: { self.now },
            makeID: { ids.isEmpty ? UUID() : ids.removeFirst() })
        let parent = try sut.addTask(title: "Apresentação")
        try sut.setTags(id: parent.id, tags: ["trabalho"])

        let child = try sut.addSubtask(parentID: parent.id, title: "  Esboço  ", tags: ["slides"])

        XCTAssertEqual(child.id, childID)
        XCTAssertEqual(child.parentID, parent.id)
        XCTAssertEqual(child.title, "Esboço")
        XCTAssertEqual(child.createdAt, now)
        XCTAssertEqual(child.source, .manual)
        XCTAssertEqual(child.tags, ["slides"])
        XCTAssertTrue(child.isSubtask)
        XCTAssertEqual(try stored(child.id).parentID, parent.id)
        // Tag da subtarefa entra no catálogo como qualquer outra.
        XCTAssertEqual(try sut.allTags(), ["slides", "trabalho"])
    }

    /// Nasce na raia do pai (Kanban): criar pelo formulário não pode jogar a filha na 1ª raia
    /// enquanto o pai está em "Em andamento".
    func test_addSubtask_herdaRaiaDoPai() throws {
        let parent = try sut.addTask(title: "Apresentação")
        let lane = UUID()
        try sut.update(id: parent.id) { $0.laneID = lane }

        let child = try sut.addSubtask(parentID: parent.id, title: "Esboço")

        XCTAssertEqual(child.laneID, lane)
    }

    func test_addSubtask_paiInexistente_lanca() {
        XCTAssertThrowsError(try sut.addSubtask(parentID: UUID(), title: "x")) { error in
            XCTAssertEqual(error as? DomainError, .parentTaskNotFound)
        }
        XCTAssertEqual(repo.tasks, [])
    }

    /// Um nível só: subtarefa de subtarefa é recusada.
    func test_addSubtask_deSubtarefa_lanca() throws {
        let parent = try sut.addTask(title: "Apresentação")
        let child = try sut.addSubtask(parentID: parent.id, title: "Esboço")
        XCTAssertThrowsError(try sut.addSubtask(parentID: child.id, title: "Neta")) { error in
            XCTAssertEqual(error as? DomainError, .subtaskNestingNotAllowed)
        }
        XCTAssertEqual(repo.tasks.count, 2)
    }

    func test_addSubtask_tituloEmBranco_lanca() throws {
        let parent = try sut.addTask(title: "Apresentação")
        XCTAssertThrowsError(try sut.addSubtask(parentID: parent.id, title: " \n ")) { error in
            XCTAssertEqual(error as? DomainError, .emptyTaskTitle)
        }
        XCTAssertEqual(repo.tasks.count, 1)
    }

    /// Unicidade por irmãos ativos: repete sob outro pai e repete título de tarefa de topo;
    /// não repete sob o mesmo pai (salvo se a irmã já estiver concluída).
    func test_addSubtask_duplicataSoEntreIrmasAtivas() async throws {
        let p1 = try sut.addTask(title: "P1")
        let p2 = try sut.addTask(title: "P2")
        let revisar = try sut.addSubtask(parentID: p1.id, title: "Revisar")
        XCTAssertNoThrow(try sut.addSubtask(parentID: p2.id, title: "revisar"))
        XCTAssertNoThrow(try sut.addSubtask(parentID: p1.id, title: "P2"))
        XCTAssertThrowsError(try sut.addSubtask(parentID: p1.id, title: " REVISAR ")) { error in
            XCTAssertEqual(error as? DomainError, .duplicateEntry("REVISAR"))
        }
        try await sut.completeTask(id: revisar.id)
        XCTAssertNoThrow(try sut.addSubtask(parentID: p1.id, title: "Revisar"))
    }

    /// `addTask`/lote: tarefa de topo pode repetir o título de uma subtarefa ativa.
    func test_addTaskEValidateNewTasks_ignoramSubtarefasNaDuplicata() throws {
        let parent = try sut.addTask(title: "Apresentação")
        try sut.addSubtask(parentID: parent.id, title: "Revisar")
        XCTAssertNoThrow(try sut.addTask(title: "Revisar"))
        XCTAssertEqual(try sut.validateNewTasks([NewTaskDraft(title: "Revisar")]).keys.sorted(), [0])
        try sut.addSubtask(parentID: parent.id, title: "Ensaiar")
        XCTAssertEqual(try sut.validateNewTasks([NewTaskDraft(title: "Ensaiar")]), [:])
    }

    /// `editTask`: duplicata contra irmãs, não contra a lista inteira; `parentID` é preservado.
    func test_editTask_duplicataEntreIrmasEPreservaPai() throws {
        let parent = try sut.addTask(title: "Apresentação")
        let a = try sut.addSubtask(parentID: parent.id, title: "A")
        try sut.addSubtask(parentID: parent.id, title: "B")

        XCTAssertNoThrow(try sut.editTask(id: a.id, title: "Apresentação", tags: [], dueDate: nil, priority: .none))
        XCTAssertThrowsError(try sut.editTask(id: a.id, title: "b", tags: [], dueDate: nil, priority: .none)) { error in
            XCTAssertEqual(error as? DomainError, .duplicateEntry("b"))
        }
        try sut.editTask(id: a.id, TaskEdit(title: "A2", isUrgent: true))
        XCTAssertEqual(try stored(a.id).parentID, parent.id)
        XCTAssertEqual(try stored(a.id).title, "A2")
    }

    /// Concluir o pai fecha as filhas abertas com a MESMA data; as já concluídas mantêm a sua.
    func test_completeTask_cascataFechaFilhasAbertasEPreservaDataDasFeitas() async throws {
        let parent = try sut.addTask(title: "Apresentação")
        let feita = try sut.addSubtask(parentID: parent.id, title: "feita")
        let aberta = try sut.addSubtask(parentID: parent.id, title: "aberta")
        let earlier = now.addingTimeInterval(-3_600)
        let earlierSut = ManageTasksUseCase(tasks: repo, importer: importer, now: { earlier })
        try await earlierSut.completeTask(id: feita.id)
        let saves = repo.saveCallCount

        try await sut.completeTask(id: parent.id)

        XCTAssertEqual(try stored(parent.id).completedAt, now)
        XCTAssertEqual(try stored(feita.id).completedAt, earlier)
        XCTAssertEqual(try stored(aberta.id).completedAt, now)
        XCTAssertEqual(repo.saveCallCount - saves, 1, "cascata numa gravação só")
    }

    /// Fechar todas as filhas NÃO conclui o pai; concluir a filha não mexe no pai nem nas irmãs.
    func test_completeTask_filha_naoTocaPaiNemIrmas() async throws {
        let parent = try sut.addTask(title: "Apresentação")
        let a = try sut.addSubtask(parentID: parent.id, title: "A")
        let b = try sut.addSubtask(parentID: parent.id, title: "B")

        try await sut.completeTask(id: a.id)
        try await sut.completeTask(id: b.id)

        XCTAssertNil(try stored(parent.id).completedAt)
    }

    // MARK: makeSubtask (arrastar uma tarefa sobre a outra)

    func test_makeSubtask_tarefaDeTopoViraFilhaMantendoARaia() throws {
        let parent = try sut.addTask(title: "Apresentação")
        let task = try sut.addTask(title: "Esboço", tags: ["slides"])
        let lane = UUID()
        try sut.update(id: task.id) { $0.laneID = lane }
        let before = repo.saveCallCount

        let result = try sut.makeSubtask(id: task.id, parentID: parent.id)

        XCTAssertEqual(result?.parentID, parent.id)
        XCTAssertEqual(try stored(task.id).parentID, parent.id)
        XCTAssertEqual(try stored(task.id).laneID, lane)
        XCTAssertEqual(try stored(task.id).tags, ["slides"])
        XCTAssertEqual(repo.saveCallCount - before, 1)
    }

    func test_makeSubtask_filhaTrocaDePai() throws {
        let p1 = try sut.addTask(title: "P1")
        let p2 = try sut.addTask(title: "P2")
        let child = try sut.addSubtask(parentID: p1.id, title: "Filha")

        try sut.makeSubtask(id: child.id, parentID: p2.id)

        XCTAssertEqual(try stored(child.id).parentID, p2.id)
    }

    func test_makeSubtask_mesmoPai_naoGrava() throws {
        let parent = try sut.addTask(title: "P")
        let child = try sut.addSubtask(parentID: parent.id, title: "Filha")
        let before = repo.saveCallCount

        XCTAssertEqual(try sut.makeSubtask(id: child.id, parentID: parent.id)?.id, child.id)

        XCTAssertEqual(repo.saveCallCount, before)
    }

    func test_makeSubtask_tarefaQueJaEPai_lanca() throws {
        let parent = try sut.addTask(title: "Pai")
        try sut.addSubtask(parentID: parent.id, title: "Filha")
        let other = try sut.addTask(title: "Outra")
        let before = repo.saveCallCount

        XCTAssertThrowsError(try sut.makeSubtask(id: parent.id, parentID: other.id)) { error in
            XCTAssertEqual(error as? DomainError, .taskHasSubtasks)
        }
        XCTAssertNil(try stored(parent.id).parentID)
        XCTAssertEqual(repo.saveCallCount, before)
    }

    func test_makeSubtask_sobreSubtarefaOuSobreSiMesma_lanca() throws {
        let parent = try sut.addTask(title: "Pai")
        let child = try sut.addSubtask(parentID: parent.id, title: "Filha")
        let other = try sut.addTask(title: "Outra")

        XCTAssertThrowsError(try sut.makeSubtask(id: other.id, parentID: child.id)) { error in
            XCTAssertEqual(error as? DomainError, .subtaskNestingNotAllowed)
        }
        XCTAssertThrowsError(try sut.makeSubtask(id: other.id, parentID: other.id)) { error in
            XCTAssertEqual(error as? DomainError, .subtaskNestingNotAllowed)
        }
        XCTAssertNil(try stored(other.id).parentID)
    }

    func test_makeSubtask_paiInexistente_lanca_eTarefaInexistenteENoOp() throws {
        let task = try sut.addTask(title: "T")
        XCTAssertThrowsError(try sut.makeSubtask(id: task.id, parentID: UUID())) { error in
            XCTAssertEqual(error as? DomainError, .parentTaskNotFound)
        }
        XCTAssertNil(try sut.makeSubtask(id: UUID(), parentID: task.id))
    }

    func test_makeSubtask_duplicataEntreIrmasAtivasDoNovoPai_lanca() async throws {
        let parent = try sut.addTask(title: "Pai")
        try sut.addSubtask(parentID: parent.id, title: "Revisar")
        let active = try sut.addTask(title: " revisar ")
        XCTAssertThrowsError(try sut.makeSubtask(id: active.id, parentID: parent.id)) { error in
            XCTAssertEqual(error as? DomainError, .duplicateEntry("revisar"))
        }
        // Concluída não disputa título: entra sem checar duplicata.
        let done = try sut.addTask(title: "Revisar!")
        try sut.update(id: done.id) { $0.title = "Revisar" }
        try await sut.completeTask(id: done.id)
        XCTAssertNoThrow(try sut.makeSubtask(id: done.id, parentID: parent.id))
        XCTAssertEqual(try stored(done.id).parentID, parent.id)
    }

    func test_makeSubtask_tarefaAtivaSobPaiConcluido_reabreOPai() async throws {
        let parent = try sut.addTask(title: "Pai")
        try await sut.completeTask(id: parent.id)
        let task = try sut.addTask(title: "T")
        let before = repo.saveCallCount

        try sut.makeSubtask(id: task.id, parentID: parent.id)

        XCTAssertNil(try stored(parent.id).completedAt)
        XCTAssertEqual(repo.saveCallCount - before, 1)
    }

    /// Invariante "subtarefa ativa ⇒ pai ativo": filha ativa sob pai concluído ficaria invisível
    /// na lista (só aparece aninhada). Criar filha num pai concluído reabre o pai, numa gravação só.
    func test_addSubtask_paiConcluido_reabreOPai() async throws {
        let parent = try sut.addTask(title: "Apresentação")
        try await sut.completeTask(id: parent.id)
        let before = repo.saveCallCount

        let child = try sut.addSubtask(parentID: parent.id, title: "Nova")

        XCTAssertNil(try stored(parent.id).completedAt)
        XCTAssertNil(try stored(child.id).completedAt)
        XCTAssertEqual(repo.saveCallCount - before, 1)
    }

    func test_reopenTask_filha_reabreOPaiConcluido_eEspelhaOsDois() async throws {
        let sut = ManageTasksUseCase(tasks: repo, importer: importer, now: { self.now },
                                     shouldSyncReminderCompletion: { true })
        let parent = FocusTask(id: UUID(), title: "Pai", source: .reminders, reminderID: "r-pai", createdAt: now)
        try repo.saveTasks([parent])
        let child = try sut.addSubtask(parentID: parent.id, title: "Filha")
        try await sut.completeTask(id: parent.id)
        XCTAssertEqual(try stored(child.id).completedAt, now)
        let writesBefore = importer.completionWriteBacks.count
        let before = repo.saveCallCount

        let outcome = try await sut.reopenTask(id: child.id)

        XCTAssertNil(try stored(child.id).completedAt)
        XCTAssertNil(try stored(parent.id).completedAt, "filha ativa exige pai ativo")
        XCTAssertEqual(repo.saveCallCount - before, 1)
        XCTAssertEqual(outcome, .synced)
        let writes = importer.completionWriteBacks.dropFirst(writesBefore)
        XCTAssertEqual(writes.map(\.reminderID), ["r-pai"], "só o pai veio do Lembretes")
        XCTAssertEqual(writes.map(\.completed), [false])
    }

    func test_reopenTask_filha_comPaiAberto_naoTocaOPai() async throws {
        let parent = try sut.addTask(title: "Pai")
        let child = try sut.addSubtask(parentID: parent.id, title: "Filha")
        try await sut.completeTask(id: child.id)
        try sut.update(id: parent.id) { $0.laneID = UUID() }
        let parentBefore = try stored(parent.id)

        try await sut.reopenTask(id: child.id)

        XCTAssertEqual(try stored(parent.id), parentBefore)
    }

    func test_reopenTask_naoReabreFilhas() async throws {
        let parent = try sut.addTask(title: "Apresentação")
        let child = try sut.addSubtask(parentID: parent.id, title: "aberta")
        try await sut.completeTask(id: parent.id)

        try await sut.reopenTask(id: parent.id)

        XCTAssertNil(try stored(parent.id).completedAt)
        XCTAssertEqual(try stored(child.id).completedAt, now)
    }

    /// Pai diário fecha como qualquer outro (cascata nas filhas) e só ELE é clonado — o clone
    /// nasce sem filhas.
    func test_completeTask_paiDiario_fechaFilhasEClonaSoOPai() async throws {
        let parent = try sut.addTask(title: "Treino")
        try sut.setRepeatsDaily(id: parent.id, true)
        let child = try sut.addSubtask(parentID: parent.id, title: "alongar")

        try await sut.completeTask(id: parent.id)

        XCTAssertEqual(try stored(parent.id).completedAt, now)
        XCTAssertEqual(try stored(child.id).completedAt, now)
        XCTAssertEqual(repo.tasks.count, 3)
        let clone = try XCTUnwrap(repo.tasks.first { $0.id != parent.id && $0.title == "Treino" })
        XCTAssertNil(clone.parentID)
        XCTAssertTrue(TaskTree.children(of: clone.id, in: repo.tasks).isEmpty)
    }

    /// Filha diária fechada pela cascata do pai NÃO gera clone: o pai acabou, e um clone ativo
    /// ficaria sem pai ativo (invariante "subtarefa ativa ⇒ pai ativo").
    func test_completeTask_cascataNaoClonaFilhaDiaria() async throws {
        let parent = try sut.addTask(title: "Apresentação")
        let child = try sut.addSubtask(parentID: parent.id, title: "revisar notas")
        try sut.setRepeatsDaily(id: child.id, true)

        try await sut.completeTask(id: parent.id)

        XCTAssertEqual(try stored(child.id).completedAt, now)
        XCTAssertEqual(repo.tasks.count, 2)
    }

    func test_completeTask_idInexistente_naoGrava() async throws {
        try sut.addTask(title: "Intacta")
        let saves = repo.saveCallCount
        let outcome = try await sut.completeTask(id: UUID())
        XCTAssertEqual(outcome, .notApplicable)
        XCTAssertEqual(repo.saveCallCount, saves)
    }

    func test_deleteTask_cascataApagaFilhas_eFilhaSozinhaNaoApagaPai() throws {
        let parent = try sut.addTask(title: "Apresentação")
        let a = try sut.addSubtask(parentID: parent.id, title: "A")
        try sut.addSubtask(parentID: parent.id, title: "B")
        let outra = try sut.addTask(title: "Outra")

        try sut.deleteTask(id: a.id)
        XCTAssertEqual(repo.tasks.map(\.title), ["Apresentação", "B", "Outra"])

        try sut.deleteTask(id: parent.id)
        XCTAssertEqual(repo.tasks.map(\.id), [outra.id])
    }

    // MARK: cadastro de tags (RF-09.5 / item 1)

    func test_createTag_apareceEmAllTags_mesmoSemTarefa() throws {
        try sut.createTag("Faturamento")
        XCTAssertEqual(try sut.allTags(), ["Faturamento"])
    }

    func test_renameTag_trocaEmTodasAsTarefasENoCatalogo() throws {
        try sut.addTask(title: "A", tags: ["work"])
        try sut.addTask(title: "B", tags: ["work", "home"])
        try sut.renameTag(from: "work", to: "trabalho")
        let tags = try repo.loadTasks().flatMap(\.tags)
        XCTAssertFalse(tags.contains { $0.caseInsensitiveCompare("work") == .orderedSame })
        XCTAssertTrue(tags.contains("trabalho"))
        XCTAssertTrue(try sut.allTags().contains("trabalho"))
    }

    func test_deleteTag_removeDeTodasAsTarefas() throws {
        try sut.addTask(title: "A", tags: ["temp", "keep"])
        try sut.deleteTag("temp")
        XCTAssertEqual(try repo.loadTasks().first?.tags, ["keep"])
        XCTAssertFalse(try sut.allTags().contains("temp"))
    }

    // RF-09.15 — escopo por tag do seletor do foco acompanha rename/delete, como o do Kanban.
    func test_renameEDeleteTag_atualizamEscopoDoFoco() throws {
        let settings = InMemorySettingsRepository(
            configuration: PomodoroConfiguration(focusTaskScope: .tags(["Trabalho", "Casa"])))
        let sut = ManageTasksUseCase(tasks: repo, importer: importer, now: { self.now }, settings: settings)
        try sut.addTask(title: "A", tags: ["Trabalho", "Casa"])

        try sut.renameTag(from: "trabalho", to: "Job")
        XCTAssertEqual(settings.configuration.focusTaskScope, .tags(["Job", "Casa"]))

        try sut.deleteTag("Casa")
        try sut.deleteTag("Job")
        XCTAssertEqual(settings.configuration.focusTaskScope, .tags([]))
    }

    func test_renameTag_escopoDoFocoEmTodas_naoRegravaConfig() throws {
        let settings = InMemorySettingsRepository(configuration: PomodoroConfiguration(focusDuration: 50 * 60))
        let sut = ManageTasksUseCase(tasks: repo, importer: importer, now: { self.now }, settings: settings)
        try sut.addTask(title: "A", tags: ["x"])
        try sut.renameTag(from: "x", to: "y")
        XCTAssertEqual(settings.configuration.focusTaskScope, .all)
        XCTAssertEqual(settings.configuration.focusDuration, 50 * 60, "o resto da config fica intacto")
    }

    func test_addTask_tituloVazio_lanca() {
        XCTAssertThrowsError(try sut.addTask(title: "   ")) { error in
            XCTAssertEqual(error as? DomainError, .emptyTaskTitle)
        }
    }

    func test_addTask_tituloDuplicadoEntreAtivas_lancaIgnorandoCaixa() throws {
        try sut.addTask(title: "Estudar Swift")
        XCTAssertThrowsError(try sut.addTask(title: "estudar swift")) { error in
            XCTAssertEqual(error as? DomainError, .duplicateEntry("estudar swift"))
        }
    }

    /// Tarefa concluída libera o título para uma nova — repetir trabalho é o caso comum.
    func test_addTask_tituloIgualAoDeConcluida_permite() async throws {
        let done = try sut.addTask(title: "Reunião")
        try await sut.completeTask(id: done.id)
        XCTAssertNoThrow(try sut.addTask(title: "Reunião"))
    }

    // MARK: ciclo de vida

    func test_completeEReopen_alternamCompletedAt() async throws {
        let task = try sut.addTask(title: "Deploy")
        try await sut.completeTask(id: task.id)
        XCTAssertEqual(repo.tasks[0].completedAt, now)
        try await sut.reopenTask(id: task.id)
        XCTAssertNil(repo.tasks[0].completedAt)
    }

    func test_deleteTask_remove() throws {
        let task = try sut.addTask(title: "Apagar")
        try sut.deleteTask(id: task.id)
        XCTAssertTrue(repo.tasks.isEmpty)
    }

    func test_activeTasks_excluiConcluidasEOrdenaMaisRecentesPrimeiro() async throws {
        var tick = now
        sut = ManageTasksUseCase(tasks: repo, importer: importer, now: {
            tick = tick.addingTimeInterval(60); return tick
        })
        let old = try sut.addTask(title: "Antiga")
        let done = try sut.addTask(title: "Concluída")
        let recent = try sut.addTask(title: "Recente")
        try await sut.completeTask(id: done.id)

        XCTAssertEqual(try sut.activeTasks().map(\.id), [recent.id, old.id])
    }

    // MARK: importação do Lembretes

    func test_import_acessoNegado_devolveFalha() async {
        importer.accessGranted = false
        let result = await sut.importFromReminders()
        XCTAssertEqual(result.failure, .accessDenied)
        XCTAssertTrue(repo.tasks.isEmpty)
    }

    func test_import_criaTarefasComReminderID() async {
        importer.reminders = [
            ImportedReminder(reminderID: "r1", title: "Pagar boleto", listName: "Casa", isCompleted: false),
            ImportedReminder(reminderID: "r2", title: " Ligar dentista ", listName: "Saúde", isCompleted: false)
        ]
        let result = await sut.importFromReminders()

        XCTAssertEqual(result.importedTitles, ["Pagar boleto", "Ligar dentista"])
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(repo.tasks.map(\.reminderID), ["r1", "r2"])
        XCTAssertEqual(repo.tasks.map(\.source), [.reminders, .reminders])
    }

    func test_import_reimportarNaoDuplica() async {
        importer.reminders = [
            ImportedReminder(reminderID: "r1", title: "Pagar boleto", listName: "Casa", isCompleted: false)
        ]
        _ = await sut.importFromReminders()
        let second = await sut.importFromReminders()

        XCTAssertEqual(second.importedTitles, [])
        XCTAssertEqual(second.skippedCount, 1)
        XCTAssertEqual(repo.tasks.count, 1)
    }

    /// Concluída aqui e reimportada: não pode ressuscitar nem duplicar.
    func test_import_lembreteJaImportadoEConcluido_naoRessuscita() async throws {
        importer.reminders = [
            ImportedReminder(reminderID: "r1", title: "Pagar boleto", listName: "Casa", isCompleted: false)
        ]
        _ = await sut.importFromReminders()
        try await sut.completeTask(id: repo.tasks[0].id)

        let result = await sut.importFromReminders()
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(repo.tasks.count, 1)
        XCTAssertTrue(repo.tasks[0].isCompleted)
    }

    func test_import_tituloVazio_ehIgnoradoSemContarComoSkip() async {
        importer.reminders = [
            ImportedReminder(reminderID: "r1", title: "   ", listName: "Casa", isCompleted: false)
        ]
        let result = await sut.importFromReminders()
        XCTAssertEqual(result.importedTitles, [])
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertTrue(repo.tasks.isEmpty)
    }

    func test_import_falhaDeBusca_devolveFalha() async {
        importer.fetchError = NSError(domain: "ek", code: 1)
        let result = await sut.importFromReminders()
        if case .fetchFailed = result.failure {} else { XCTFail("esperava fetchFailed") }
    }

    // MARK: filtro por lista do Lembretes

    func test_import_semFiltro_pedeTodasAsListas() async {
        _ = await sut.importFromReminders()
        XCTAssertEqual(importer.fetchCallCount, 1)
        XCTAssertNil(importer.lastRequestedListIDs)
    }

    func test_import_comFiltro_repassaListasAoImporter() async {
        importer.reminders = [
            ImportedReminder(reminderID: "r1", title: "Só do trabalho", listName: "Trabalho", isCompleted: false)
        ]
        let result = await sut.importFromReminders(fromLists: ["cal-1", "cal-2"])

        XCTAssertEqual(importer.lastRequestedListIDs, ["cal-1", "cal-2"])
        XCTAssertEqual(result.importedTitles, ["Só do trabalho"])
    }

    func test_import_comFiltro_dedupContinuaValendo() async {
        importer.reminders = [
            ImportedReminder(reminderID: "r1", title: "Repetida", listName: "Trabalho", isCompleted: false)
        ]
        _ = await sut.importFromReminders(fromLists: ["cal-1"])
        let second = await sut.importFromReminders(fromLists: ["cal-1"])
        XCTAssertEqual(second.skippedCount, 1)
        XCTAssertEqual(repo.tasks.count, 1)
    }

    func test_loadReminderLists_devolveListas() async {
        importer.lists = [
            ReminderList(id: "cal-1", title: "Trabalho"),
            ReminderList(id: "cal-2", title: "Casa")
        ]
        let result = await sut.loadReminderLists()
        XCTAssertEqual(try? result.get(), importer.lists)
    }

    func test_loadReminderLists_acessoNegado() async {
        importer.accessGranted = false
        let result = await sut.loadReminderLists()
        if case .failure(.accessDenied) = result {} else { XCTFail("esperava accessDenied") }
    }

    func test_loadReminderLists_falhaDeBusca() async {
        importer.listsError = NSError(domain: "ek", code: 2)
        let result = await sut.loadReminderLists()
        if case .failure(.fetchFailed) = result {} else { XCTFail("esperava fetchFailed") }
    }

    // MARK: picker — carregar lembretes importáveis

    func test_loadImportableReminders_devolveLembretes() async {
        importer.reminders = [
            ImportedReminder(reminderID: "r1", title: "Pagar boleto", listName: "Casa", isCompleted: false)
        ]
        let result = await sut.loadImportableReminders()
        XCTAssertEqual(try? result.get().map(\.reminderID), ["r1"])
        XCTAssertNil(importer.lastRequestedListIDs)
    }

    func test_loadImportableReminders_acessoNegado() async {
        importer.accessGranted = false
        let result = await sut.loadImportableReminders()
        if case .failure(.accessDenied) = result {} else { XCTFail("esperava accessDenied") }
    }

    // MARK: picker — importar um lembrete

    func test_importReminder_criaTarefaComCamposRicos() async {
        let due = Date(timeIntervalSince1970: 2_000_000)
        let reminder = ImportedReminder(
            reminderID: "r1", title: "  Pagar boleto  ", listName: "Casa", isCompleted: false,
            notes: "conta de luz", dueDate: due, priority: 1, url: "https://banco.example/boleto"
        )
        let result = await sut.importReminder(reminder)

        XCTAssertEqual(result.importedTitles, ["Pagar boleto"])
        XCTAssertEqual(repo.tasks.count, 1)
        let task = repo.tasks[0]
        XCTAssertEqual(task.title, "Pagar boleto")
        XCTAssertEqual(task.source, .reminders)
        XCTAssertEqual(task.reminderID, "r1")
        XCTAssertEqual(task.notes, "conta de luz")
        XCTAssertEqual(task.dueDate, due)
        XCTAssertEqual(task.priority, 1)
        XCTAssertEqual(task.sourceURL, "https://banco.example/boleto")
    }

    func test_importReminder_prioridadeZeroViraNil() async {
        let reminder = ImportedReminder(
            reminderID: "r1", title: "Sem prioridade", listName: "Casa", isCompleted: false, priority: 0
        )
        _ = await sut.importReminder(reminder)
        XCTAssertNil(repo.tasks[0].priority)
    }

    func test_importReminder_tituloVazio_naoCria() async {
        let reminder = ImportedReminder(reminderID: "r1", title: "   ", listName: "Casa", isCompleted: false)
        let result = await sut.importReminder(reminder)
        XCTAssertEqual(result.importedTitles, [])
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertTrue(repo.tasks.isEmpty)
    }

    func test_importReminder_jaImportado_naoDuplicaEContaSkip() async {
        let reminder = ImportedReminder(reminderID: "r1", title: "Repetida", listName: "Casa", isCompleted: false)
        _ = await sut.importReminder(reminder)
        let second = await sut.importReminder(reminder)
        XCTAssertEqual(second.skippedCount, 1)
        XCTAssertEqual(second.importedTitles, [])
        XCTAssertEqual(repo.tasks.count, 1)
    }

    // MARK: sincronização de conclusão de volta no Lembretes

    /// Cria um use case com o toggle de sync ligado.
    private func makeSyncingSUT() -> ManageTasksUseCase {
        ManageTasksUseCase(tasks: repo, importer: importer, now: { self.now },
                           shouldSyncReminderCompletion: { true })
    }

    func test_completeTask_reminderComSyncLigado_escreveDeVolta() async throws {
        sut = makeSyncingSUT()
        let reminder = ImportedReminder(reminderID: "r1", title: "Boleto", listName: "Casa", isCompleted: false)
        _ = await sut.importReminder(reminder)
        try await sut.completeTask(id: repo.tasks[0].id)

        XCTAssertEqual(importer.completionWriteBacks.count, 1)
        XCTAssertEqual(importer.completionWriteBacks.first?.reminderID, "r1")
        XCTAssertEqual(importer.completionWriteBacks.first?.completed, true)
    }

    func test_reopenTask_reminderComSyncLigado_escreveDeVoltaFalse() async throws {
        sut = makeSyncingSUT()
        let reminder = ImportedReminder(reminderID: "r1", title: "Boleto", listName: "Casa", isCompleted: false)
        _ = await sut.importReminder(reminder)
        try await sut.completeTask(id: repo.tasks[0].id)
        try await sut.reopenTask(id: repo.tasks[0].id)

        XCTAssertEqual(importer.completionWriteBacks.last?.completed, false)
    }

    func test_completeTask_tarefaManual_naoEscreveNoLembretes() async throws {
        sut = makeSyncingSUT()
        let task = try sut.addTask(title: "Manual")
        try await sut.completeTask(id: task.id)
        XCTAssertTrue(importer.completionWriteBacks.isEmpty)
    }

    func test_completeTask_syncDesligado_naoEscreve() async throws {
        // `sut` padrão do setUp tem o toggle default `false`.
        let reminder = ImportedReminder(reminderID: "r1", title: "Boleto", listName: "Casa", isCompleted: false)
        _ = await sut.importReminder(reminder)
        try await sut.completeTask(id: repo.tasks[0].id)
        XCTAssertTrue(importer.completionWriteBacks.isEmpty)
    }

    func test_completeTask_falhaDeEscrita_naoDesfazConclusaoLocal() async throws {
        sut = makeSyncingSUT()
        importer.setCompletedResult = false  // lembrete apagado no app Lembretes
        let reminder = ImportedReminder(reminderID: "r1", title: "Boleto", listName: "Casa", isCompleted: false)
        _ = await sut.importReminder(reminder)
        let outcome = try await sut.completeTask(id: repo.tasks[0].id)

        XCTAssertTrue(repo.tasks[0].isCompleted)  // conclusão local persiste mesmo assim
        XCTAssertEqual(importer.completionWriteBacks.count, 1)
        XCTAssertEqual(outcome, .failed, "a UI precisa poder avisar que o Lembretes não mudou")
    }

    func test_completeTask_devolveOutcomeDoEspelhamento() async throws {
        sut = makeSyncingSUT()
        let reminder = ImportedReminder(reminderID: "r1", title: "Boleto", listName: "Casa", isCompleted: false)
        _ = await sut.importReminder(reminder)

        let synced = try await sut.completeTask(id: repo.tasks[0].id)
        XCTAssertEqual(synced, .synced)

        let manual = try sut.addTask(title: "Manual")
        let notApplicable = try await sut.completeTask(id: manual.id)
        XCTAssertEqual(notApplicable, .notApplicable, "tarefa manual não tem o que espelhar")
    }

    /// Lembrete recorrente: concluída a ocorrência local, o picker pode trazer a próxima.
    /// A tarefa concluída fica onde está (histórico), a nova entra com `id` próprio.
    func test_importReminder_concluidaPodeSerReimportada() async throws {
        let reminder = ImportedReminder(reminderID: "r1", title: "Boleto", listName: "Casa", isCompleted: false)
        _ = await sut.importReminder(reminder)
        let first = repo.tasks[0]
        try await sut.completeTask(id: first.id)

        let result = await sut.importReminder(reminder)

        XCTAssertEqual(result.importedTitles, ["Boleto"])
        XCTAssertEqual(repo.tasks.count, 2)
        XCTAssertEqual(repo.tasks.filter { !$0.isCompleted }.count, 1)
        XCTAssertNotEqual(repo.tasks[1].id, first.id, "reimportação é tarefa nova, não ressurreição")
        XCTAssertEqual(repo.tasks[1].reminderID, "r1")
    }

    /// A reimportação leva os dados ATUAIS do lembrete — num recorrente a data sempre muda, e a
    /// tarefa nova não pode nascer com o vencimento da ocorrência passada. A concluída não muda.
    func test_importReminder_reimportacaoUsaOsDadosAtuaisDoLembrete() async throws {
        let ontem = Date(timeIntervalSince1970: 1_000_000)
        let amanha = Date(timeIntervalSince1970: 1_086_400)
        let antiga = ImportedReminder(
            reminderID: "r1", title: "Boleto", listName: "Casa", isCompleted: false,
            notes: "parcela 1", dueDate: ontem, priority: 9, url: "https://banco.example/1")
        _ = await sut.importReminder(antiga)
        try await sut.completeTask(id: repo.tasks[0].id)

        let atual = ImportedReminder(
            reminderID: "r1", title: "Boleto", listName: "Casa", isCompleted: false,
            notes: "parcela 2", dueDate: amanha, priority: 1, url: "https://banco.example/2")
        _ = await sut.importReminder(atual)

        let nova = try XCTUnwrap(repo.tasks.first { !$0.isCompleted })
        XCTAssertEqual(nova.dueDate, amanha)
        XCTAssertEqual(nova.notes, "parcela 2")
        XCTAssertEqual(nova.priority, 1)
        XCTAssertEqual(nova.sourceURL, "https://banco.example/2")

        let concluida = try XCTUnwrap(repo.tasks.first(where: \.isCompleted))
        XCTAssertEqual(concluida.dueDate, ontem, "histórico da ocorrência anterior fica intacto")
    }

    /// Com a tarefa ATIVA na lista, o mesmo lembrete continua barrado — senão um clique a mais
    /// no picker duplicaria a tarefa em aberto.
    func test_importReminder_comTarefaAtiva_naoDuplica() async {
        let reminder = ImportedReminder(reminderID: "r1", title: "Boleto", listName: "Casa", isCompleted: false)
        _ = await sut.importReminder(reminder)

        let result = await sut.importReminder(reminder)

        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(repo.tasks.count, 1)
    }

    /// O lote não segue a regra do picker: sem escolha item a item, reimportar tudo traria de
    /// volta cada tarefa já concluída por aqui.
    func test_importFromReminders_emLote_naoRessuscitaConcluida() async throws {
        let reminder = ImportedReminder(reminderID: "r1", title: "Boleto", listName: "Casa", isCompleted: false)
        _ = await sut.importReminder(reminder)
        try await sut.completeTask(id: repo.tasks[0].id)
        importer.reminders = [reminder]

        let result = await sut.importFromReminders()

        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(repo.tasks.count, 1)
    }
}
