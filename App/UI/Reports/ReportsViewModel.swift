import Foundation
import SwiftUI
import TomafocoDomain
import TomafocoApplication

/// ViewModel da aba Relatórios (RF-10). Lê histórico + tarefas e delega a agregação
/// ao `ReportBuilder` puro — aqui só há seleção de período e formatação.
@MainActor
final class ReportsViewModel: ObservableObject {

    enum Period: String, CaseIterable, Identifiable {
        case week = "7 dias"
        case month = "30 dias"
        case all = "Tudo"
        var id: String { rawValue }
    }

    @Published var period: Period = .week {
        didSet { reload() }
    }
    @Published private(set) var report: FocusReport?
    /// Todas as tarefas concluídas (fonte para a lista e o CSV), antes de busca/tag.
    @Published private(set) var completedAll: [FocusTask] = []
    /// Todas as tags conhecidas — alimenta o filtro por tag.
    @Published private(set) var knownTags: [String] = []
    /// Busca por título e filtro por tag da lista de concluídas (item 3).
    @Published var searchText = ""
    @Published var tagFilter: String?

    private let sessions: SessionRepository
    private let tasks: TaskRepository
    private let calendar = Calendar.current

    init(sessions: SessionRepository, tasks: TaskRepository) {
        self.sessions = sessions
        self.tasks = tasks
    }

    func reload() {
        let records = (try? sessions.loadHistory()) ?? []
        let allTasks = (try? tasks.loadTasks()) ?? []
        report = ReportBuilder.build(
            records: records, tasks: allTasks,
            interval: interval(for: period), now: Date(), calendar: calendar)
        completedAll = allTasks.filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        knownTags = allTasks.flatMap(\.tags).reduce(into: [String]()) { acc, tag in
            if !acc.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { acc.append(tag) }
        }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Concluídas após busca por título e filtro por tag.
    var completedTasks: [FocusTask] {
        var list = completedAll
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        if let tag = tagFilter {
            list = list.filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        }
        return list
    }

    /// CSV das tarefas concluídas filtradas (item 3). Datas formatadas em pt-BR.
    func csv() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return ReportCSVExporter.completedTasksCSV(
            tasks: completedTasks,
            report: report ?? FocusReport(taskTotals: [], dailyTotals: [], summary: emptySummary()),
            dateString: { formatter.string(from: $0) })
    }

    private func emptySummary() -> FocusReport.Summary {
        FocusReport.Summary(focusTotal: 0, breakTotal: 0, completedFocusCount: 0,
                            cancelledFocusCount: 0, skippedFocusCount: 0,
                            streakDays: 0, dailyFocusAverage: 0)
    }

    private func interval(for period: Period) -> DateInterval? {
        let days: Int
        switch period {
        case .week: days = 7
        case .month: days = 30
        case .all: return nil
        }
        // Do início de (hoje − N + 1) até agora: "7 dias" = hoje + 6 anteriores completos.
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
