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
        .sheet(item: $viewModel.bulkAdd) { bulk in
            BulkAddTasksView(viewModel: bulk)
        }
        .sheet(item: $viewModel.editingTask) { _ in
            FocusHost { historyFocused in editSheet(historyFocused: historyFocused) }
        }
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
                TagSuggestionsMenu(knownTags: viewModel.knownTags, text: $viewModel.newTags)
            }

            Button("Adicionar") { viewModel.addTask() }
                .disabled(viewModel.newTitle.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                viewModel.beginBulkAdd()
            } label: {
                Image(systemName: "text.badge.plus")
            }
            .help("Adicionar em lote — uma tarefa por linha")
            .accessibilityLabel("Adicionar em lote")

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
                        Label(p.displayName, systemImage: viewModel.priorityFilter == p ? "checkmark" : "")
                    }
                }
            } label: {
                Label(viewModel.priorityFilter.map(\.displayName) ?? "Prioridade", systemImage: "flag")
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

    /// Menu de prioridade estilo Lembretes: nenhuma / baixa / média / alta (item 4).
    private func priorityControl(_ task: FocusTask) -> some View {
        let current = TaskPriority(rawPriority: task.priority)
        return Menu {
            ForEach(TaskPriority.displayOrder, id: \.self) { p in
                Button { viewModel.setPriority(task, p) } label: {
                    Label(p.displayName, systemImage: current == p ? "checkmark" : "")
                }
            }
        } label: {
            if current == .none {
                Image(systemName: "flag")
                    .foregroundStyle(Brand.textFaint)
            } else {
                Text(current.glyph)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(current.displayColor)
            }
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Prioridade: \(current.displayName)")
    }

    // MARK: - Formulário de edição (RF-09.6)

    /// Edita título, prioridade, tags e data/hora de vencimento de uma vez (+ histórico, gravado na hora).
    /// Nada é gravado até "Salvar" — erro de validação mantém o sheet aberto.
    /// `historyFocused`: com o campo de histórico focado, "Salvar" perde o `.defaultAction` —
    /// senão o Return vira key equivalent da janela (roda ANTES do `onSubmit` do campo), salva e
    /// fecha o sheet sem acrescentar a entrada.
    private func editSheet(historyFocused: FocusState<Bool>.Binding) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Editar tarefa")
                .font(.system(size: 14, weight: .semibold))

            Form {
                TextField("Título", text: $viewModel.editTitle)
                    .onSubmit { viewModel.saveEdit() }

                Picker("Prioridade", selection: $viewModel.editPriority) {
                    ForEach(TaskPriority.displayOrder, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 4) {
                    TextField("Tags (vírgula)", text: $viewModel.editTags)
                    TagSuggestionsMenu(knownTags: viewModel.knownTags, text: $viewModel.editTags)
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
            }
            .formStyle(.grouped)

            // Fora do `Form` de propósito: em `.grouped`, linha com `Button` vira alvo de clique
            // inteira — o clique no campo "Nova entrada" ia para o botão e o campo nunca focava.
            historySection(focused: historyFocused)
                .padding(.horizontal, 4)

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
                    .keyboardShortcut(historyFocused.wrappedValue ? nil : .defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    // MARK: - Histórico da tarefa (FEAT-001)

    /// Entradas datadas da tarefa. Ao contrário do resto do formulário, adicionar/apagar aqui
    /// **grava na hora** — histórico é log, não rascunho. A legenda avisa o usuário.
    /// `ScrollView` + `VStack` em vez de `List` (altura previsível dentro do sheet).
    private func historySection(focused: FocusState<Bool>.Binding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Histórico")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textSecondary)
                Text("· gravado na hora")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textFaint)
            }

            HStack(spacing: 6) {
                TextField("Nova entrada", text: $viewModel.newHistoryText)
                    .textFieldStyle(.roundedBorder)
                    .focused(focused)
                    .onSubmit { viewModel.addHistoryEntry() }
                Button("Adicionar") { viewModel.addHistoryEntry() }
                    .disabled(viewModel.newHistoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if viewModel.editingHistory.isEmpty {
                Text("Sem entradas ainda.")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textFaint)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.editingHistory) { entry in
                            historyRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
    }

    private func historyRow(_ entry: TaskHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 10))
                .foregroundStyle(Brand.textFaint)
                .frame(width: 110, alignment: .leading)

            Text(entry.text)
                .font(.system(size: 11))
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(role: .destructive) {
                viewModel.deleteHistoryEntry(entry)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.textFaint)
            .accessibilityLabel("Apagar entrada do histórico")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Brand.surface))
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
            busySwap(task) {
                Button {
                    viewModel.setCompleted(task, !task.isCompleted)
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isCompleted ? Brand.cyan : Brand.textFaint)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isMutatingTask)
                .accessibilityLabel(task.isCompleted ? "Reabrir tarefa" : "Concluir tarefa")
            }

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
                    if !task.history.isEmpty {
                        Label("\(task.history.count)", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.textFaint)
                            .help("\(task.history.count) entrada(s) no histórico")
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

            busySwap(task) {
                Button(role: .destructive) {
                    viewModel.delete(task)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.textFaint)
                .disabled(viewModel.isMutatingTask)
                .accessibilityLabel("Apagar tarefa")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { viewModel.beginEditing(task) }
        .contextMenu {
            Button("Editar…") { viewModel.beginEditing(task) }
            Button("Apagar", role: .destructive) { viewModel.delete(task) }
                .disabled(viewModel.isMutatingTask)
        }
    }

    /// Loading no lugar dos botões de concluir/apagar enquanto a ação da linha está em andamento.
    @ViewBuilder
    private func busySwap(_ task: FocusTask, @ViewBuilder content: () -> some View) -> some View {
        if viewModel.busyTaskIDs.contains(task.id) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
                .accessibilityLabel("Atualizando tarefa")
        } else {
            content()
        }
    }
}

/// Dono do `@FocusState` do formulário de edição. Precisa morar DENTRO do sheet: `@FocusState`
/// declarado na view que apresenta não atravessa a fronteira do sheet de forma confiável.
private struct FocusHost<Content: View>: View {
    @FocusState private var focused: Bool
    let content: (FocusState<Bool>.Binding) -> Content

    var body: some View { content($focused) }
}
