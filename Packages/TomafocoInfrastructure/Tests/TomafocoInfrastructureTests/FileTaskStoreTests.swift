import XCTest
import TomafocoDomain
@testable import TomafocoInfrastructure

final class FileTaskStoreTests: XCTestCase {

    private var dir: URL!
    private var sut: FileTaskStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tomafoco-tasks-\(UUID().uuidString)", isDirectory: true)
        sut = FileTaskStore(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        try super.tearDownWithError()
    }

    private func makeTask(title: String) -> FocusTask {
        FocusTask(id: UUID(), title: title, source: .manual,
                  createdAt: Date(timeIntervalSince1970: 1_000_000))
    }

    func test_semArquivo_devolveVazio() throws {
        XCTAssertEqual(try sut.loadTasks(), [])
    }

    func test_roundtrip_preservaTarefas() throws {
        let tasks = [makeTask(title: "A"), makeTask(title: "B")]
        try sut.saveTasks(tasks)
        XCTAssertEqual(try sut.loadTasks(), tasks)
    }

    func test_arquivoCorrompido_viraBakEDevolveVazio() throws {
        let url = dir.appendingPathComponent("tasks.json")
        try Data("{{{ lixo".utf8).write(to: url)

        XCTAssertEqual(try sut.loadTasks(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("tasks.json.bak").path))
    }

    /// JSON antigo sem campos novos que venham a existir não pode virar .bak por engano:
    /// campos opcionais decodificam. (Regressão do formato mínimo atual.)
    func test_jsonSemCamposOpcionais_decodifica() throws {
        let json = """
        [{"id":"00000000-0000-0000-0000-0000000000AA","title":"Antiga",
          "source":"manual","createdAt":"2026-07-20T09:00:00Z"}]
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("tasks.json"))
        let tasks = try sut.loadTasks()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertNil(tasks[0].reminderID)
        XCTAssertNil(tasks[0].completedAt)
    }
}
