import SwiftUI
import TomafocoDomain

/// Janela Tarefas (RF-09). Ativas por padrão; concluídas aparecem opcionalmente no fim da
/// lista (checkbox "Mostrar concluídas") e seguem nos Relatórios (item 3).
/// Traz busca, ordenação, filtros, prioridade e destaque de atraso (itens 4–7).
struct TasksView: View {
    @ObservedObject var viewModel: TasksViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            addRow
            controlBar

            if let feedback = viewModel.feedback {
                feedbackRow(feedback)
            }

            List {
                if viewModel.displayedTasks.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(Brand.textFaint)
                }
                ForEach(viewModel.displayedTasks) { task in
                    row(task)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(16)
        .onAppear { viewModel.reload() }
        .sheet(isPresented: $viewModel.showsImportSheet) { importSheet }
        .sheet(isPresented: $viewModel.showsTagManager) {
            TagManagerView(viewModel: viewModel)
        }
        .sheet(item: $viewModel.editingTask) { _ in editSheet }
    }

    private var emptyMessage: String {
        if !viewModel.activeTasks.isEmpty
            || (viewModel.showsCompleted && !viewModel.completedTasks.isEmpty) {
            return "Nenhuma tarefa corresponde aos filtros."
        }
        return "Nenhuma tarefa ativa. Crie acima ou importe do Lembretes."
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("Nova tarefa", text: $viewModel.newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.addTask() }

            HStack(spacing: 4) {
                TextField("tags (vírgula)", text: $viewModel.newTags)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                    .onSubmit { viewModel.addTask() }
                tagSuggestionsMenu(for: $viewModel.newTags)
            }

            Button("Adicionar") { viewModel.addTask() }
                .disabled(viewModel.newTitle.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                Task { await viewModel.prepareImport() }
            } label: {
                if viewModel.isImporting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Importar do Lembretes…", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(viewModel.isImporting)
        }
    }

    /// Autocomplete simples: menu com as tags já conhecidas; clicar acrescenta ao campo (item 1).
    /// Recebe o `Binding` porque serve tanto o campo de criação quanto o de edição.
    private func tagSuggestionsMenu(for text: Binding<String>) -> some View {
        Menu {
            if viewModel.knownTags.isEmpty {
                Text("Nenhuma tag ainda")
            } else {
                ForEach(viewModel.knownTags, id: \.self) { tag in
                    Button(tag) { appendTag(tag, to: text) }
                }
            }
        } label: {
            Image(systemName: "tag")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Adicionar uma tag existente")
    }

    /// Acrescenta uma tag ao texto de um campo (evitando duplicar), respeitando vírgulas.
    private func appendTag(_ tag: String, to text: Binding<String>) {
        let existing = TasksViewModel.parseTags(text.wrappedValue)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !existing.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
        let trimmed = text.wrappedValue.trimmingCharacters(in: .whitespaces)
        text.wrappedValue = trimmed.isEmpty ? tag : trimmed + ", " + tag
    }

    // MARK: - Barra de ordenação e filtros (itens 5 e 7)

    private var controlBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Brand.textFaint)
                TextField("Buscar", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 130)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.surface))

            Picker("Ordenar", selection: $viewModel.sortOrder) {
                ForEach(TasksViewModel.SortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

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

            Menu {
                Button("Todas") { viewModel.priorityFilter = nil }
                Divider()
                ForEach([TaskPriority.high, .medium, .low, .none], id: \.self) { p in
                    Button { viewModel.priorityFilter = p } label: {
                        Label(priorityName(p), systemImage: viewModel.priorityFilter == p ? "checkmark" : "")
                    }
                }
            } label: {
                Label(viewModel.priorityFilter.map(priorityName) ?? "Prioridade", systemImage: "flag")
            }
            .fixedSize()

            Toggle("Mostrar concluídas", isOn: $viewModel.showsCompleted)
                .toggleStyle(.checkbox)

            Spacer()

            Button {
                viewModel.showsTagManager = true
            } label: {
                Label("Tags…", systemImage: "tag.circle")
            }
        }
        .font(.system(size: 12))
    }

    // MARK: - Import (RF-09.3)

    private var importSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Importar do Lembretes")
                .font(.system(size: 14, weight: .semibold))

            TextField("Buscar por título…", text: $viewModel.reminderSearch)
                .textFieldStyle(.roundedBorder)

            if viewModel.filteredReminders.isEmpty {
                Text(viewModel.availableReminders.isEmpty
                     ? "Nenhum lembrete pendente."
                     : "Nada encontrado para essa busca.")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textFaint)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List(viewModel.filteredReminders) { reminder in
                    reminderRow(reminder)
                }
                .frame(minHeight: 220)
            }

            HStack {
                Spacer()
                Button("Concluir") { viewModel.showsImportSheet = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380, height: 420)
    }

    private func reminderRow(_ reminder: ImportedReminder) -> some View {
        // Só tarefa ATIVA bloqueia: com a cópia local concluída o lembrete volta a ser
        // importável (recorrente), sinalizado como reimportação.
        let alreadyImported = viewModel.importedReminderIDs.contains(reminder.reminderID)
        let isReimport = viewModel.reimportableReminderIDs.contains(reminder.reminderID)
        return Button {
            Task { await viewModel.importOne(reminder) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName(imported: alreadyImported, reimport: isReimport))
                    .foregroundStyle(alreadyImported ? Brand.cyan : Brand.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .foregroundStyle(alreadyImported ? Brand.textFaint : Brand.textPrimary)
                    HStack(spacing: 8) {
                        Text(reminder.listName)
                            .foregroundStyle(Brand.textFaint)
                        if let due = reminder.dueDate {
                            Label(due.formatted(date: .abbreviated, time: .omitted),
                                  systemImage: "calendar")
                                .foregroundStyle(Brand.textFaint)
                        }
                    }
                    .font(.system(size: 10))
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyImported)
    }

    private func iconName(imported: Bool, reimport: Bool) -> String {
        if imported { return "checkmark.circle.fill" }
        return reimport ? "arrow.clockwise.circle" : "plus.circle"
    }

    // MARK: - Chips e prioridade

    private func tagChip(_ tag: String) -> some View {
        Text(tag)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Brand.cyan)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Brand.cyan.opacity(0.14), in: Capsule())
    }

    private func priorityName(_ p: TaskPriority) -> String {
        switch p {
        case .none: return "Nenhuma"
        case .low: return "Baixa"
        case .medium: return "Média"
        case .high: return "Alta"
        }
    }

    private func priorityColor(_ p: TaskPriority) -> Color {
        switch p {
        case .none: return Brand.textFaint
        case .low: return Brand.textSecondary
        case .medium: return .orange
        case .high: return Brand.danger
        }
    }

    private func priorityGlyph(_ p: TaskPriority) -> String {
        switch p {
        case .none: return ""
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }

    /// Menu de prioridade estilo Lembretes: nenhuma / baixa / média / alta (item 4).
    private func priorityControl(_ task: FocusTask) -> some View {
        let current = TaskPriority(rawPriority: task.priority)
        return Menu {
            ForEach([TaskPriority.none, .low, .medium, .high], id: \.self) { p in
                Button { viewModel.setPriority(task, p) } label: {
                    Label(priorityName(p), systemImage: current == p ? "checkmark" : "")
                }
            }
        } label: {
            if current == .none {
                Image(systemName: "flag")
                    .foregroundStyle(Brand.textFaint)
            } else {
                Text(priorityGlyph(current))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(priorityColor(current))
            }
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Prioridade: \(priorityName(current))")
    }

    // MARK: - Formulário de edição (RF-09.6)

    /// Edita título, prioridade, tags, observação e data/hora de vencimento de uma vez.
    /// Nada é gravado até "Salvar" — erro de validação mantém o sheet aberto.
    private var editSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Editar tarefa")
                .font(.system(size: 14, weight: .semibold))

            Form {
                TextField("Título", text: $viewModel.editTitle)
                    .onSubmit { viewModel.saveEdit() }

                Picker("Prioridade", selection: $viewModel.editPriority) {
                    ForEach([TaskPriority.none, .low, .medium, .high], id: \.self) { p in
                        Text(priorityName(p)).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 4) {
                    TextField("Tags (vírgula)", text: $viewModel.editTags)
                    tagSuggestionsMenu(for: $viewModel.editTags)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Vencimento", isOn: $viewModel.editHasDueDate)
                    DatePicker(
                        "", selection: $viewModel.editDueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .disabled(!viewModel.editHasDueDate)
                    .opacity(viewModel.editHasDueDate ? 1 : 0.4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Observação")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textSecondary)
                    TextEditor(text: $viewModel.editNotes)
                        .font(.system(size: 12))
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Brand.textFaint.opacity(0.4), lineWidth: 1)
                        )
                }
            }
            .formStyle(.grouped)

            if let error = viewModel.editFeedback {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.danger)
            }

            HStack {
                Spacer()
                Button("Cancelar") { viewModel.cancelEditing() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") { viewModel.saveEdit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func feedbackRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Brand.textSecondary)
            if viewModel.accessDenied {
                Button("Abrir Ajustes de Privacidade…") { viewModel.openPrivacySettings() }
                    .font(.system(size: 12))
            }
        }
    }

    private func row(_ task: FocusTask) -> some View {
        let overdue = viewModel.isOverdue(task)
        return HStack(spacing: 10) {
            Button {
                viewModel.setCompleted(task, !task.isCompleted)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Brand.cyan : Brand.textFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Reabrir tarefa" : "Concluir tarefa")

            priorityControl(task)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if overdue {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.danger)
                    }
                    Text(task.title)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? Brand.textFaint
                                         : (overdue ? Brand.danger : Brand.textPrimary))
                }
                HStack(spacing: 6) {
                    if task.source == .reminders {
                        Label("Lembretes", systemImage: "square.and.arrow.down")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.textFaint)
                    }
                    if let due = task.dueDate {
                        Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .font(.system(size: 10))
                            .foregroundStyle(overdue ? Brand.danger : Brand.textFaint)
                    }
                    if let urlString = task.sourceURL, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Label("Link", systemImage: "link")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Brand.cyan)
                    }
                    ForEach(task.tags, id: \.self) { tag in
                        tagChip(tag)
                    }
                }
                if let notes = task.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.textFaint)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button {
                viewModel.beginEditing(task)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.textFaint)
            .accessibilityLabel("Editar tarefa")
            .help("Editar tarefa")

            Button(role: .destructive) {
                viewModel.delete(task)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.textFaint)
            .accessibilityLabel("Apagar tarefa")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { viewModel.beginEditing(task) }
        .contextMenu {
            Button("Editar…") { viewModel.beginEditing(task) }
            Button("Apagar", role: .destructive) { viewModel.delete(task) }
        }
    }
}
