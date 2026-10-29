import Foundation

/// Converte o `dueDateComponents` de um lembrete em `Date` (FEAT-006, H2). Fora do adapter do
/// EventKit para ser testável sem `EKEventStore`.
///
/// Lembrete "dia inteiro" chega sem hora: `DateComponents.date` daria **00:00** e a tarefa
/// apareceria atrasada o dia inteiro em que vence. Sem hora → **23:59 local** do dia, a mesma
/// regra do clone da diária sem horário (`FocusTask.nextDailyDueDate`).
public enum ReminderDueDate {

    public static func resolve(_ components: DateComponents?, calendar: Calendar) -> Date? {
        guard let components else { return nil }
        guard components.hour == nil else {
            var cal = components.calendar ?? calendar
            if let zone = components.timeZone { cal.timeZone = zone }
            return cal.date(from: components)
        }
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        // Dia inteiro é "flutuante" (sem fuso): vale o dia no fuso local.
        return calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                  hour: 23, minute: 59, second: 0))
    }
}
