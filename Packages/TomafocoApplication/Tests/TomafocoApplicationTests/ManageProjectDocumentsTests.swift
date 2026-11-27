import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

/// Documentos dos projetos (FEAT-009 / RF-09.20): vários por projeto, com título; apagar o
/// projeto apaga os documentos na mesma transação.
@MainActor
final class ManageProjectDocumentsTests: XCTestCase {

    private var projectRepo: InMemoryProjectRepository!
    private var documentRepo: InMemoryProjectDocumentRepository!
    private var now: Date!
    private var sut: ManageProjectDocumentsUseCase!
    private var project: Project!

    private struct Boom: Error {}

    override func setUp() async throws {
        projectRepo = InMemoryProjectRepository()
        documentRepo = InMemoryProjectDocumentRepository()
        now = Date(timeIntervalSince1970: 1_900_000_000)
        sut = ManageProjectDocumentsUseCase(documents: documentRepo, projects: projectRepo, now: { self.now })
        project = Project(id: UUID(), title: "Site", createdAt: now)
        try projectRepo.upsert(project)
    }

    private func later() { now = now.addingTimeInterval(60) }

    func test_create_documentoVazioComTitulo_tituloEmBrancoViraSemTitulo() throws {
        let spec = try sut.create(projectID: project.id, title: "  Especificação ")
        let blank = try sut.create(projectID: project.id, title: " ")
        XCTAssertEqual(spec.title, "Especificação")
        XCTAssertEqual(spec.markdown, "")
        XCTAssertEqual(spec.createdAt, now)
        XCTAssertEqual(blank.title, "Sem título")
        XCTAssertEqual(try sut.document(id: spec.id), spec)
    }

    func test_create_projetoInexistente_lanca() {
        XCTAssertThrowsError(try sut.create(projectID: UUID(), title: "X")) {
            XCTAssertEqual($0 as? DomainError, .projectNotFound)
        }
        XCTAssertTrue(documentRepo.documents.isEmpty)
    }

    func test_documents_soDoProjeto_ordenadosPorTituloNatural() throws {
        let other = Project(id: UUID(), title: "Outro", createdAt: now)
        try projectRepo.upsert(other)
        try sut.create(projectID: project.id, title: "Ata 10")
        try sut.create(projectID: project.id, title: "Ata 2")
        try sut.create(projectID: other.id, title: "Alheio")
        XCTAssertEqual(try sut.documents(projectID: project.id).map(\.title), ["Ata 2", "Ata 10"])
    }

    func test_save_gravaTexto_igualNaoRegrava_brancoContinuaExistindo() throws {
        let doc = try sut.create(projectID: project.id, title: "Spec")
        later()
        XCTAssertEqual(try sut.save(id: doc.id, markdown: "# Spec"), .saved(updatedAt: now))
        let saves = documentRepo.saveCount
        later()
        XCTAssertEqual(try sut.save(id: doc.id, markdown: "# Spec"), .unchanged)
        XCTAssertEqual(documentRepo.saveCount, saves)
        XCTAssertEqual(try sut.save(id: doc.id, markdown: "   "), .saved(updatedAt: now))
        XCTAssertEqual(try sut.document(id: doc.id)?.markdown, "   ", "em branco não apaga")
    }

    func test_save_acimaDoLimite_lanca() throws {
        let doc = try sut.create(projectID: project.id, title: "Spec")
        let big = String(repeating: "a", count: TaskDocument.maxByteCount + 1)
        XCTAssertThrowsError(try sut.save(id: doc.id, markdown: big)) {
            XCTAssertEqual($0 as? DomainError, .documentTooLarge(maxBytes: TaskDocument.maxByteCount))
        }
    }

    func test_save_documentoOuProjetoApagado_naoGrava() throws {
        let doc = try sut.create(projectID: project.id, title: "Spec")
        XCTAssertEqual(try sut.save(id: UUID(), markdown: "x"), .documentNotFound)
        try projectRepo.delete(id: project.id)
        XCTAssertEqual(try sut.save(id: doc.id, markdown: "x"), .documentNotFound)
        XCTAssertEqual(try sut.document(id: doc.id)?.markdown, "")
    }

    func test_rename_normaliza_eMesmoTituloNaoGrava() throws {
        let doc = try sut.create(projectID: project.id, title: "Spec")
        let saves = documentRepo.saveCount
        XCTAssertEqual(try sut.rename(id: doc.id, title: " Spec "), doc)
        XCTAssertEqual(documentRepo.saveCount, saves)
        later()
        let renamed = try XCTUnwrap(try sut.rename(id: doc.id, title: "Escopo"))
        XCTAssertEqual(renamed.title, "Escopo")
        XCTAssertEqual(renamed.updatedAt, now)
        XCTAssertNil(try sut.rename(id: UUID(), title: "X"))
    }

    func test_delete() throws {
        let doc = try sut.create(projectID: project.id, title: "Spec")
        try sut.delete(id: doc.id)
        XCTAssertNil(try sut.document(id: doc.id))
    }

    // MARK: - Apagar projeto

    func test_deleteProject_apagaDocumentosDoProjetoNaTransacao() throws {
        let taskRepo = InMemoryTaskRepository()
        let unitOfWork = InMemoryUnitOfWork(tasks: taskRepo, projects: projectRepo, projectDocuments: documentRepo)
        let projects = ManageProjectsUseCase(projects: projectRepo, tasks: taskRepo, unitOfWork: unitOfWork,
                                             now: { self.now }, projectDocuments: documentRepo)
        let other = Project(id: UUID(), title: "Outro", createdAt: now)
        try projectRepo.upsert(other)
        try sut.create(projectID: project.id, title: "A")
        try sut.create(projectID: project.id, title: "B")
        let kept = try sut.create(projectID: other.id, title: "C")
        XCTAssertEqual(try projects.documentCount(of: project.id), 2)

        try projects.deleteProject(id: project.id)

        XCTAssertEqual(Array(documentRepo.documents.keys), [kept.id])
    }

    func test_deleteProject_falhaNoMeio_documentosVoltam() throws {
        let taskRepo = InMemoryTaskRepository()
        let unitOfWork = InMemoryUnitOfWork(tasks: taskRepo, projects: projectRepo, projectDocuments: documentRepo)
        let projects = ManageProjectsUseCase(projects: projectRepo, tasks: taskRepo, unitOfWork: unitOfWork,
                                             now: { self.now }, projectDocuments: documentRepo)
        let doc = try sut.create(projectID: project.id, title: "A")
        projectRepo.saveError = Boom()

        XCTAssertThrowsError(try projects.deleteProject(id: project.id))

        XCTAssertNotNil(documentRepo.documents[doc.id])
    }
}
