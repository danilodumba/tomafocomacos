import XCTest
@testable import TomafocoDomain

/// Escopo por tag do quadro Kanban (FEAT-005) e do seletor do foco (RF-09.15).
final class TaskScopeTests: XCTestCase {

    private func task(_ tags: [String], parentID: UUID? = nil) -> FocusTask {
        FocusTask(id: UUID(), title: "T", source: .manual, createdAt: Date(timeIntervalSince1970: 0),
                  tags: tags, parentID: parentID)
    }

    func test_includesIn_subtarefaHerdaOEscopoDoPai() {
        let scope = TaskScope.tags(["Trabalho"])
        let parent = task(["Trabalho"])
        let child = task([], parentID: parent.id)
        let orphan = task([], parentID: UUID())
        let all = [parent, child, orphan]
        XCTAssertTrue(scope.includes(child, in: all), "filha sem tag entra pelo pai")
        XCTAssertFalse(scope.includes(orphan, in: all), "pai fora da lista não ajuda")
        XCTAssertFalse(scope.includes(child, in: [child]), "sem o pai na lista, só a própria tag conta")
        XCTAssertTrue(scope.includes(task(["trabalho"], parentID: UUID()), in: []), "tag própria basta")
    }

    func test_all_incluiTudo() {
        XCTAssertTrue(TaskScope.all.includes(task([])))
        XCTAssertTrue(TaskScope.all.includes(task(["x"])))
    }

    func test_tags_casaPorQualquerTag_semCaixa() {
        let scope = TaskScope.tags(["Trabalho", "Estudo"])
        XCTAssertTrue(scope.includes(task(["estudo"])))
        XCTAssertTrue(scope.includes(task(["casa", "TRABALHO"])))
        XCTAssertFalse(scope.includes(task(["casa"])))
        XCTAssertFalse(scope.includes(task([])))
    }

    func test_tagsVazio_naoIncluiNada() {
        XCTAssertFalse(TaskScope.tags([]).includes(task(["x"])))
    }

    func test_renamingTag_atualizaSelecao_semMexerEmAll() {
        XCTAssertEqual(TaskScope.tags(["Trabalho", "Casa"]).renamingTag(from: "trabalho", to: "Job"),
                       .tags(["Job", "Casa"]))
        XCTAssertEqual(TaskScope.all.renamingTag(from: "a", to: "b"), .all)
    }

    func test_removingTag_ultimaTagContinuaNoModoTags() {
        XCTAssertEqual(TaskScope.tags(["Trabalho"]).removingTag("TRABALHO"), .tags([]))
        XCTAssertEqual(TaskScope.all.removingTag("x"), .all)
    }

    // MARK: - Edição nas Configurações (quadro e foco compartilham)

    func test_isByTagEContains_semCaixa_eAllNaoContemNada() {
        XCTAssertTrue(TaskScope.tags([]).isByTag)
        XCTAssertFalse(TaskScope.all.isByTag)
        XCTAssertTrue(TaskScope.tags(["Trabalho"]).contains("TRABALHO"))
        XCTAssertFalse(TaskScope.tags(["Trabalho"]).contains("Casa"))
        XCTAssertFalse(TaskScope.all.contains("Trabalho"))
    }

    func test_selectableTags_uneConhecidasEMarcadas_semDuplicata_ordenadas() {
        XCTAssertEqual(TaskScope.tags(["Zeta", "trabalho"]).selectableTags(knownTags: ["Casa", "Trabalho"]),
                       ["Casa", "Trabalho", "Zeta"])
        XCTAssertEqual(TaskScope.all.selectableTags(knownTags: ["b", "a"]), ["a", "b"])
    }

    func test_settingTag_marcaDesmarcaSemCaixa_eNormaliza() {
        let scope = TaskScope.tags(["Trabalho"])
        XCTAssertEqual(scope.settingTag("Casa", selected: true), .tags(["Trabalho", "Casa"]))
        XCTAssertEqual(scope.settingTag("TRABALHO", selected: false), .tags([]))
        XCTAssertEqual(scope.settingTag("trabalho", selected: true), .tags(["trabalho"]), "remarcar troca a grafia, sem duplicar")
        XCTAssertEqual(TaskScope.all.settingTag(" x ", selected: true), .tags(["x"]), "a partir de 'todas' entra no modo por tag")
    }

    func test_switchingByTag_nilQuandoJaEstaNoModo() {
        XCTAssertEqual(TaskScope.all.switchingByTag(true), .tags([]))
        XCTAssertEqual(TaskScope.tags(["a"]).switchingByTag(false), .all)
        XCTAssertNil(TaskScope.all.switchingByTag(false))
        XCTAssertNil(TaskScope.tags(["a"]).switchingByTag(true))
    }

    func test_codable_roundtrip_eModoDesconhecidoViraAll() throws {
        for scope in [TaskScope.all, .tags(["a", "b"]), .tags([])] {
            XCTAssertEqual(try JSONDecoder().decode(TaskScope.self, from: JSONEncoder().encode(scope)), scope)
        }
        let unknown = #"{"mode":"futuro"}"#
        XCTAssertEqual(try JSONDecoder().decode(TaskScope.self, from: Data(unknown.utf8)), .all)
    }
}
