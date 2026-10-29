import Foundation

/// Período dos relatórios (RF-10) — o mesmo nas janelas de tarefas e de projetos.
enum ReportPeriod: String, CaseIterable, Identifiable {
    case today = "Hoje"
    case week = "7 dias"
    case month = "30 dias"
    case all = "Tudo"

    var id: String { rawValue }

    /// Do início de (hoje − N + 1) até agora: "7 dias" = hoje + 6 anteriores completos;
    /// "Hoje" = do início de hoje até agora. `nil` = sem recorte ("Tudo").
    func interval(now: Date, calendar: Calendar) -> DateInterval? {
        let days: Int
        switch self {
        case .today: days = 1
        case .week: days = 7
        case .month: days = 30
        case .all: return nil
        }
        let startOfToday = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) else {
            return nil
        }
        return DateInterval(start: start, end: now)
    }

    /// Texto do período para o PDF ("Últimos 7 dias", "Hoje", "Todo o histórico").
    var printLabel: String {
        switch self {
        case .today: return "Hoje"
        case .week: return "Últimos 7 dias"
        case .month: return "Últimos 30 dias"
        case .all: return "Todo o histórico"
        }
    }
}
