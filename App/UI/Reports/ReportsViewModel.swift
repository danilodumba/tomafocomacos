import Foundation
import SwiftUI
import TomafocoDomain
import TomafocoApplication

/// ViewModel da aba Relatórios (RF-10). Lê histórico + tarefas e delega a agregação
/// ao `ReportBuilder` puro — aqui só há seleção de período e formatação.
@MainActor
final class ReportsViewModel: ObservableObject {

    enum Period: String, CaseIterable, Identifiable {
        case today = "Hoje"
        case week = "7 dias"
        case month = "30 dias"
        case all = "Tudo"
        var id: String { rawValue }
    }

    @Published var period: Period = .week {
        didSet { reload() }
    }
    @Published private(set) var report: FocusReport?
    /// Tarefas concluídas NO PERÍODO (fonte para a lista e o CSV), antes de busca/tag.
    /// Uma linha por conclusão — tarefa diária (FEAT-004) aparece uma vez por dia concluído.
    @Published private(set) var completedAll: [CompletedTaskOccurrence] = []
    /// Tarefas com foco no período, na ordem das `taskTotals` — opções do relatório por tarefa.
    @Published private(set) var taskOptions: [TaskOption] = []
    /// Tarefa escolhida para o relatório por tarefa (RF-10.6); `nil` = seção recolhida.
    @Published var selectedTaskID: UUID? {
        didSet { rebuildTaskReport() }
    }
    @Published private(set) var taskReport: TaskReport?
    /// Todas as tags conhecidas — alimenta o filtro por tag.
    @Published private(set) var knownTags: [String] = []
    /// Busca por título e filtro por tag da lista de concluídas (item 3).
    @Published var searchText = ""
    @Published var tagFilter: String?

    struct TaskOption: Identifiable, Equatable {
        let id: UUID
        let title: String
    }

    private let sessions: SessionRepository
    private let tasks: TaskRepository
    private let calendar = Calendar.current
    /// Último snapshot lido — o relatório por tarefa é recalculado a partir dele ao trocar a
    /// seleção, sem reler o disco.
    private var loadedRecords: [SessionRecord] = []
    private var loadedTasks: [FocusTask] = []

    init(sessions: SessionRepository, tasks: TaskRepository) {
        self.sessions = sessions
        self.tasks = tasks
    }

    func reload() {
        let records = (try? sessions.loadHistory()) ?? []
        let allTasks = (try? tasks.loadTasks()) ?? []
        let interval = interval(for: period)
        loadedRecords = records
        loadedTasks = allTasks
        let built = ReportBuilder.build(
            records: records, tasks: allTasks,
            interval: interval, now: Date(), calendar: calendar)
        report = built
        // Conclusões recortadas pelo mesmo período do resto — "Hoje" tem que mostrar só o que
        // foi concluído hoje.
        completedAll = CompletedTaskOccurrence.occurrences(of: allTasks).filter { occurrence in
            occurrence.task.completedAt.map { interval?.contains($0) ?? true } ?? false
        }
        let existing = Set(allTasks.map(\.id))
        taskOptions = built.taskTotals.compactMap { total in
            total.taskID.flatMap { existing.contains($0) ? TaskOption(id: $0, title: total.title) : nil }
        }
        // Seleção que saiu do período (ou foi apagada) é limpa — o menu não a mostraria mais.
        if let selected = selectedTaskID, !taskOptions.contains(where: { $0.id == selected }) {
            selectedTaskID = nil
        } else {
            rebuildTaskReport()
        }
        knownTags = allTasks.flatMap(\.tags).reduce(into: [String]()) { acc, tag in
            if !acc.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { acc.append(tag) }
        }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Concluídas após busca por título e filtro por tag.
    var completedTasks: [CompletedTaskOccurrence] {
        var list = completedAll
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            list = list.filter { $0.task.title.localizedCaseInsensitiveContains(query) }
        }
        if let tag = tagFilter {
            list = list.filter { $0.task.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        }
        return list
    }

    private func rebuildTaskReport() {
        taskReport = selectedTaskID.flatMap {
            ReportBuilder.taskReport(taskID: $0, records: loadedRecords, tasks: loadedTasks,
                                     interval: interval(for: period), calendar: calendar)
        }
    }

    var selectedTaskTitle: String? {
        selectedTaskID.flatMap { id in taskOptions.first { $0.id == id }?.title }
    }

    /// Entradas de histórico do período (FEAT-001) — recorte só por período; busca e filtro de
    /// tag valem para a lista de concluídas, não para o histórico.
    var historyEntries: [FocusReport.HistoryItem] { report?.historyEntries ?? [] }

    /// CSV das tarefas concluídas filtradas (item 3). Datas formatadas em pt-BR.
    func csv() -> String {
        ReportCSVExporter.completedTasksCSV(
            tasks: completedTasks.map(\.task),
            report: report ?? FocusReport(taskTotals: [], dailyTotals: [], summary: emptySummary()),
            dateString: { Self.csvDateFormatter.string(from: $0) })
    }

    /// CSV do histórico das tarefas no período (FEAT-001).
    func historyCSV() -> String {
        ReportCSVExporter.taskHistoryCSV(
            entries: historyEntries,
            dateString: { Self.csvDateFormatter.string(from: $0) })
    }

    /// CSV das sessões da tarefa selecionada (RF-10.6); vazio sem seleção.
    func taskSessionsCSV() -> String {
        guard let taskReport else { return "" }
        return ReportCSVExporter.taskSessionsCSV(
            report: taskReport,
            dateString: { Self.csvDateFormatter.string(from: $0) })
    }

    /// Nome de arquivo sugerido para o CSV da tarefa: "tomafoco-tarefa-<título>.csv".
    func taskSessionsCSVFileName() -> String {
        let raw = taskReport?.title ?? "tarefa"
        let slug = raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "tomafoco-tarefa-\(slug.isEmpty ? "sessoes" : slug).csv"
    }

    /// Formatador dos CSVs — um só para todos os exports.
    private static let csvDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private func emptySummary() -> FocusReport.Summary {
        FocusReport.Summary(focusTotal: 0, breakTotal: 0, completedFocusCount: 0,
                            cancelledFocusCount: 0, skippedFocusCount: 0,
                            streakDays: 0, dailyFocusAverage: 0)
    }

    private func interval(for period: Period) -> DateInterval? {
        let days: Int
        switch period {
        case .today: days = 1
        case .week: days = 7
        case .month: days = 30
        case .all: return nil
        }
        // Do início de (hoje − N + 1) até agora: "7 dias" = hoje + 6 anteriores completos;
        // "Hoje" = do início de hoje até agora.
        let startOfToday = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) else {
            return nil
        }
        return DateInterval(start: start, end: Date())
    }

    // MARK: - Formatação

    /// "2h 10min" / "45min" — sempre legível, nunca segundos crus.
    nonisolated static func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((interval / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)min" }
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)min"
    }

    func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.setLocalizedDateFormatFromTemplate("dd/MM")
        return formatter.string(from: date)
    }
}
