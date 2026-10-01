import SwiftUI
import TomafocoDomain

/// Sheet de criação em lote (RF-09.8). Passo 1: texto, uma tarefa por linha. Passo 2: grid
/// editável (título, prioridade, tags, vencimento) e "Criar".
/// Grid em `ScrollView` + `LazyVStack` com colunas fixas: `Table` com linhas editáveis por
/// `Binding` é macOS 14+, e o deployment target é 13.
struct BulkAddTasksView: View {
    @ObservedObject var viewModel: BulkAddTasksViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch viewModel.step {
            case .text: textStep
            case .grid: gridStep
            }
        }
        .padding(16)
        .frame(width: viewModel.step == .text ? 460 : 800, height: 480)
    }

    // MARK: - Passo 1: texto

    private var textStep: some View {
        Group {
            Text("Adicionar tarefas em lote")
                .font(.system(size: 14, weight: .semibold))
            Text("Uma tarefa por linha. Marcadores de lista (-, *, 1.) são removidos.")
                .font(.system(size: 12))
                .foregroundStyle(Brand.textSecondary)

            TextEditor(text: $viewModel.rawText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.surfaceStroke))

            HStack {
                Text(countLabel(viewModel.lineCount))
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textSecondary)
                Spacer()
                Button("Cancelar") { viewModel.cancel() }
                    .keyboardShortcut(.cancelAction)
                // Sem `.defaultAction`: Return no editor tem que quebrar linha, não avançar.
                Button("Próximo") { viewModel.goToGrid() }
                    .disabled(viewModel.lineCount == 0)
            }
        }
    }

    // MARK: - Passo 2: grid

    private enum Column {
        static let priority: CGFloat = 110
        static let tags: CGFloat = 170
        static let due: CGFloat = 210
        static let remove: CGFloat = 24
    }

    private var gridStep: some View {
        Group {
            Text("Revisar \(countLabel(viewModel.rows.count))")
                .font(.system(size: 14, weight: .semibold))

            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach($viewModel.rows) { $row in
                            gridRow($row)
                            Divider()
                        }
                    }
                }
            }
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.surfaceStroke))

            if let feedback = viewModel.feedback {
                Text(feedback)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.danger)
            }

            HStack {
                if !viewModel.issues.isEmpty {
                    Label("Corrija as linhas destacadas", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.danger)
                }
                Spacer()
                Button("Voltar") { viewModel.goBack() }
                Button("Cancelar") { viewModel.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Criar \(countLabel(viewModel.rows.count))") { viewModel.create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canCreate)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Título").frame(maxWidth: .infinity, alignment: .leading)
            Text("Prioridade").frame(width: Column.priority, alignment: .leading)
            Text("Tags").frame(width: Column.tags, alignment: .leading)
            Text("Vencimento").frame(width: Column.due, alignment: .leading)
            Color.clear.frame(width: Column.remove, height: 1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Brand.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func gridRow(_ row: Binding<BulkAddTasksViewModel.Row>) -> some View {
        let issue = viewModel.issues[row.wrappedValue.id]
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Título", text: row.title)
                    .textFieldStyle(.roundedBorder)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(Brand.danger, lineWidth: issue == nil ? 0 : 1.5))
                if let issue {
                    Text(issue)
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Prioridade", selection: row.priority) {
                ForEach(TaskPriority.displayOrder, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: Column.priority)

            HStack(spacing: 4) {
                TextField("vírgula", text: row.tags)
                    .textFieldStyle(.roundedBorder)
                TagSuggestionsMenu(knownTags: viewModel.knownTags, text: row.tags)
            }
            .frame(width: Column.tags)

            HStack(spacing: 4) {
                Toggle("Vencimento", isOn: row.hasDueDate)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                DatePicker("", selection: row.dueDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .disabled(!row.wrappedValue.hasDueDate)
                    .opacity(row.wrappedValue.hasDueDate ? 1 : 0.4)
            }
            .frame(width: Column.due, alignment: .leading)

            Button {
                viewModel.removeRow(row.wrappedValue.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Brand.textSecondary)
            }
            .buttonStyle(.plain)
            .frame(width: Column.remove)
            .help("Remover esta linha")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func countLabel(_ count: Int) -> String {
        count == 1 ? "1 tarefa" : "\(count) tarefas"
    }
}
