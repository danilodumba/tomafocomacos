import Foundation
import TomafocoDomain

/// Relatório de um projeto (FEAT-006 / RF-10.7): as tarefas **pai** do projeto com o tempo de foco
/// de cada uma no período e o total do projeto.
public struct ProjectReport: Equatable {
    public struct Row: Equatable, Identifiable {
        public let id: UUID
        public let title: String
        /// Foco da tarefa + das subtarefas dela (o mesmo roll-up do relatório geral), contando
        /// UMA vez a sessão em que pai e filha (ou duas filhas) estavam juntos.
        public let focusTime: TimeInterval
        public let sessionCount: Int
        public let subtaskCount: Int
        public let isCompleted: Bool

        public init(id: UUID, title: String, focusTime: TimeInterval, sessionCount: Int,
                    subtaskCount: Int, isCompleted: Bool) {
            self.id = id
            self.title = title
            self.focusTime = focusTime
            self.sessionCount = sessionCount
            self.subtaskCount = subtaskCount
            self.isCompleted = isCompleted
        }
    }

    public let project: Project
    /// Mais tempo primeiro; empate por título. Inclui tarefas sem foco no período (tempo zero):
    /// o relatório é "o que o projeto tem e quanto custou", não só "o que teve foco".
    public let rows: [Row]
    /// Tempo real do projeto: cada sessão conta **uma vez**, mesmo que tenha focado duas tarefas
    /// do projeto juntas (foco multi-tarefa). Por isso pode ser menor que a soma das linhas.
    public let focusTotal: TimeInterval
    public let sessionCount: Int

    /// A soma das linhas passa do total quando há sessão com várias tarefas do projeto.
    public var rowsSum: TimeInterval { rows.reduce(0) { $0 + $1.focusTime } }

    public init(project: Project, rows: [Row], focusTotal: TimeInterval, sessionCount: Int) {
        self.project = project
        self.rows = rows
        self.focusTotal = focusTotal
        self.sessionCount = sessionCount
    }
}

extension ReportBuilder {

    /// Relatório do projeto (RF-10.7). Só tarefas **de topo** (pai) entram como linha; o foco das
    /// subtarefas soma no pai. Período pelo início da sessão, como o resto dos relatórios.
    public static func projectReport(
        project: Project,
        records: [SessionRecord],
        tasks: [FocusTask],
        interval: DateInterval?
    ) -> ProjectReport {
        let parents = tasks.filter { $0.projectID == project.id && !$0.isSubtask }
        let parentIDs = Set(parents.map(\.id))
        // Tarefa (pai ou filha) → pai do projeto a que o foco dela pertence.
        var ownerByTask: [UUID: UUID] = [:]
        var subtaskCount: [UUID: Int] = [:]
        for parent in parents { ownerByTask[parent.id] = parent.id }
        for task in tasks {
            guard let parentID = task.parentID, parentIDs.contains(parentID) else { continue }
            ownerByTask[task.id] = parentID
            subtaskCount[parentID, default: 0] += 1
        }

        var timeByParent: [UUID: TimeInterval] = [:]
        var sessionsByParent: [UUID: Int] = [:]
        var total: TimeInterval = 0
        var totalSessions = 0
        for record in records where record.phase == .focus && (interval?.contains(record.startedAt) ?? true) {
            let owners = Set(record.taskIDs.compactMap { ownerByTask[$0] })
            guard !owners.isEmpty else { continue }
            let dur = max(0, record.endedAt.timeIntervalSince(record.startedAt))
            for owner in owners {
                timeByParent[owner, default: 0] += dur
                sessionsByParent[owner, default: 0] += 1
            }
            total += dur
            totalSessions += 1
        }

        let rows = parents
            .map { parent in
                ProjectReport.Row(
                    id: parent.id, title: parent.title,
                    focusTime: timeByParent[parent.id] ?? 0,
                    sessionCount: sessionsByParent[parent.id] ?? 0,
                    subtaskCount: subtaskCount[parent.id] ?? 0,
                    isCompleted: parent.isCompleted)
            }
            .sorted { lhs, rhs in
                if lhs.focusTime != rhs.focusTime { return lhs.focusTime > rhs.focusTime }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        return ProjectReport(project: project, rows: rows, focusTotal: total, sessionCount: totalSessions)
    }
}
