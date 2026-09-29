import SwiftUI
import Charts
import AppKit
import TomafocoDomain
import TomafocoApplication

/// Janela Relatórios (RF-10): resumo, horas por dia, intervalos por dia, horas por tarefa e a
/// lista de tarefas concluídas (item 3) com busca, filtro por tag e exportação CSV.
/// Dois gráficos separados de propósito — nunca eixo Y duplo; cada medida tem seu gráfico.
struct ReportsView: View {
    @ObservedObject var viewModel: ReportsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let report = viewModel.report {
                    if report.dailyTotals.isEmpty {
                        emptyState
                    } else {
                        summaryTiles(report.summary)
                        dailyFocusChart(report.dailyTotals)
                        dailyBreaksChart(report.dailyTotals)
                        taskTable(report.taskTotals)
                    }
                }

                completedSection
                historySection
            }
            .padding(16)
        }
        .onAppear { viewModel.reload() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Período", selection: $viewModel.period) {
                ForEach(ReportsViewModel.Period.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button {
                save(csv: viewModel.csv(), defaultName: "tomafoco-tarefas.csv")
            } label: {
                Label("Exportar CSV…", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.completedTasks.isEmpty)
        }
    }

    // MARK: - Tarefas concluídas (item 3)

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tarefas concluídas")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.textSecondary)

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Brand.textFaint)
                    TextField("Buscar", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 140)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Brand.surface))

                Menu {
                    Button("Todas") { viewModel.tagFilter = nil }
                    Divider()
                    ForEach(viewModel.knownTags, id: \.self) { tag in
                        Button { viewModel.tagFilter = tag } label: {
                            Label(tag, systemImage: viewModel.tagFilter == tag ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label(viewModel.tagFilter ?? "Tag", systemImage: "tag")
                }
                .fixedSize()

                Spacer()
            }
            .font(.system(size: 12))

            if viewModel.completedTasks.isEmpty {
                Text("Nenhuma tarefa concluída no filtro.")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textFaint)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.completedTasks) { task in
                    completedRow(task)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
        )
    }

    private func completedRow(_ task: FocusTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let done = task.completedAt {
                        Text(done.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(Brand.textFaint)
                    }
                    ForEach(task.tags, id: \.self) { tag in
                        Text(tag)
                            .foregroundStyle(Brand.cyan)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Brand.cyan.opacity(0.14), in: Capsule())
                    }
                }
                .font(.system(size: 10))
            }
            Spacer()
            if let p = task.priority {
                Text(priorityGlyph(TaskPriority(rawPriority: p)))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.surface))
    }

    private func priorityGlyph(_ p: TaskPriority) -> String {
        switch p {
        case .none: return ""
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }

    /// Grava um CSV via `NSSavePanel` — serve tanto as concluídas (item 3) quanto o histórico
    /// (FEAT-001).
    private func save(csv: String, defaultName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // BOM UTF-8 para o Excel abrir acentos corretamente.
        let content = "\u{FEFF}" + csv
        try? content.data(using: .utf8)?.write(to: url)
    }

    // MARK: - Histórico das tarefas (FEAT-001)

    /// Entradas de histórico do período selecionado, mais recente primeiro. Recorte é só por
    /// período: a busca e o filtro de tag acima valem para a lista de concluídas.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Histórico das tarefas")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)

                Spacer()

                Button {
                    save(csv: viewModel.historyCSV(), defaultName: "tomafoco-historico.csv")
                } label: {
                    Label("Exportar histórico CSV…", systemImage: "square.and.arrow.up")
                }
                .font(.system(size: 12))
                .disabled(viewModel.historyEntries.isEmpty)
            }

            if viewModel.historyEntries.isEmpty {
                Text("Nenhuma entrada de histórico no período.")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textFaint)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.historyEntries) { entry in
                    historyRow(entry)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
        )
    }

    private func historyRow(_ entry: FocusReport.HistoryItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(Brand.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(entry.taskTitle)
                }
                .font(.system(size: 10))
                .foregroundStyle(Brand.textFaint)
            }
            Spacer()
        }
        .font(.system(size: 12))
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Brand.surface))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 28))
                .foregroundStyle(Brand.textFaint)
            Text("Sem sessões no período. Complete um foco e volte aqui.")
                .font(.system(size: 12))
                .foregroundStyle(Brand.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Resumo (stat tiles)

    private func summaryTiles(_ summary: FocusReport.Summary) -> some View {
        let tiles: [(String, String)] = [
            ("Foco total", ReportsViewModel.formatDuration(summary.focusTotal)),
            ("Intervalos", ReportsViewModel.formatDuration(summary.breakTotal)),
            ("Média/dia", ReportsViewModel.formatDuration(summary.dailyFocusAverage)),
            ("Sequência", "\(summary.streakDays) dia\(summary.streakDays == 1 ? "" : "s")"),
            ("Focos ✓", "\(summary.completedFocusCount)"),
            ("Cancelados", "\(summary.cancelledFocusCount)")
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
            ForEach(tiles, id: \.0) { title, value in
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(Brand.textFaint)
                    Text(value)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Brand.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Gráficos (uma série cada — o título nomeia; sem legenda)

    private func dailyFocusChart(_ days: [FocusReport.DailyTotal]) -> some View {
        chartCard("Horas focadas por dia") {
            Chart(days, id: \.day) { day in
                BarMark(
                    x: .value("Dia", day.day, unit: .day),
                    y: .value("Horas", day.focusTime / 3600)
                )
                .foregroundStyle(Brand.cyan)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Brand.surfaceStroke)
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(hours, specifier: "%.0f")h")
                                .foregroundStyle(Brand.textFaint)
                        }
                    }
                }
            }
            .chartXAxis { dayAxis }
        }
    }

    private func dailyBreaksChart(_ days: [FocusReport.DailyTotal]) -> some View {
        chartCard("Intervalos por dia") {
            Chart(days, id: \.day) { day in
                BarMark(
                    x: .value("Dia", day.day, unit: .day),
                    y: .value("Intervalos", day.breakCount)
                )
                .foregroundStyle(Brand.cyanDeep)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Brand.surfaceStroke)
                    AxisValueLabel()
                        .foregroundStyle(Brand.textFaint)
                }
            }
            .chartXAxis { dayAxis }
        }
    }

    private var dayAxis: some AxisContent {
        AxisMarks(values: .stride(by: .day)) { _ in
            AxisValueLabel(format: .dateTime.day().month(.twoDigits), centered: true)
                .foregroundStyle(Brand.textFaint)
        }
    }

    private func chartCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.textSecondary)
            content()
                .frame(height: 140)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Brand.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
                )
        )
    }

    // MARK: - Horas por tarefa (tabela — identidade + valor, sem gráfico)

    private func taskTable(_ totals: [FocusReport.TaskTotal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Horas por tarefa")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.textSecondary)

            ForEach(Array(totals.enumerated()), id: \.offset) { _, total in
                HStack {
                    Text(total.title)
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(total.sessionCount) sessão\(total.sessionCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textFaint)
                    Text(ReportsViewModel.formatDuration(total.focusTime))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .frame(minWidth: 64, alignment: .trailing)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Brand.surface)
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
        )
    }
}
