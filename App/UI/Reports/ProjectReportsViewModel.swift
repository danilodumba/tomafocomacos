import Foundation
import TomafocoDomain
import TomafocoApplication

/// Relatório de projetos (FEAT-006 / RF-10.7): período + projeto escolhido → tarefas pai com o
/// tempo de foco e o total do projeto. A agregação é do `ReportBuilder.projectReport` (puro);
/// aqui só há seleção, formatação e o PDF.
@MainActor
final class ProjectReportsViewModel: ObservableObject {

    @Published var period: ReportPeriod = .month {
        didSet { rebuild() }
    }
    @Published private(set) var projects: [Project] = []
    @Published var selectedProjectID: UUID? {
        didSet { rebuild() }
    }
    @Published private(set) var report: ProjectReport?
    /// PDF gerado para a pré-visualização — `nil` = sheet fechado.
    @Published var pdfPreview: ProjectReportPDFDocument?
    @Published var feedback: String?

    private let sessions: SessionRepository
    private let tasks: TaskRepository
    private let manageProjects: ManageProjectsUseCase
    private let calendar = Calendar.current
    /// Snapshot lido no `reload()` — trocar período/projeto recalcula sem reler o banco.
    private var loadedRecords: [SessionRecord] = []
    private var loadedTasks: [FocusTask] = []

    init(sessions: SessionRepository, tasks: TaskRepository, manageProjects: ManageProjectsUseCase) {
        self.sessions = sessions
        self.tasks = tasks
        self.manageProjects = manageProjects
    }

    var selectedProject: Project? {
        selectedProjectID.flatMap { id in projects.first { $0.id == id } }
    }

    func reload() {
        feedback = nil
        do {
            loadedRecords = try sessions.loadHistory()
            loadedTasks = try tasks.loadTasks()
            projects = try manageProjects.allProjects()
        } catch {
            feedback = "Não foi possível ler os dados: \(error.localizedDescription)"
        }
        // Projeto apagado sai da seleção; sem seleção, abre no primeiro (lista por título).
        if selectedProject == nil { selectedProjectID = projects.first?.id } else { rebuild() }
    }

    private func rebuild() {
        report = selectedProject.map { project in
            ReportBuilder.projectReport(
                project: project, records: loadedRecords, tasks: loadedTasks,
                interval: period.interval(now: Date(), calendar: calendar))
        }
    }

    // MARK: - PDF

    func showPDF() {
        guard let report else { return }
        let data = ProjectReportPDF.render(report, period: period, generatedAt: Date())
        pdfPreview = ProjectReportPDFDocument(data: data, fileName: pdfFileName(for: report.project))
    }

    /// "tomafoco-projeto-<título>.pdf".
    private func pdfFileName(for project: Project) -> String {
        let slug = project.title.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "tomafoco-projeto-\(slug.isEmpty ? "relatorio" : slug).pdf"
    }

    // MARK: - Formatação

    /// "2h 10min" — o mesmo formato do relatório de tarefas.
    static func formatDuration(_ interval: TimeInterval) -> String {
        ReportsViewModel.formatDuration(interval)
    }

    /// "2,17 h" — horas decimais para quem cobra/aponta por hora.
    static func formatDecimalHours(_ interval: TimeInterval) -> String {
        decimalHoursFormatter.string(from: NSNumber(value: interval / 3_600)).map { "\($0) h" } ?? ""
    }

    private static let decimalHoursFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

/// PDF pronto para a pré-visualização (`.sheet(item:)`).
struct ProjectReportPDFDocument: Identifiable {
    let id = UUID()
    let data: Data
    let fileName: String
}
