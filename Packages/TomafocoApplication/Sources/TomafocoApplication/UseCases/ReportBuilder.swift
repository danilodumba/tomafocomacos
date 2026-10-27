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

    /// Uma entrada de histórico de tarefa dentro do período (FEAT-001), já com o título
    /// resolvido para exibição/exportação.
    public struct HistoryItem: Equatable, Identifiable {
        /// `id` da própria `TaskHistoryEntry` — identidade estável para `ForEach` na UI.
        public let id: UUID
        public let taskID: UUID
        public let taskTitle: String
        public let date: Date
        public let text: String

        public init(id: UUID, taskID: UUID, taskTitle: String, date: Date, text: String) {
            self.id = id
            self.taskID = taskID
            self.taskTitle = taskTitle
            self.date = date
            self.text = text
        }
    }

    public let taskTotals: [TaskTotal]
    public let dailyTotals: [DailyTotal]
    public let summary: Summary
    /// Histórico das tarefas no período, mais recente primeiro.
    public let historyEntries: [HistoryItem]

    public init(
        taskTotals: [TaskTotal],
        dailyTotals: [DailyTotal],
        summary: Summary,
        historyEntries: [HistoryItem] = []
    ) {
        self.taskTotals = taskTotals
        self.dailyTotals = dailyTotals
        self.summary = summary
        self.historyEntries = historyEntries
    }
}

/// Relatório de UMA tarefa num período (RF-10.6): sessões de foco uma a uma, foco por dia,
/// conclusões e histórico. Subtarefas (FEAT-003) entram no relatório do pai — mesma regra de
/// roll-up das `taskTotals`, mas aqui cada sessão aparece uma vez e diz por qual filha veio.
public struct TaskReport: Equatable {
    public struct Session: Equatable, Identifiable {
        /// `sessionID` do registro — uma sessão multi-tarefa com pai e filha aparece uma vez só.
        public let id: UUID
        public let startedAt: Date
        public let endedAt: Date
        public let duration: TimeInterval
        public let outcome: SessionRecord.Outcome
        /// Título da subtarefa quando a sessão conta no pai por roll-up (`nil` = foco direto).
        public let subtaskTitle: String?

        public init(
            id: UUID, startedAt: Date, endedAt: Date, duration: TimeInterval,
            outcome: SessionRecord.Outcome, subtaskTitle: String?
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.duration = duration
            self.outcome = outcome
            self.subtaskTitle = subtaskTitle
        }
    }

    public let taskID: UUID
    /// Título resolvido ("Pai › Filha" para subtarefa).
    public let title: String
    public let focusTotal: TimeInterval
    /// Sessões de foco no período, mais recente primeiro.
    public let sessions: [Session]
    /// Foco por dia só desta tarefa (`breakTime`/`breakCount` sempre 0 — intervalo não é de tarefa).
    public let dailyTotals: [FocusReport.DailyTotal]
    /// Conclusões no período, mais recente primeiro (diária = uma por dia, RF-10.4).
    public let completions: [Date]
    /// Entradas de histórico da tarefa no período, mais recente primeiro.
    public let historyEntries: [FocusReport.HistoryItem]

    public init(
        taskID: UUID, title: String, focusTotal: TimeInterval, sessions: [Session],
        dailyTotals: [FocusReport.DailyTotal], completions: [Date],
        historyEntries: [FocusReport.HistoryItem]
    ) {
        self.taskID = taskID
        self.title = title
        self.focusTotal = focusTotal
        self.sessions = sessions
        self.dailyTotals = dailyTotals
        self.completions = completions
        self.historyEntries = historyEntries
    }

    public var sessionCount: Int { sessions.count }
    /// Média de duração por sessão; 0 sem sessão.
    public var averageSessionDuration: TimeInterval {
        sessions.isEmpty ? 0 : focusTotal / Double(sessions.count)
    }
}

/// Agregador PURO de relatórios (RF-10): sem `Date()`, sem I/O — `now` e `calendar` injetados,
/// testável por tabela. Tempo é sempre de parede (`endedAt − startedAt`), pausas incluídas —
/// decisão de produto registrada no plano de 2026-07-22.
public enum ReportBuilder {

    /// Relatório de uma tarefa (RF-10.6). `nil` se a tarefa não existe mais — tarefa apagada não
    /// tem relatório próprio (ela só sobrevive como "Tarefa removida" nas `taskTotals`).
    public static func taskReport(
        taskID: UUID,
        records: [SessionRecord],
        tasks: [FocusTask],
        interval: DateInterval?,
        calendar: Calendar
    ) -> TaskReport? {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return nil }
        let children = TaskTree.children(of: taskID, in: tasks)
        let childTitleByID = Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0.title) })

        let focus = records.filter {
            $0.phase == .focus && (interval?.contains($0.startedAt) ?? true)
        }
        var matched: [SessionRecord] = []
        var sessions: [TaskReport.Session] = []
        for record in focus {
            let direct = record.taskIDs.contains(taskID)
            let viaChild = record.taskIDs.first { childTitleByID[$0] != nil }
            guard direct || viaChild != nil else { continue }
            matched.append(record)
            sessions.append(TaskReport.Session(
                id: record.sessionID,
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                duration: duration(record),
                outcome: record.outcome,
                // Foco direto no pai vence: a sessão é "dele" mesmo que uma filha também esteja.
                subtaskTitle: direct ? nil : viaChild.flatMap { childTitleByID[$0] }
            ))
        }

        let completions = CompletedTaskOccurrence.occurrences(of: [task])
            .compactMap(\.task.completedAt)
            .filter { interval?.contains($0) ?? true }

        return TaskReport(
            taskID: taskID,
            title: TaskTree.displayTitle(of: task, in: tasks),
            focusTotal: matched.reduce(0) { $0 + duration($1) },
            sessions: sessions.sorted { $0.startedAt > $1.startedAt },
            dailyTotals: dailyTotals(focus: matched, breaks: [], calendar: calendar),
            completions: completions,
            historyEntries: historyEntries(tasks: [task], interval: interval)
        )
    }

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
                             now: now, calendar: calendar),
            historyEntries: historyEntries(tasks: tasks, interval: interval)
        )
    }

    // MARK: - Agregações

    private static func duration(_ record: SessionRecord) -> TimeInterval {
        max(0, record.endedAt.timeIntervalSince(record.startedAt))
    }

    private static func taskTotals(focus: [SessionRecord], tasks: [FocusTask]) -> [FocusReport.TaskTotal] {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        // Foco multi-tarefa (RF-09.4): uma sessão com N tarefas dá o tempo CHEIO a cada uma
        // (decisão de produto — a soma dos totais pode passar do tempo real de foco). Registro
        // sem tarefa (`taskIDs` vazio) agrupa sob a chave `nil` → "Sem tarefa".
        var focusTimeByTask: [UUID?: TimeInterval] = [:]
        var sessionsByTask: [UUID?: Int] = [:]
        for record in focus {
            let dur = duration(record)
            var keys: [UUID?] = record.taskIDs.isEmpty ? [nil] : record.taskIDs.map { $0 }
            // Subtarefas (FEAT-003): o tempo da filha também soma no pai — a linha do pai é
            // "próprio + filhas" e aparece mesmo que o pai nunca tenha sido focado diretamente.
            // A filha continua com a linha dela, como "Pai › Filha". A soma é **por sessão**: pai
            // e filha (ou duas filhas) na mesma sessão multi-tarefa contam UMA vez para o pai.
            for taskID in record.taskIDs {
                guard let parentID = byID[taskID]?.parentID, byID[parentID] != nil,
                      !keys.contains(parentID) else { continue }
                keys.append(parentID)
            }
            for key in keys {
                focusTimeByTask[key, default: 0] += dur
                sessionsByTask[key, default: 0] += 1
            }
        }
        return focusTimeByTask
            .map { taskID, focusTime in
                FocusReport.TaskTotal(
                    taskID: taskID,
                    // Tarefa apagada depois de usada não pode sumir do relatório — vira "Tarefa removida".
                    title: taskID.map { id in
                        byID[id].map { TaskTree.displayTitle(of: $0, in: tasks) } ?? "Tarefa removida"
                    } ?? "Sem tarefa",
                    focusTime: focusTime,
                    sessionCount: sessionsByTask[taskID] ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.focusTime != rhs.focusTime { return lhs.focusTime > rhs.focusTime }
                return lhs.title < rhs.title
            }
    }

    /// Histórico (FEAT-001): vem das TAREFAS, não de `[SessionRecord]` — a entrada mora dentro da
    /// `FocusTask`. Por isso não há fallback "Tarefa removida" como em `taskTotals`: apagar a
    /// tarefa leva o histórico junto. Recorte pela data da inclusão, mesmo `interval` do resto.
    private static func historyEntries(tasks: [FocusTask], interval: DateInterval?) -> [FocusReport.HistoryItem] {
        tasks
            .flatMap { task in
                task.history.map {
                    FocusReport.HistoryItem(
                        id: $0.id, taskID: task.id, taskTitle: task.title,
                        date: $0.createdAt, text: $0.text)
                }
            }
            .filter { interval?.contains($0.date) ?? true }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.taskTitle < rhs.taskTitle
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
