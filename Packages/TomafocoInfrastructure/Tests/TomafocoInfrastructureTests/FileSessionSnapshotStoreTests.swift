import XCTest
import TomafocoDomain
@testable import TomafocoInfrastructure

/// Persistência do failsafe e do histórico contra diretório temporário — sem tocar em
/// Application Support de verdade.
final class FileSessionSnapshotStoreTests: XCTestCase {

    private var directory: URL!
    private var store: FileSessionSnapshotStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tomafoco-tests-\(UUID().uuidString)", isDirectory: true)
        store = FileSessionSnapshotStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func record(cycle: Int = 1) -> SessionRecord {
        SessionRecord(
            sessionID: UUID(), phase: .focus,
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            endedAt: Date(timeIntervalSince1970: 1_001_500),
            outcome: .completed, cycleNumber: cycle, taskID: nil
        )
    }

    // MARK: - Sessão ativa (failsafe)

    func test_saveELoad_daSessaoAtiva_fazemRoundTrip() throws {
        let session = PomodoroSession(
            id: UUID(), phase: .focus,
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            endsAt: Date(timeIntervalSince1970: 1_001_500),
            reason: "código", cycleNumber: 2, taskID: nil
        )

        try store.saveActive(session)
        let loaded = try store.loadActive()

        XCTAssertEqual(loaded, session)
    }

    func test_clearActive_semSessao_ehNoOp() throws {
        XCTAssertNoThrow(try store.clearActive())
        XCTAssertNil(try store.loadActive())
    }

    // MARK: - Histórico

    func test_appendToHistory_acumulaRegistros() throws {
        try store.appendToHistory(record(cycle: 1))
        try store.appendToHistory(record(cycle: 2))

        let history = try store.loadHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.map(\.cycleNumber), [1, 2])
    }

    /// Um history.json corrompido não pode ser apagado em silêncio: vira .bak para diagnóstico
    /// e o histórico recomeça — o registro novo nunca se perde.
    func test_historicoCorrompido_ehPreservadoComoBakEAppendNaoSePerde() throws {
        let historyURL = directory.appendingPathComponent("history.json")
        let backupURL = directory.appendingPathComponent("history.json.bak")
        let corrupted = Data("{ lixo que não decodifica ]".utf8)
        try corrupted.write(to: historyURL)

        try store.appendToHistory(record(cycle: 7))

        XCTAssertEqual(try Data(contentsOf: backupURL), corrupted,
                       "o arquivo corrompido deveria ter sido preservado intacto como .bak")
        let history = try store.loadHistory()
        XCTAssertEqual(history.map(\.cycleNumber), [7])
    }
}
