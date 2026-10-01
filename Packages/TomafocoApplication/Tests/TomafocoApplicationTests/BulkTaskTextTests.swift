import XCTest
@testable import TomafocoApplication

final class BulkTaskTextTests: XCTestCase {

    func test_parseTitles_umaTarefaPorLinha_ignoraVaziasETrima() {
        let text = "  Revisar PR  \n\n   \nPagar boleto\n"
        XCTAssertEqual(BulkTaskText.parseTitles(text), ["Revisar PR", "Pagar boleto"])
    }

    func test_parseTitles_aceitaCRLFeCR() {
        XCTAssertEqual(BulkTaskText.parseTitles("A\r\nB\rC"), ["A", "B", "C"])
    }

    func test_parseTitles_removeMarcadoresDeLista() {
        let text = """
        - Hífen
        * Asterisco
        • Bolinha
        - [ ] Checkbox
        [x] Marcado
        1. Numerada
        12) Parêntese
        """
        XCTAssertEqual(BulkTaskText.parseTitles(text),
                       ["Hífen", "Asterisco", "Bolinha", "Checkbox", "Marcado", "Numerada", "Parêntese"])
    }

    /// Só tira marcador seguido de espaço — "-5 kg" e "2024 metas" são conteúdo.
    func test_parseTitles_naoMexeEmConteudoParecidoComMarcador() {
        XCTAssertEqual(BulkTaskText.parseTitles("-5 kg\n2024 metas\n3.5 horas"),
                       ["-5 kg", "2024 metas", "3.5 horas"])
    }

    func test_parseTitles_linhaSoComMarcador_eDescartada() {
        XCTAssertEqual(BulkTaskText.parseTitles("- \n* \nTarefa"), ["Tarefa"])
    }

    func test_parseTitles_mantemDuplicatas() {
        XCTAssertEqual(BulkTaskText.parseTitles("A\nA"), ["A", "A"])
    }
}
