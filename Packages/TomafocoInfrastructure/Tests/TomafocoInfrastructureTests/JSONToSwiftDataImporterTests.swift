import XCTest
import TomafocoDomain
@testable import TomafocoInfrastructure

/// Migração JSON → banco (FEAT-006, P5): importa tudo, renomeia os arquivos, é idempotente,
/// aguenta arquivo corrompido e formato antigo.
@MainActor
final class JSONToSwiftDataImporterTests: XCTestCase {

    private var dir: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var database: TomafocoDatabase!
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tomafoco-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        suiteName = "tomafoco-import-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        database = try TomafocoDatabase.inMemory()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeImporter(database: TomafocoDatabase? = nil) -> JSONToSwiftDataImporter {
        let db = database ?? self.database!
        return JSONToSwiftDataImporter(
            database: db, tasks: SwiftDataTaskStore(database: db), sessions: SwiftDataSessionStore(database: db),
            tags: SwiftDataTagCatalog(database: db), directory: dir,
            legacyTags: UserDefaultsTagCatalog(defaults: defaults), now: { self.now },
            allowInMemory: db.isInMemory)
    }

    private func file(_ name: String) -> URL { dir.appendingPathComponent(name) }
    private func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: file(name).path) }

    private func task(_ title: String) -> FocusTask {
        FocusTask(id: UUID(), title: title, source: .manual, createdAt: Date(timeIntervalSince1970: 1_000))
    }

    private func seedEverything() throws -> (tasks: [FocusTask], board: KanbanBoard, history: [SessionRecord], active: PomodoroSession) {
        let tasks = [task("A"), task("B")]
        try FileTaskStore(directory: dir).saveTasks(tasks)
        let board = KanbanBoard.makeDefault(makeID: { UUID() })
        try FileKanbanStore(directory: dir).saveBoard(board)
        let sessions = FileSessionSnapshotStore(directory: dir)
        let history = [
            SessionRecord(sessionID: UUID(), phase: .focus, startedAt: Date(timeIntervalSince1970: 100),
                          endedAt: Date(timeIntervalSince1970: 200), outcome: .completed, cycleNumber: 1, taskIDs: []),
            SessionRecord(sessionID: UUID(), phase: .shortBreak, startedAt: Date(timeIntervalSince1970: 200),
                          endedAt: Date(timeIntervalSince1970: 300), outcome: .skipped, cycleNumber: 1, taskIDs: [])
        ]
        try history.forEach { try sessions.appendToHistory($0) }
        let active = PomodoroSession(id: UUID(), phase: .focus, startedAt: Date(timeIntervalSince1970: 400),
                                     endsAt: Date(timeIntervalSince1970: 1_900), cycleNumber: 2, taskIDs: [])
        try sessions.saveActive(active)
        UserDefaultsTagCatalog(defaults: defaults).saveTags(["órfã", "Trabalho"])
        return (tasks, board, history, active)
    }

    func test_importaTudo_eRenomeiaOsArquivos() throws {
        let seeded = try seedEverything()

        let report = try makeImporter().run()

        XCTAssertEqual(report.tasks, 2)
        XCTAssertEqual(report.sessions, 2)
        XCTAssertEqual(report.tags, 2)
        XCTAssertTrue(report.importedBoard)
        XCTAssertTrue(report.importedActiveSession)
        XCTAssertEqual(report.unreadableFiles, [])

        // ISO 8601 dos arquivos guarda segundos inteiros — as datas das fixtures também.
        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks(), seeded.tasks)
        XCTAssertEqual(try SwiftDataKanbanStore(database: database).loadBoard(), seeded.board)
        XCTAssertEqual(try SwiftDataSessionStore(database: database).loadHistory(), seeded.history)
        XCTAssertEqual(try SwiftDataSessionStore(database: database).loadActive(), seeded.active)
        XCTAssertEqual(SwiftDataTagCatalog(database: database).loadTags(), ["órfã", "Trabalho"])

        for name in JSONToSwiftDataImporter.fileNames {
            XCTAssertFalse(exists(name), name)
            XCTAssertTrue(exists(name + ".migrated"), name)
        }
        XCTAssertEqual(UserDefaultsTagCatalog(defaults: defaults).loadTags(), ["órfã", "Trabalho"],
                       "catálogo antigo fica como cópia de recuperação")
    }

    /// Achado do review: com o app no banco em memória (disco indisponível), importar renomearia
    /// os JSON sem salvar nada — o próximo lançamento abriria vazio.
    func test_bancoEmMemoria_naoImporta_eNaoMexeNosArquivos() throws {
        _ = try seedEverything()
        let importer = JSONToSwiftDataImporter(
            database: database, tasks: SwiftDataTaskStore(database: database),
            sessions: SwiftDataSessionStore(database: database), tags: SwiftDataTagCatalog(database: database),
            directory: dir, legacyTags: UserDefaultsTagCatalog(defaults: defaults), now: { self.now })
        XCTAssertThrowsError(try importer.run()) {
            XCTAssertEqual($0 as? JSONToSwiftDataImporter.ImportError, .databaseNotPersistent)
        }
        XCTAssertTrue(exists("tasks.json"))
        XCTAssertFalse(exists("tasks.json.migrated"))
    }

    /// Banco recriado: as tags órfãs voltam do UserDefaults junto com os `.migrated`.
    func test_bancoRecriado_recuperaTagsDoCatalogoAntigo() throws {
        let storeURL = dir.appendingPathComponent("db/Tomafoco.store")
        _ = try seedEverything()
        try makeImporter(database: try TomafocoDatabase.open(at: storeURL, retryDelay: 0)).run()
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: storeURL.path + suffix) }
        try Data("lixo".utf8).write(to: storeURL)
        let recreated = try TomafocoDatabase.open(at: storeURL, retryDelay: 0)
        try makeImporter(database: recreated).run()
        XCTAssertEqual(SwiftDataTagCatalog(database: recreated).loadTags(), ["órfã", "Trabalho"])
    }

    func test_segundaExecucao_naoFazNada() throws {
        _ = try seedEverything()
        try makeImporter().run()
        // Um JSON novo aparecendo depois (ex.: versão antiga aberta por engano) não reimporta.
        try FileTaskStore(directory: dir).saveTasks([task("Fantasma")])

        let report = try makeImporter().run()

        XCTAssertTrue(report.skipped)
        XCTAssertEqual(try SwiftDataTaskStore(database: database).loadTasks().map(\.title), ["A", "B"])
    }

    func test_instalacaoNova_soGravaMeta() throws {
        let report = try makeImporter().run()
        XCTAssertEqual(report, JSONToSwiftDataImporter.Report())
        XCTAssertNotNil(try database.singleton(SingletonKey.storeMeta))
        XCTAssertTrue(try makeImporter().run().skipped)
    }

    /// `tasks.json` de versão antiga (sem os campos novos) entra com os valores padrão.
    func test_formatoAntigo_importaComPadroes() throws {
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","title":"Antiga","source":"manual","createdAt":"2026-07-22T10:00:00Z"}]
        """
        try Data(json.utf8).write(to: file("tasks.json"))

        try makeImporter().run()

        let imported = try XCTUnwrap(try SwiftDataTaskStore(database: database).task(id: id))
        XCTAssertEqual(imported.title, "Antiga")
        XCTAssertEqual(imported.tags, [])
        XCTAssertEqual(imported.history, [])
        XCTAssertNil(imported.laneID)
        XCTAssertNil(imported.parentID)
    }

    func test_arquivoCorrompido_viraBak_eORestoImporta() throws {
        _ = try seedEverything()
        try Data("{{{ lixo".utf8).write(to: file("history.json"))
        try Data("{{{ lixo".utf8).write(to: file("tasks.json"))

        let report = try makeImporter().run()

        XCTAssertEqual(Set(report.unreadableFiles), ["history.json", "tasks.json"])
        XCTAssertTrue(exists("history.json.bak"))
        XCTAssertTrue(exists("tasks.json.bak"))
        XCTAssertEqual(report.tasks, 0)
        XCTAssertEqual(report.sessions, 0)
        XCTAssertTrue(report.importedBoard)
        XCTAssertTrue(report.importedActiveSession)
    }

    /// Achado do review: `tasks.json` ilegível já virou `.bak` numa tentativa que falhou depois;
    /// a repetição precisa avisar mesmo sem ver o arquivo original.
    func test_bakDeTentativaAnterior_entraNoAviso() throws {
        try Data("{{{ lixo".utf8).write(to: file("tasks.json.bak"))
        let report = try makeImporter().run()
        XCTAssertEqual(report.unreadableFiles, ["tasks.json"])
        XCTAssertEqual(report.tasks, 0)
    }

    /// Achado do review: o banco migrado sumiu (tentativa anterior renomeou e falhou ao criar o
    /// novo; `wasReset` morreu com o processo). Banco novo + `.migrated` no disco → recupera.
    func test_bancoNovoSemMeta_recuperaDosMigratedSemFlagDeReset() throws {
        _ = try seedEverything()
        try makeImporter().run()
        XCTAssertTrue(exists("tasks.json.migrated"))

        let fresh = try TomafocoDatabase.inMemory()
        XCTAssertFalse(fresh.wasReset)
        let report = try makeImporter(database: fresh).run()

        XCTAssertEqual(report.tasks, 2)
        XCTAssertEqual(report.sessions, 2)
        XCTAssertEqual(try SwiftDataTaskStore(database: fresh).loadTasks().map(\.title), ["A", "B"])
        XCTAssertTrue(exists("tasks.json.migrated"))
        XCTAssertFalse(exists("tasks.json"))
    }

    /// Banco recriado depois da migração: relê os `.migrated` em vez de abrir vazio.
    func test_bancoRecriado_recuperaDosMigrated() throws {
        let dbDir = dir.appendingPathComponent("db", isDirectory: true)
        let storeURL = dbDir.appendingPathComponent("Tomafoco.store")
        _ = try seedEverything()
        try makeImporter(database: try TomafocoDatabase.open(at: storeURL, retryDelay: 0)).run()
        XCTAssertTrue(exists("tasks.json.migrated"))

        // Corrompe o banco: a próxima abertura recria e o importador recupera.
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: storeURL.path + suffix) }
        try Data("lixo".utf8).write(to: storeURL)
        let recreated = try TomafocoDatabase.open(at: storeURL, retryDelay: 0)
        XCTAssertTrue(recreated.wasReset)

        let report = try makeImporter(database: recreated).run()

        XCTAssertEqual(report.tasks, 2)
        XCTAssertEqual(try SwiftDataTaskStore(database: recreated).loadTasks().map(\.title), ["A", "B"])
        XCTAssertFalse(exists("tasks.json"))
        XCTAssertTrue(exists("tasks.json.migrated"))
    }
}
