import XCTest
@testable import TomafocoDomain

/// Retrocompatibilidade do vínculo com tarefa (RF-09): snapshots e histórico gravados ANTES
/// do campo `taskID` precisam decodificar com `nil` — sem migração e sem perder dados.
final class TaskLinkCodingTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func test_sessionRecordAntigoSemTaskID_decodificaVazio() throws {
        let json = """
        {"sessionID":"00000000-0000-0000-0000-0000000000AA","phase":"focus",
         "startedAt":"2026-07-20T09:00:00Z","endedAt":"2026-07-20T09:25:00Z",
         "outcome":"completed","cycleNumber":1}
        """
        let record = try decoder.decode(SessionRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.taskIDs, [])
        XCTAssertEqual(record.outcome, .completed)
    }

    func test_pomodoroSessionAntigaSemTaskID_decodificaVazio() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000AA","phase":"focus",
         "startedAt":"2026-07-20T09:00:00Z","endsAt":"2026-07-20T09:25:00Z",
         "cycleNumber":1}
        """
        let session = try decoder.decode(PomodoroSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.taskIDs, [])
    }

    /// Migração da chave singular `taskID` (antes do foco multi-tarefa) para o array `taskIDs`.
    func test_sessionComTaskIDSingular_migraParaArray() throws {
        let single = "00000000-0000-0000-0000-0000000000CC"
        let sessionJSON = """
        {"id":"00000000-0000-0000-0000-0000000000AA","phase":"focus",
         "startedAt":"2026-07-20T09:00:00Z","endsAt":"2026-07-20T09:25:00Z",
         "cycleNumber":1,"taskID":"\(single)"}
        """
        let session = try decoder.decode(PomodoroSession.self, from: Data(sessionJSON.utf8))
        XCTAssertEqual(session.taskIDs, [UUID(uuidString: single)!])

        let recordJSON = """
        {"sessionID":"00000000-0000-0000-0000-0000000000AA","phase":"focus",
         "startedAt":"2026-07-20T09:00:00Z","endedAt":"2026-07-20T09:25:00Z",
         "outcome":"completed","cycleNumber":1,"taskID":"\(single)"}
        """
        let record = try decoder.decode(SessionRecord.self, from: Data(recordJSON.utf8))
        XCTAssertEqual(record.taskIDs, [UUID(uuidString: single)!])
    }

    func test_focusTaskAntigaSemTags_decodificaComListaVazia() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000AA","title":"Deploy",
         "source":"manual","createdAt":"2026-07-20T09:00:00Z"}
        """
        let task = try decoder.decode(FocusTask.self, from: Data(json.utf8))
        XCTAssertEqual(task.tags, [])
    }

    func test_focusTaskInit_normalizaTags() {
        let task = FocusTask(
            id: UUID(), title: "T", source: .manual,
            createdAt: Date(timeIntervalSince1970: 0),
            tags: [" a ", "A", "", "b"]
        )
        XCTAssertEqual(task.tags, ["a", "b"])
    }

    func test_focusTaskAntigaSemCamposRicos_decodificaComNil() throws {
        // JSON gravado antes de notes/dueDate/priority/sourceURL — todos devem virar nil.
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000AA","title":"Deploy",
         "source":"reminders","reminderID":"r1","createdAt":"2026-07-20T09:00:00Z","tags":[]}
        """
        let task = try decoder.decode(FocusTask.self, from: Data(json.utf8))
        XCTAssertNil(task.notes)
        XCTAssertNil(task.dueDate)
        XCTAssertNil(task.priority)
        XCTAssertNil(task.sourceURL)
    }

    func test_focusTaskRoundtripComCamposRicos_preserva() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let due = Date(timeIntervalSince1970: 2_000_000)
        let task = FocusTask(
            id: UUID(), title: "Boleto", source: .reminders, reminderID: "r1",
            createdAt: Date(timeIntervalSince1970: 0),
            notes: "conta", dueDate: due, priority: 3, sourceURL: "https://x.example"
        )
        let decoded = try decoder.decode(FocusTask.self, from: encoder.encode(task))
        XCTAssertEqual(decoded.notes, "conta")
        XCTAssertEqual(decoded.dueDate, due)
        XCTAssertEqual(decoded.priority, 3)
        XCTAssertEqual(decoded.sourceURL, "https://x.example")
    }

    func test_focusTaskRoundtripComTags_preserva() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let task = FocusTask(
            id: UUID(), title: "T", source: .manual,
            createdAt: Date(timeIntervalSince1970: 0), tags: ["x", "y"]
        )
        let decoded = try decoder.decode(FocusTask.self, from: encoder.encode(task))
        XCTAssertEqual(decoded.tags, ["x", "y"])
    }

    // MARK: - Histórico (FEAT-001)

    /// `tasks.json` gravado antes da FEAT-001 não tem a chave `history` — decodificar tem que
    /// dar lista vazia, nunca lançar (decode que lança viraria `tasks.json.bak` e o usuário
    /// abriria o app sem tarefa nenhuma).
    func test_focusTaskAntigaSemHistorico_decodificaComListaVazia() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-0000000000AA","title":"Deploy",
         "source":"manual","createdAt":"2026-07-20T09:00:00Z","tags":["x"]}
        """
        let task = try decoder.decode(FocusTask.self, from: Data(json.utf8))
        XCTAssertEqual(task.history, [])
    }

    func test_focusTaskRoundtripComHistorico_preserva() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let entries = [
            TaskHistoryEntry(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_000), text: "liguei"),
            TaskHistoryEntry(id: UUID(), createdAt: Date(timeIntervalSince1970: 2_000), text: "retorno")
        ]
        let task = FocusTask(
            id: UUID(), title: "Cliente", source: .manual,
            createdAt: Date(timeIntervalSince1970: 0), history: entries
        )
        let decoded = try decoder.decode(FocusTask.self, from: encoder.encode(task))
        XCTAssertEqual(decoded.history, entries)
    }

    func test_roundtripComTaskIDs_preserva() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let taskIDs = [UUID(), UUID()]
        let record = SessionRecord(
            sessionID: UUID(), phase: .focus,
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            endedAt: Date(timeIntervalSince1970: 1_001_500),
            outcome: .completed, cycleNumber: 1, taskIDs: taskIDs
        )
        let decoded = try decoder.decode(SessionRecord.self, from: encoder.encode(record))
        XCTAssertEqual(decoded.taskIDs, taskIDs)
    }
}
