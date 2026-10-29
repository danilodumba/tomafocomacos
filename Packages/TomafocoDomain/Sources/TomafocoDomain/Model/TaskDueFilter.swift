import Foundation

/// Recorte por vencimento da lista e do quadro (FEAT-005, RF-09.11). Tarefa sem vencimento só
/// aparece em `all`.
public enum TaskDueFilter: String, CaseIterable, Sendable {
    case all
    /// O que é para hoje: vence hoje (inclusive já vencidas mais cedo hoje) **e** as abertas
    /// atrasadas de dias anteriores (FEAT-006).
    case today
    /// Vence de hoje (dia inteiro) até o fim do 7º dia seguinte — **mais** as abertas atrasadas,
    /// como "Hoje": alargar o recorte não pode fazer tarefa sumir (FEAT-006).
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
            if calendar.isDate(due, inSameDayAs: now) { return true }
            return !task.isCompleted && due < calendar.startOfDay(for: now)
        case .next7Days:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 8, to: start) ?? start.addingTimeInterval(8 * 86_400)
            if due < start { return !task.isCompleted }
            return due < end
        case .overdue:
            return !task.isCompleted && due < now
        }
    }

    /// Recorte pela **data de conclusão** — a raia Done do quadro julga o cartão concluído só
    /// por aqui (o vencimento é ignorado). Mesma janela do vencimento: "Hoje" = concluída hoje;
    /// "Próximos 7 dias" = concluída de hoje em diante (na prática, hoje). "Atrasadas" não tem
    /// sentido para conclusão — nunca casa.
    public func matchesCompletion(_ task: FocusTask, now: Date, calendar: Calendar) -> Bool {
        guard self != .all else { return true }
        guard let completed = task.completedAt else { return false }
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(completed, inSameDayAs: now)
        case .next7Days:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 8, to: start) ?? start.addingTimeInterval(8 * 86_400)
            return completed >= start && completed < end
        case .overdue:
            return false
        }
    }
}
