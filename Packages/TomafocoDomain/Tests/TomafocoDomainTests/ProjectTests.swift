import XCTest
@testable import TomafocoDomain

/// Projetos (FEAT-006): modelo, decode tolerante, filtro e o vínculo na tarefa.
final class ProjectTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    }

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func project(due: Date? = nil) -> Project {
        Project(id: UUID(), title: "P", createdAt: date(1), dueDate: due)
    }

    func test_isOverdue_porDia() {
        XCTAssertFalse(project().isOverdue(now: date(29), calendar: calendar))
        XCTAssertFalse(project(due: date(29, 0)).isOverdue(now: date(29, 23), calendar: calendar), "o próprio dia não venceu")
        XCTAssertTrue(project(due: date(28, 23)).isOverdue(now: date(29, 0), calendar: calendar))
        XCTAssertFalse(project(due: date(30)).isOverdue(now: date(29), calendar: calendar))
    }

    func test_normalizeTitle_trim() {
        XCTAssertEqual(Project.normalizeTitle("  Site novo \n"), "Site novo")
    }

    func test_roundTrip() throws {
        let original = Project(id: UUID(), title: "Site", createdAt: date(1), dueDate: date(30),
                               color: .purple, icon: "briefcase", details: "linha 1\nlinha 2")
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    /// Versão futura com cor nova ou sem campos opcionais não pode derrubar a leitura.
    func test_decodeTolerante_corDesconhecida_eCamposAusentes() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","title":"X","createdAt":0,"color":"turquesa"}
        """
        let decoded = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.color, .cyan)
        XCTAssertEqual(decoded.icon, Project.defaultIcon)
        XCTAssertNil(decoded.dueDate)
        XCTAssertNil(decoded.details)
    }

    // MARK: - Filtro

    private func task(project: UUID?) -> FocusTask {
        FocusTask(id: UUID(), title: "T", source: .manual, createdAt: date(1), projectID: project)
    }

    func test_filtro() {
        let p = UUID()
        let comProjeto = task(project: p), outro = task(project: UUID()), sem = task(project: nil)
        XCTAssertTrue([comProjeto, outro, sem].allSatisfy(ProjectFilter.all.matches))
        XCTAssertEqual([comProjeto, outro, sem].filter(ProjectFilter.none.matches), [sem])
        XCTAssertEqual([comProjeto, outro, sem].filter(ProjectFilter.project(p).matches), [comProjeto])
    }

    func test_filtro_projetoDaNovaTarefa() {
        let p = UUID()
        XCTAssertEqual(ProjectFilter.project(p).projectIDForNewTask, p)
        XCTAssertNil(ProjectFilter.none.projectIDForNewTask)
        XCTAssertNil(ProjectFilter.all.projectIDForNewTask)
    }

    // MARK: - Tarefa

    func test_tarefaSemProjetoNoJSON_decodificaNil() throws {
        let json = """
        {"id":"\(UUID().uuidString)","title":"Antiga","source":"manual","createdAt":0}
        """
        XCTAssertNil(try JSONDecoder().decode(FocusTask.self, from: Data(json.utf8)).projectID)
    }

    func test_tarefa_roundTripComProjeto() throws {
        let original = task(project: UUID())
        XCTAssertEqual(try JSONDecoder().decode(FocusTask.self, from: JSONEncoder().encode(original)), original)
    }

    func test_cloneDaDiaria_levaOProjeto() {
        var diaria = task(project: UUID())
        diaria.repeatsDaily = true
        let clone = diaria.nextDailyOccurrence(id: UUID(), now: date(29), calendar: calendar)
        XCTAssertEqual(clone.projectID, diaria.projectID)
    }
}
