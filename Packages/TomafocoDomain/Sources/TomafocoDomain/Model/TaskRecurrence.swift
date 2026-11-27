import Foundation

/// Regra de repetição da tarefa (RF-09.21). Generaliza a "diária" da FEAT-004: concluir uma tarefa
/// que repete **fecha** a tarefa e cria um **clone** com o vencimento na próxima data da regra
/// (`FocusTask.nextOccurrence`). A conta parte do dia da conclusão — como a diária sempre fez
/// ("amanhã" a partir de quando concluiu, não a partir do vencimento antigo).
///
/// Dias da semana seguem o `Calendar`: 1 = domingo … 7 = sábado.
public enum TaskRecurrence: Equatable, Hashable, Sendable {
    /// A cada `interval` dias (1 = todo dia — a diária da FEAT-004).
    case daily(interval: Int)
    /// Nos dias da semana marcados, a cada `interval` semanas. Dias úteis e fins de semana são
    /// presets (`weekdays`/`weekends`).
    case weekly(weekdays: [Int], interval: Int)
    /// No dia `day` do mês (1–31), a cada `interval` meses. Mês sem esse dia (31 em abril, 30 em
    /// fevereiro) usa o último dia do mês.
    case monthly(day: Int, interval: Int)
    /// Todo ano no mesmo dia/mês. 29/02 em ano não bissexto vira 28/02.
    case yearly(month: Int, day: Int)

    public static let maxInterval = 99

    public static var everyDay: TaskRecurrence { .daily(interval: 1) }
    /// Segunda a sexta.
    public static var weekdays: TaskRecurrence { .weekly(weekdays: [2, 3, 4, 5, 6], interval: 1) }
    /// Sábado e domingo.
    public static var weekends: TaskRecurrence { .weekly(weekdays: [1, 7], interval: 1) }

    /// Regra limpa: intervalo em 1…99, dias da semana únicos/ordenados em 1…7 (vazio → todos),
    /// dia/mês dentro da faixa. Aplicada no `init` do decode e pelo use case ao gravar.
    public var normalized: TaskRecurrence {
        switch self {
        case .daily(let interval):
            return .daily(interval: Self.clampInterval(interval))
        case .weekly(let days, let interval):
            let valid = Array(Set(days.filter { (1...7).contains($0) })).sorted()
            return .weekly(weekdays: valid.isEmpty ? Array(1...7) : valid, interval: Self.clampInterval(interval))
        case .monthly(let day, let interval):
            return .monthly(day: min(max(day, 1), 31), interval: Self.clampInterval(interval))
        case .yearly(let month, let day):
            return .yearly(month: min(max(month, 1), 12), day: min(max(day, 1), 31))
        }
    }

    private static func clampInterval(_ value: Int) -> Int { min(max(value, 1), maxInterval) }

    // MARK: - Próxima data

    /// Próximo **dia** da regra estritamente depois do dia de `now` (início do dia, no `calendar`).
    /// Quem põe o horário é `FocusTask.nextOccurrenceDueDate`.
    public func nextDay(after now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        func addDays(_ n: Int, to date: Date) -> Date {
            calendar.date(byAdding: .day, value: n, to: date) ?? date.addingTimeInterval(TimeInterval(86_400 * n))
        }
        switch normalized {
        case .daily(let interval):
            return addDays(interval, to: today)

        case .weekly(let days, let interval):
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            // Procura até `interval` semanas + 1 à frente: sempre acha (dias nunca é vazio).
            for offset in 1...(7 * (interval + 1)) {
                let candidate = addDays(offset, to: today)
                let candidateWeekStart = calendar.dateInterval(of: .weekOfYear, for: candidate)?.start ?? candidate
                let weeks = calendar.dateComponents([.day], from: weekStart, to: candidateWeekStart).day.map { $0 / 7 } ?? 0
                guard weeks == 0 || weeks % interval == 0 else { continue }
                if days.contains(calendar.component(.weekday, from: candidate)) { return candidate }
            }
            return addDays(1, to: today)

        case .monthly(let day, let interval):
            // Ainda dá neste mês → este mês; senão `interval` meses à frente.
            let monthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
            let thisMonth = Self.day(day, in: monthStart, calendar: calendar)
            if thisMonth > today { return thisMonth }
            let next = calendar.date(byAdding: .month, value: interval, to: monthStart) ?? monthStart
            return Self.day(day, in: next, calendar: calendar)

        case .yearly(let month, let day):
            let year = calendar.component(.year, from: today)
            for y in [year, year + 1] {
                guard let firstOfMonth = calendar.date(from: DateComponents(year: y, month: month, day: 1)) else { continue }
                let candidate = Self.day(day, in: firstOfMonth, calendar: calendar)
                if candidate > today { return candidate }
            }
            return addDays(365, to: today)
        }
    }

    /// Dia `day` do mês que contém `month`, limitado ao último dia do mês.
    private static func day(_ day: Int, in month: Date, calendar: Calendar) -> Date {
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let length = calendar.range(of: .day, in: .month, for: start)?.count ?? 28
        return calendar.date(byAdding: .day, value: min(day, length) - 1, to: start) ?? start
    }
}

// Codable manual (`kind` + campos): JSON legível e estável. Tipo desconhecido (versão futura) →
// diária, para a tarefa continuar repetindo em vez de perder a regra ou derrubar a tarefa.
extension TaskRecurrence: Codable {
    private enum CodingKeys: String, CodingKey { case kind, interval, weekdays, day, month }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let interval = (try? c.decodeIfPresent(Int.self, forKey: .interval)) ?? 1
        switch (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil {
        case "weekly":
            self = TaskRecurrence.weekly(
                weekdays: (try? c.decodeIfPresent([Int].self, forKey: .weekdays)) ?? [], interval: interval).normalized
        case "monthly":
            self = TaskRecurrence.monthly(
                day: (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 1, interval: interval).normalized
        case "yearly":
            self = TaskRecurrence.yearly(
                month: (try? c.decodeIfPresent(Int.self, forKey: .month)) ?? 1,
                day: (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 1).normalized
        default:
            self = TaskRecurrence.daily(interval: interval).normalized
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily(let interval):
            try c.encode("daily", forKey: .kind)
            try c.encode(interval, forKey: .interval)
        case .weekly(let days, let interval):
            try c.encode("weekly", forKey: .kind)
            try c.encode(days, forKey: .weekdays)
            try c.encode(interval, forKey: .interval)
        case .monthly(let day, let interval):
            try c.encode("monthly", forKey: .kind)
            try c.encode(day, forKey: .day)
            try c.encode(interval, forKey: .interval)
        case .yearly(let month, let day):
            try c.encode("yearly", forKey: .kind)
            try c.encode(month, forKey: .month)
            try c.encode(day, forKey: .day)
        }
    }
}
