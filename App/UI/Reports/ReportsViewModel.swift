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
