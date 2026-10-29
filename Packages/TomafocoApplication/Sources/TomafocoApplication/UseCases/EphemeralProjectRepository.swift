import Foundation
import TomafocoDomain

/// Projetos em memória — padrão do `ManageTasksUseCase` quando nenhum store é injetado (testes
/// antigos, que não usam projeto). Vazio de propósito: esquecer de injetar o store real faz
/// qualquer vínculo com projeto falhar com `projectNotFound` — erro visível, não `projectID`
/// pendurado em silêncio. O app real injeta o store do banco (Infrastructure).
@MainActor
public final class EphemeralProjectRepository: ProjectRepository {
    private var projects: [Project]

    public nonisolated init(projects: [Project] = []) {
        self.projects = projects
    }

    public func loadProjects() throws -> [Project] { projects }

    public func project(id: UUID) throws -> Project? { projects.first { $0.id == id } }

    public func upsert(_ project: Project) throws {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        } else {
            projects.append(project)
        }
    }

    public func delete(id: UUID) throws {
        projects.removeAll { $0.id == id }
    }
}
