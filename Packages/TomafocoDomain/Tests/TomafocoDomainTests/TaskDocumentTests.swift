import XCTest
@testable import TomafocoDomain

final class TaskDocumentTests: XCTestCase {

    func test_validated_textoEmBrancoViraNil() throws {
        XCTAssertNil(try TaskDocument.validated(""))
        XCTAssertNil(try TaskDocument.validated("   \n\t\n  "))
    }

    func test_validated_preservaOTextoComoDigitado() throws {
        let text = "  # Título\n\n    código recuado\n"
        XCTAssertEqual(try TaskDocument.validated(text), text)
    }

    func test_validated_acimaDoLimiteLanca() {
        let big = String(repeating: "a", count: TaskDocument.maxByteCount + 1)
        XCTAssertThrowsError(try TaskDocument.validated(big)) { error in
            XCTAssertEqual(error as? DomainError, .documentTooLarge(maxBytes: TaskDocument.maxByteCount))
        }
    }

    func test_validated_limiteContaBytesUTF8() throws {
        // "é" ocupa 2 bytes: metade do limite em caracteres já estoura.
        let accented = String(repeating: "é", count: TaskDocument.maxByteCount / 2 + 1)
        XCTAssertThrowsError(try TaskDocument.validated(accented))
        let exact = String(repeating: "a", count: TaskDocument.maxByteCount)
        XCTAssertEqual(try TaskDocument.validated(exact), exact)
    }

    func test_wordCount() {
        let doc = TaskDocument(taskID: UUID(), markdown: "# Plano\n\n- [ ] item um\n- dois", updatedAt: .init())
        XCTAssertEqual(doc.wordCount, 9)
    }

    func test_codable_idaEVolta() throws {
        let doc = TaskDocument(taskID: UUID(), markdown: "**oi**", updatedAt: Date(timeIntervalSince1970: 1_000))
        let data = try JSONEncoder().encode(doc)
        XCTAssertEqual(try JSONDecoder().decode(TaskDocument.self, from: data), doc)
    }

    func test_identityChecklistResetter_naoMexe() {
        XCTAssertEqual(IdentityChecklistResetter().uncheckingAll("- [x] a"), "- [x] a")
    }
}
