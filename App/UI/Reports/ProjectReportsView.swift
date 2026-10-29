import SwiftUI
import TomafocoDomain
import TomafocoApplication

/// Janela Relatórios › Projetos (FEAT-006 / RF-10.7): escolhe período e projeto, lista as tarefas
/// pai com o tempo de foco (subtarefas somadas no pai), totaliza e gera o PDF.
struct ProjectReportsView: View {
    @ObservedObject var viewModel: ProjectReportsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let feedback = viewModel.feedback {
                Text(feedback).font(.system(size: 12)).foregroundStyle(Brand.textSecondary)
            }

            if viewModel.projects.isEmpty {
                placeholder("Nenhum projeto cadastrado.",
                            detail: "Crie projetos pela janela Tarefas › Projetos… e volte aqui.")
            } else if let report = viewModel.report {
                content(report)
            }
        }
        .padding(16)
        .onAppear { viewModel.reload() }
        .sheet(item: $viewModel.pdfPreview) { document in
            PDFPreviewSheet(document: document) { viewModel.pdfPreview = nil }
        }
    }

    // MARK: - Barra

    private var header: some View {
        HStack(spacing: 12) {
            projectMenu

            Picker("Período", selection: $viewModel.period) {
                ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            Button {
                viewModel.showPDF()
            } label: {
                Label("Ver PDF…", systemImage: "doc.richtext")
            }
            .disabled(viewModel.report == nil)
        }
    }

    private var projectMenu: some View {
        Menu {
            ForEach(viewModel.projects) { project in
                Toggle(isOn: Binding(
                    get: { viewModel.selectedProjectID == project.id },
                    set: { if $0 { viewModel.selectedProjectID = project.id } })
                ) {
                    Label(project.title, systemImage: project.symbolName)
                }
            }
        } label: {
            if let project = viewModel.selectedProject {
                Label(project.title, systemImage: project.symbolName)
            } else {
                Label("Escolher projeto…", systemImage: "folder")
            }
        }
        .fixedSize()
        .accessibilityLabel("Projeto: \(viewModel.selectedProject?.title ?? "nenhum")")
    }

    // MARK: - Conteúdo

    private func content(_ report: ProjectReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatTile(title: "Total", value: ProjectReportsViewModel.formatDuration(report.focusTotal))
                StatTile(title: "Em horas", value: ProjectReportsViewModel.formatDecimalHours(report.focusTotal))
                StatTile(title: "Tarefas", value: "\(report.rows.count)")
                StatTile(title: "Sessões", value: "\(report.sessionCount)")
            }

            if report.rows.isEmpty {
                placeholder("Nenhuma tarefa neste projeto.",
                            detail: "Só tarefas pai entram — o tempo das subtarefas soma no pai.")
            } else {
                table(report)
            }
        }
    }

    private func table(_ report: ProjectReport) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Tarefa").frame(maxWidth: .infinity, alignment: .leading)
                Text("Subtarefas").frame(width: 80, alignment: .trailing)
                Text("Sessões").frame(width: 64, alignment: .trailing)
                Text("Tempo").frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Brand.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(report.rows) { row in
                        tableRow(row, accent: report.project.color.color)
                        Divider()
                    }
                }
            }

            // Totalizador fixo no rodapé da tabela.
            HStack(spacing: 8) {
                Text("Total do projeto").frame(maxWidth: .infinity, alignment: .leading)
                Text(ProjectReportsViewModel.formatDuration(report.focusTotal))
                    .frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Brand.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(report.project.color.color.opacity(0.10))

            if report.rowsSum > report.focusTotal {
                Text("Sessões com mais de uma tarefa do projeto contam uma vez no total — por isso a soma das linhas é maior.")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
        }
        .monospacedDigit()
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Brand.surfaceStroke))
    }

    private func tableRow(_ row: ProjectReport.Row, accent: Color) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if row.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                        .help("Concluída")
                }
                Text(row.title)
                    .foregroundStyle(row.isCompleted ? Brand.textSecondary : Brand.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.subtaskCount > 0 ? "\(row.subtaskCount)" : "—").frame(width: 80, alignment: .trailing)
            Text("\(row.sessionCount)").frame(width: 64, alignment: .trailing)
            Text(ProjectReportsViewModel.formatDuration(row.focusTime))
                .fontWeight(.medium)
                .frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: 12))
        .foregroundStyle(Brand.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func placeholder(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "folder").font(.system(size: 26)).foregroundStyle(Brand.textFaint)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Brand.textSecondary)
            Text(detail).font(.system(size: 11)).foregroundStyle(Brand.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
