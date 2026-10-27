import Foundation

/// Recorte por vencimento da lista e do quadro (FEAT-005, RF-09.11). Tarefa sem vencimento só
/// aparece em `all`.
public enum TaskDueFilter: String, CaseIterable, Sendable {
    case all
    /// Vence hoje — inclusive as que já venceram mais cedo hoje.
    case today
    /// Vence de hoje (dia inteiro) até o fim do 7º dia seguinte.
    case next7Days
    /// Aberta e com vencimento já passado.
    case overdue

    public func matches(_ task: FocusTask, now: Date, calendar: Calendar) -> Bool {
        guard self != .all else { return true }
        guard let due = task.dueDate else { return false }
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(due, inSameDayAs: now)
        case .next7Days:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 8, to: start) ?? start.addingTimeInterval(8 * 86_400)
            return due >= start && due < end
        case .overdue:
            return !task.isCompleted && due < now
        }
    }
}
