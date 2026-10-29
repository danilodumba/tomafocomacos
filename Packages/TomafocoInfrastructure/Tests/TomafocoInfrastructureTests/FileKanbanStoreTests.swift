import XCTest
import TomafocoDomain
@testable import TomafocoInfrastructure

@MainActor
final class FileKanbanStoreTests: XCTestCase {

    private var dir: URL!
    private var sut: FileKanbanStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tomafoco-kanban-\(UUID().uuidString)", isDirectory: true)
        sut = FileKanbanStore(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        try super.tearDownWithError()
    }

    func test_semArquivo_devolveNil() throws {
        XCTAssertNil(try sut.loadBoard())
    }

    func test_roundtrip_preservaQuadro() throws {
        var board = KanbanBoard.makeDefault(makeID: { UUID() })
        board.doneRetentionDays = 3
        board.taskScope = .tags(["Trabalho"])
        try sut.saveBoard(board)
        XCTAssertEqual(try sut.loadBoard(), board)
    }

    func test_arquivoCorrompido_viraBakEDevolveNil() throws {
        let url = dir.appendingPathComponent("kanban.json")
        try Data("{{{ lixo".utf8).write(to: url)

        XCTAssertNil(try sut.loadBoard())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("kanban.json.bak").path))
    }
}
