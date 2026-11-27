import SwiftUI
import TomafocoDomain

// MARK: - Textos (RF-09.21)

extension TaskRecurrence {
    /// Abreviações pt-BR na ordem do `Calendar` (1 = domingo).
    static let weekdaySymbols = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
    static let weekdayInitials = ["D", "S", "T", "Q", "Q", "S", "S"]
    static let monthNames = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho",
                             "agosto", "setembro", "outubro", "novembro", "dezembro"]

    /// Rótulo curto do selo na linha/cartão.
    var badgeText: String {
        switch self {
        case .daily(1): return "Diária"
        case .daily: return "A cada \(interval) dias"
        case _ where self == .weekdays: return "Dias úteis"
        case _ where self == .weekends: return "Fins de semana"
        case .weekly: return "Semanal"
        case .monthly: return "Mensal"
        case .yearly: return "Anual"
        }
    }

    /// Descrição completa: tooltip do selo e resumo no formulário.
    var summary: String {
        switch self {
        case .daily(1):
            return "Todo dia"
        case .daily(let n):
            return "A cada \(n) dias"
        case _ where self == .weekdays:
            return "Dias úteis (segunda a sexta)"
        case _ where self == .weekends:
            return "Fins de semana (sábado e domingo)"
        case .weekly(let days, let n):
            let list = days.map { Self.weekdaySymbols[$0 - 1] }.joined(separator: ", ")
            return n == 1 ? "Toda semana: \(list)" : "A cada \(n) semanas: \(list)"
        case .monthly(let day, let n):
            let base = n == 1 ? "Todo mês" : "A cada \(n) meses"
            return day >= 29 ? "\(base), no dia \(day) (ou no último dia)" : "\(base), no dia \(day)"
        case .yearly(let month, let day):
            return "Todo ano em \(day) de \(Self.monthNames[month - 1])"
        }
    }

    private var interval: Int {
        switch self {
        case .daily(let n), .weekly(_, let n), .monthly(_, let n): return n
        case .yearly: return 1
        }
    }
}

/// Selo "repete" da linha/cartão.
struct RecurrenceBadge: View {
    let recurrence: TaskRecurrence

    var body: some View {
        Label(recurrence.badgeText, systemImage: "repeat")
            .foregroundStyle(Brand.cyan)
            .help("Repete — \(recurrence.summary). Ao concluir, uma cópia é criada com o próximo vencimento.")
    }
}

// MARK: - Editor

/// Tipo escolhido no seletor — os presets (dias úteis, fins de semana) são `weekly` por baixo.
enum RecurrenceKind: String, CaseIterable, Identifiable {
    case none, daily, everyNDays, weekdays, weekends, weekly, monthly, yearly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Não repete"
        case .daily: "Todo dia"
        case .everyNDays: "A cada N dias"
        case .weekdays: "Dias úteis (seg–sex)"
        case .weekends: "Fins de semana"
        case .weekly: "Semanal (dias escolhidos)"
        case .monthly: "Mensal"
        case .yearly: "Anual"
        }
    }

    init(_ recurrence: TaskRecurrence?) {
        switch recurrence {
        case nil: self = .none
        case .daily(1)?: self = .daily
        case .daily?: self = .everyNDays
        case let r? where r == .weekdays: self = .weekdays
        case let r? where r == .weekends: self = .weekends
        case .weekly?: self = .weekly
        case .monthly?: self = .monthly
        case .yearly?: self = .yearly
        }
    }

    /// Regra inicial ao escolher o tipo. `reference` = vencimento (ou hoje): semanal começa no dia
    /// da semana dele, mensal no dia do mês, anual no dia/mês.
    func makeRecurrence(reference: Date, calendar: Calendar = .current) -> TaskRecurrence? {
        let weekday = calendar.component(.weekday, from: reference)
        let day = calendar.component(.day, from: reference)
        let month = calendar.component(.month, from: reference)
        switch self {
        case .none: return nil
        case .daily: return .everyDay
        case .everyNDays: return .daily(interval: 2)
        case .weekdays: return .weekdays
        case .weekends: return .weekends
        case .weekly: return .weekly(weekdays: [weekday], interval: 1)
        case .monthly: return .monthly(day: day, interval: 1)
        case .yearly: return .yearly(month: month, day: day)
        }
    }
}

/// Seletor de repetição do formulário da tarefa (RF-09.21): tipo + detalhes do tipo (dias da
/// semana, intervalo, dia do mês, data anual) + resumo em texto.
struct RecurrenceEditor: View {
    @Binding var recurrence: TaskRecurrence?
    /// Vencimento do rascunho (ou hoje) — ponto de partida ao trocar de tipo.
    let reference: Date

    var body: some View {
        Picker("Repetir", selection: Binding(
            get: { RecurrenceKind(recurrence) },
            set: { kind in
                guard kind != RecurrenceKind(recurrence) else { return }
                recurrence = kind.makeRecurrence(reference: reference)
            }
        )) {
            ForEach(RecurrenceKind.allCases) { kind in
                Text(kind.title).tag(kind)
                if kind == .none || kind == .everyNDays || kind == .weekends { Divider() }
            }
        }

        details

        if let recurrence {
            Text("\(recurrence.summary). Ao concluir, a tarefa fecha e uma cópia é criada com o próximo vencimento.")
                .font(.system(size: 11))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var details: some View {
        switch recurrence {
        case .daily(let n)? where RecurrenceKind(recurrence) == .everyNDays:
            Stepper("A cada \(n) dias", value: Binding(
                get: { n },
                set: { recurrence = .daily(interval: max(2, $0)) }
            ), in: 2...TaskRecurrence.maxInterval)

        // Também nos presets (dias úteis/fins de semana): mexer nos dias vira semanal personalizado.
        case .weekly(let days, let n)?:
            LabeledContent("Dias") {
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { weekday in
                        weekdayButton(weekday, selected: days.contains(weekday)) {
                            var next = Set(days)
                            if next.contains(weekday) { next.remove(weekday) } else { next.insert(weekday) }
                            // Nunca vazio: desmarcar o último dia não faz nada.
                            guard !next.isEmpty else { return }
                            recurrence = .weekly(weekdays: next.sorted(), interval: n)
                        }
                    }
                }
            }
            Stepper(n == 1 ? "Toda semana" : "A cada \(n) semanas", value: Binding(
                get: { n },
                set: { recurrence = .weekly(weekdays: days, interval: $0) }
            ), in: 1...TaskRecurrence.maxInterval)

        case .monthly(let day, let n)?:
            Stepper("No dia \(day)", value: Binding(
                get: { day },
                set: { recurrence = .monthly(day: $0, interval: n) }
            ), in: 1...31)
            Stepper(n == 1 ? "Todo mês" : "A cada \(n) meses", value: Binding(
                get: { n },
                set: { recurrence = .monthly(day: day, interval: $0) }
            ), in: 1...TaskRecurrence.maxInterval)

        case .yearly(let month, let day)?:
            Picker("Mês", selection: Binding(
                get: { month },
                set: { recurrence = .yearly(month: $0, day: day) }
            )) {
                ForEach(1...12, id: \.self) { m in
                    Text(TaskRecurrence.monthNames[m - 1].capitalized).tag(m)
                }
            }
            Stepper("No dia \(day)", value: Binding(
                get: { day },
                set: { recurrence = .yearly(month: month, day: $0) }
            ), in: 1...31)

        default:
            EmptyView()
        }
    }

    private func weekdayButton(_ weekday: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(TaskRecurrence.weekdayInitials[weekday - 1])
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(selected ? Color.white : Brand.textSecondary)
                .background(Circle().fill(selected ? Brand.cyan : Brand.surface))
        }
        .buttonStyle(.plain)
        .help(TaskRecurrence.weekdaySymbols[weekday - 1])
        .accessibilityLabel(TaskRecurrence.weekdaySymbols[weekday - 1])
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Opções rápidas de repetição para os menus de contexto (linha e cartão). "Personalizar…" é o
/// formulário.
struct RecurrenceMenu: View {
    let task: FocusTask
    let set: (TaskRecurrence?) -> Void
    let customize: () -> Void

    var body: some View {
        Menu("Repetir") {
            option("Não repete", nil)
            Divider()
            option("Todo dia", .everyDay)
            option("Dias úteis (seg–sex)", .weekdays)
            option("Fins de semana", .weekends)
            option("Toda semana neste dia", RecurrenceKind.weekly.makeRecurrence(reference: reference))
            option("Todo mês neste dia", RecurrenceKind.monthly.makeRecurrence(reference: reference))
            option("Todo ano nesta data", RecurrenceKind.yearly.makeRecurrence(reference: reference))
            Divider()
            Button("Personalizar…", action: customize)
        }
    }

    /// "Neste dia" = o do vencimento, ou hoje sem vencimento.
    private var reference: Date { task.dueDate ?? Date() }

    private func option(_ title: String, _ recurrence: TaskRecurrence?) -> some View {
        Toggle(title, isOn: Binding(
            get: { task.recurrence == recurrence },
            set: { if $0 { set(recurrence) } }))
    }
}
