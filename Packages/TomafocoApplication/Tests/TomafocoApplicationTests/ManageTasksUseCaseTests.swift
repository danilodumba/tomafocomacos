import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

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
            notes: "  falar com o time  ", dueDate: due, priority: .medium
        )
        XCTAssertEqual(edited?.title, "Relatório final")
        let stored = try XCTUnwrap(try repo.loadTasks().first)
        XCTAssertEqual(stored.title, "Relatório final")
        XCTAssertEqual(stored.tags, ["Trabalho"])
        XCTAssertEqual(stored.notes, "falar com o time")
        XCTAssertEqual(stored.dueDate, due)
        XCTAssertEqual(stored.priority, 5)
    }

    func test_editTask_notasEmBrancoViramNil_eDataPodeSerLimpa() throws {
        let task = try sut.addTask(title: "Boleto")
        try sut.editTask(id: task.id, title: "Boleto", tags: [], notes: "pagar",
                         dueDate: Date(timeIntervalSince1970: 3_000), priority: .high)
        try sut.editTask(id: task.id, title: "Boleto", tags: [], notes: "   ",
                         dueDate: nil, priority: .none)
        let stored = try XCTUnwrap(try repo.loadTasks().first)
        XCTAssertNil(stored.notes)
        XCTAssertNil(stored.dueDate)
        XCTAssertNil(stored.priority)
    }

    func test_editTask_tituloVazio_lanca() throws {
        let task = try sut.addTask(title: "Algo")
        XCTAssertThrowsError(
            try sut.editTask(id: task.id, title: "   ", tags: [], notes: nil,
                             dueDate: nil, priority: .none)
        ) { XCTAssertEqual($0 as? DomainError, .emptyTaskTitle) }
    }

    func test_editTask_tituloDeOutraAtiva_lancaDuplicata() throws {
        try sut.addTask(title: "Existente")
        let task = try sut.addTask(title: "Outra")
        XCTAssertThrowsError(
            try sut.editTask(id: task.id, title: "existente", tags: [], notes: nil,
                             dueDate: nil, priority: .none)
        ) { XCTAssertEqual($0 as? DomainError, .duplicateEntry("existente")) }
    }

    // Salvar sem mexer no título não pode acusar duplicata contra a própria tarefa.
    func test_editTask_mesmoTitulo_naoAcusaDuplicata() throws {
        let task = try sut.addTask(title: "Manter")
        XCTAssertNoThrow(
            try sut.editTask(id: task.id, title: "Manter", tags: ["x"], notes: nil,
                             dueDate: nil, priority: .low)
        )
    }

    func test_editTask_idInexistente_devolveNilSemGravar() throws {
        try sut.addTask(title: "Intacta")
        let result = try sut.editTask(id: UUID(), title: "Nova", tags: [], notes: nil,
                                      dueDate: nil, priority: .none)
        XCTAssertNil(result)
        XCTAssertEqual(try repo.loadTasks().first?.title, "Intacta")
    }

    func test_editTask_tagsEntramNoCatalogo() throws {
        let task = try sut.addTask(title: "A")
        try sut.editTask(id: task.id, title: "A", tags: ["Faturamento"], notes: nil,
                         dueDate: nil, priority: .none)
        try sut.deleteTask(id: task.id)
        XCTAssertEqual(try sut.allTags(), ["Faturamento"])
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
