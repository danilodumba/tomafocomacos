import SwiftUI
import TomafocoDomain

/// Cadastro de projetos (FEAT-006): lista à esquerda, formulário à direita.
struct ProjectsSheet: View {
    @ObservedObject var viewModel: ProjectsViewModel
    @Environment(\.openWindow) private var openWindow

    /// Grades que quebram linha conforme a largura — paleta e ícones cresceram (18 e 64).
    private let colorColumns = [GridItem(.adaptive(minimum: 22), spacing: 6)]
    private let iconColumns = [GridItem(.adaptive(minimum: 28), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projetos")
                .font(.system(size: 15, weight: .semibold))

            HStack(alignment: .top, spacing: 16) {
                projectList
                    .frame(width: 250)
                Divider()
                form
            }

            HStack {
                if let feedback = viewModel.feedback {
                    Text(feedback)
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                Button("Fechar") { viewModel.close() }
                    .keyboardShortcut(.cancelAction)
                // Sem `.defaultAction`: a descrição é multilinha e o Return precisa quebrar linha
                // (key equivalent da janela roda antes do campo). Return no título salva (`onSubmit`).
                Button(viewModel.selectedID == nil ? "Criar projeto" : "Salvar") { viewModel.save() }
                    .disabled(viewModel.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 760, height: 760)
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Apagar projeto", role: .destructive) { viewModel.confirmDeletion() }
            Button("Cancelar", role: .cancel) { viewModel.pendingDeletion = nil }
        } message: {
            Text(deletionMessage)
        }
        .confirmationDialog(
            "Apagar o documento \"\(viewModel.pendingDocumentDeletion?.title ?? "")\"?",
            isPresented: Binding(
                get: { viewModel.pendingDocumentDeletion != nil },
                set: { if !$0 { viewModel.pendingDocumentDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Apagar documento", role: .destructive) { viewModel.confirmDocumentDeletion() }
            Button("Cancelar", role: .cancel) { viewModel.pendingDocumentDeletion = nil }
        } message: {
            Text("O texto é apagado de vez.")
        }
    }

    private var deletionTitle: String {
        guard let pending = viewModel.pendingDeletion else { return "" }
        return "Apagar \"\(pending.project.title)\"?"
    }

    private var deletionMessage: String {
        guard let pending = viewModel.pendingDeletion else { return "" }
        let tasks = switch pending.taskCount {
        case 0: "Nenhuma tarefa está neste projeto."
        case 1: "1 tarefa fica sem projeto. Nenhuma tarefa é apagada."
        default: "\(pending.taskCount) tarefas ficam sem projeto. Nenhuma tarefa é apagada."
        }
        let documents = switch pending.documentCount {
        case 0: ""
        case 1: " O documento do projeto também é apagado."
        default: " Os \(pending.documentCount) documentos do projeto também são apagados."
        }
        return tasks + documents
    }

    // MARK: - Lista

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                viewModel.newProject()
            } label: {
                Label("Novo projeto", systemImage: "plus")
            }

            if viewModel.projects.isEmpty {
                Text("Nenhum projeto cadastrado.")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.projects, selection: Binding(
                    get: { viewModel.selectedID },
                    set: { id in
                        if let project = viewModel.projects.first(where: { $0.id == id }) { viewModel.select(project) }
                    })
                ) { project in
                    projectRow(project).tag(project.id)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Image(systemName: project.symbolName)
                .foregroundStyle(project.color.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.code.map { "\($0) · \(project.title)" } ?? project.title)
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                if let due = project.dueDate {
                    Text(due.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10))
                        .foregroundStyle(viewModel.isOverdue(project) ? Brand.danger : Brand.textFaint)
                }
            }
            Spacer(minLength: 0)
            let count = viewModel.openCounts[project.id] ?? 0
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
                    .help("\(count) tarefa(s) aberta(s)")
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Formulário

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            Form {
                TextField("Título", text: $viewModel.title)
                    .onSubmit { viewModel.save() }

                // RF-09.22: "PSC" + número → tarefas criadas/associadas ganham "PSC0001", "PSC0002"…
                LabeledContent("Código") {
                    HStack(spacing: 8) {
                        TextField("", text: $viewModel.code, prompt: Text("ex.: PSC"))
                            .labelsHidden()
                            .frame(width: 80)
                        Text(viewModel.selectedID == nil ? "Número inicial" : "Próximo número")
                            .foregroundStyle(Brand.textSecondary)
                        TextField("", value: $viewModel.nextCodeNumber, format: .number.grouping(.never))
                            .labelsHidden()
                            .frame(width: 70)
                            .disabled(viewModel.code.isEmpty)
                        Stepper("", value: $viewModel.nextCodeNumber, in: 1...9_999_999)
                            .labelsHidden()
                            .disabled(viewModel.code.isEmpty)
                    }
                }
                if !viewModel.code.isEmpty {
                    Text("Próxima tarefa: \(Project.taskCode(prefix: viewModel.code, number: max(viewModel.nextCodeNumber, 1))). Subtarefas não ganham código.")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textSecondary)
                }

                LabeledContent("Data de cadastro") {
                    Text(viewModel.createdAtText ?? "—")
                        .foregroundStyle(Brand.textSecondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Toggle("Vencimento", isOn: $viewModel.hasDueDate)
                    DatePicker("", selection: $viewModel.dueDate, displayedComponents: [.date])
                        .labelsHidden()
                        .disabled(!viewModel.hasDueDate)
                        .opacity(viewModel.hasDueDate ? 1 : 0.4)
                }

                TextField("Descrição", text: $viewModel.details, axis: .vertical)
                    .lineLimit(3...6)

                LabeledContent("Cor") {
                    LazyVGrid(columns: colorColumns, alignment: .leading, spacing: 8) {
                        ForEach(ProjectColor.allCases, id: \.self) { color in
                            colorSwatch(color)
                        }
                    }
                }

                LabeledContent("Ícone") {
                    LazyVGrid(columns: iconColumns, alignment: .leading, spacing: 6) {
                        ForEach(ProjectIcon.curated, id: \.self) { symbol in
                            iconButton(symbol)
                        }
                    }
                }

            }
            .formStyle(.grouped)

            // Salvar/Criar fica no rodapé do sheet, ao lado de Fechar.
            if viewModel.selectedID != nil {
                HStack {
                    Button(role: .destructive) {
                        viewModel.requestDeletion()
                    } label: {
                        Label("Apagar", systemImage: "trash")
                    }
                    Button {
                        viewModel.showTasks()
                    } label: {
                        Label("Ver tarefas", systemImage: "checklist")
                    }
                    .help("Filtra a janela por este projeto — tarefas criadas lá entram nele")
                    Spacer()
                }
                documentsSection
            }
        }
    }

    // MARK: - Documentos (FEAT-009)

    /// Documentos em markdown do projeto: cada um abre na própria janela (a mesma do documento
    /// da tarefa, com o título editável lá).
    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Documentos")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                TextField("Título do novo documento", text: $viewModel.newDocumentTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createDocument)
                Button(action: createDocument) {
                    Label("Novo documento", systemImage: "doc.badge.plus")
                }
            }
            if viewModel.documents.isEmpty {
                Text("Nenhum documento. Use para especificação, atas, referências…")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textFaint)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(viewModel.documents) { document in
                            documentRow(document)
                        }
                    }
                }
                .frame(maxHeight: 130)
            }
        }
    }

    private func createDocument() {
        if let id = viewModel.createDocument() { openWindow.projectDocument(id) }
    }

    private func documentRow(_ document: ProjectDocumentSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(Brand.cyan)
            Button(document.title) { openWindow.projectDocument(document.id) }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.textPrimary)
                .lineLimit(1)
                .help("Abrir o documento")
            Spacer(minLength: 8)
            Text(document.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 10))
                .foregroundStyle(Brand.textFaint)
                .help("Última alteração")
            Button {
                viewModel.pendingDocumentDeletion = document
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Apagar documento")
            .accessibilityLabel("Apagar documento \(document.title)")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Brand.surface))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openWindow.projectDocument(document.id) }
    }

    private func colorSwatch(_ color: ProjectColor) -> some View {
        let selected = viewModel.color == color
        return Button {
            viewModel.color = color
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Brand.textPrimary, lineWidth: selected ? 2 : 0).padding(-3))
        }
        .buttonStyle(.plain)
        .help(color.displayName)
        .accessibilityLabel("Cor \(color.displayName)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func iconButton(_ symbol: String) -> some View {
        let selected = viewModel.icon == symbol
        return Button {
            viewModel.icon = symbol
        } label: {
            Image(systemName: symbol)
                .frame(width: 28, height: 24)
                .foregroundStyle(selected ? viewModel.color.color : Brand.textSecondary)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? viewModel.color.color.opacity(0.15) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
