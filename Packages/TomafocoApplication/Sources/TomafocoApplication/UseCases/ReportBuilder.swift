import Foundation
import TomafocoDomain

/// Relatório agregado de um período (RF-10). Tudo derivado de `[SessionRecord]` + `[FocusTask]`.
public struct FocusReport: Equatable {
    /// Total por tarefa — só fases de foco. `taskID == nil` agrupa o histórico sem tarefa.
    public struct TaskTotal: Equatable {
        public let taskID: UUID?
        public let title: String
        public let focusTime: TimeInterval
        public let sessionCount: Int

        public init(taskID: UUID?, title: String, focusTime: TimeInterval, sessionCount: Int) {
            self.taskID = taskID
            self.title = title
            self.focusTime = focusTime
            self.sessionCount = sessionCount
        }
    }

    /// Um dia do período, com foco e intervalos somados.
    public struct DailyTotal: Equatable {
        public let day: Date
        public let focusTime: TimeInterval
        public let breakTime: TimeInterval
        public let breakCount: Int

        public init(day: Date, focusTime: TimeInterval, breakTime: TimeInterval, breakCount: Int) {
            self.day = day
            self.focusTime = focusTime
            self.breakTime = breakTime
            self.breakCount = breakCount
        }
    }

    public struct Summary: Equatable {
        public let focusTotal: TimeInterval
        public let breakTotal: TimeInterval
        public let completedFocusCount: Int
        public let cancelledFocusCount: Int
        public let skippedFocusCount: Int
        /// Dias consecutivos com foco, contando para trás a partir do dia de `now` (hoje sem
        /// foco ainda não quebra a sequência — ontem quebra).
        public let streakDays: Int
        /// Média de foco por dia COM atividade (dias vazios não diluem).
        public let dailyFocusAverage: TimeInterval

        public init(
            focusTotal: TimeInterval, breakTotal: TimeInterval,
            completedFocusCount: Int, cancelledFocusCount: Int, skippedFocusCount: Int,
            streakDays: Int, dailyFocusAverage: TimeInterval
        ) {
            self.focusTotal = focusTotal
            self.breakTotal = breakTotal
            self.completedFocusCount = completedFocusCount
            self.cancelledFocusCount = cancelledFocusCount
            self.skippedFocusCount = skippedFocusCount
            self.streakDays = streakDays
            self.dailyFocusAverage = dailyFocusAverage
        }
    }

    public let taskTotals: [TaskTotal]
    public let dailyTotals: [DailyTotal]
    public let summary: Summary

    public init(taskTotals: [TaskTotal], dailyTotals: [DailyTotal], summary: Summary) {
        self.taskTotals = taskTotals
        self.dailyTotals = dailyTotals
        self.summary = summary
    }
}

/// Agregador PURO de relatórios (RF-10): sem `Date()`, sem I/O — `now` e `calendar` injetados,
/// testável por tabela. Tempo é sempre de parede (`endedAt − startedAt`), pausas incluídas —
/// decisão de produto registrada no plano de 2026-07-22.
public enum ReportBuilder {

    public static func build(
        records: [SessionRecord],
        tasks: [FocusTask],
        interval: DateInterval?,
        now: Date,
        calendar: Calendar
    ) -> FocusReport {
        // Sessão que cruza a meia-noite conta inteira no dia de `startedAt` — fatiar
        // por dia complicaria sem valor para um Pomodoro de ≤ 60 min.
        let scoped = records.filter { interval?.contains($0.startedAt) ?? true }
        let focus = scoped.filter { $0.phase == .focus }
        let breaks = scoped.filter { $0.phase == .shortBreak || $0.phase == .longBreak }

        return FocusReport(
            taskTotals: taskTotals(focus: focus, tasks: tasks),
            dailyTotals: dailyTotals(focus: focus, breaks: breaks, calendar: calendar),
            summary: summary(focus: focus, breaks: breaks, allFocus: records.filter { $0.phase == .focus },
                             now: now, calendar: calendar)
        )
    }

    // MARK: - Agregações

    private static func duration(_ record: SessionRecord) -> TimeInterval {
        max(0, record.endedAt.timeIntervalSince(record.startedAt))
    }

    private static func taskTotals(focus: [SessionRecord], tasks: [FocusTask]) -> [FocusReport.TaskTotal] {
        let titles = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) })
        let groups = Dictionary(grouping: focus, by: \.taskID)
        return groups
            .map { taskID, records in
                FocusReport.TaskTotal(
                    taskID: taskID,
                    // Tarefa apagada depois de usada não pode sumir do relatório — vira "Tarefa removida".
                    title: taskID.map { titles[$0] ?? "Tarefa removida" } ?? "Sem tarefa",
                    focusTime: records.reduce(0) { $0 + duration($1) },
                    sessionCount: records.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.focusTime != rhs.focusTime { return lhs.focusTime > rhs.focusTime }
                return lhs.title < rhs.title
            }
    }

    private static func dailyTotals(
        focus: [SessionRecord], breaks: [SessionRecord], calendar: Calendar
    ) -> [FocusReport.DailyTotal] {
        let focusByDay = Dictionary(grouping: focus) { calendar.startOfDay(for: $0.startedAt) }
        let breaksByDay = Dictionary(grouping: breaks) { calendar.startOfDay(for: $0.startedAt) }
        let days = Set(focusByDay.keys).union(breaksByDay.keys)
        return days.sorted().map { day in
            let dayBreaks = breaksByDay[day] ?? []
            return FocusReport.DailyTotal(
                day: day,
                focusTime: (focusByDay[day] ?? []).reduce(0) { $0 + duration($1) },
                breakTime: dayBreaks.reduce(0) { $0 + duration($1) },
                breakCount: dayBreaks.count
            )
        }
    }

    private static func summary(
        focus: [SessionRecord], breaks: [SessionRecord], allFocus: [SessionRecord],
        now: Date, calendar: Calendar
    ) -> FocusReport.Summary {
        let focusTotal = focus.reduce(0) { $0 + duration($1) }
        let activeDays = Set(focus.map { calendar.startOfDay(for: $0.startedAt) })
        return FocusReport.Summary(
            focusTotal: focusTotal,
            breakTotal: breaks.reduce(0) { $0 + duration($1) },
            completedFocusCount: focus.filter { $0.outcome == .completed }.count,
            cancelledFocusCount: focus.filter { $0.outcome == .cancelled }.count,
            skippedFocusCount: focus.filter { $0.outcome == .skipped }.count,
            streakDays: streak(focusDays: Set(allFocus.map { calendar.startOfDay(for: $0.startedAt) }),
                               now: now, calendar: calendar),
            dailyFocusAverage: activeDays.isEmpty ? 0 : focusTotal / Double(activeDays.count)
        )
    }

    /// Sequência sobre o histórico COMPLETO (não o período filtrado): mudar o filtro para
    /// "7 dias" não pode encolher uma sequência real de 30.
    private static func streak(focusDays: Set<Date>, now: Date, calendar: Calendar) -> Int {
        var day = calendar.startOfDay(for: now)
        var count = 0
        // Hoje ainda sem foco não quebra a sequência; só desloca o início para ontem.
        if !focusDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        while focusDays.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
