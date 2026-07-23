import SwiftUI
import TomafocoDomain

/// Aba Tarefas da janela "Tarefas & Relatórios" (RF-09).
struct TasksView: View {
    @ObservedObject var viewModel: TasksViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            addRow

            if let feedback = viewModel.feedback {
                feedbackRow(feedback)
            }

            List {
                Section("Ativas") {
                    if viewModel.activeTasks.isEmpty {
                        Text("Nenhuma tarefa ativa. Crie acima ou importe do Lembretes.")
                            .foregroundStyle(Brand.textFaint)
                    }
                    ForEach(viewModel.activeTasks) { task in
                        row(task)
                    }
                }
                if !viewModel.completedTasks.isEmpty {
                    Section("Concluídas") {
                        ForEach(viewModel.completedTasks) { task in
                            row(task)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(16)
        .onAppear { viewModel.reload() }
        .sheet(isPresented: $viewModel.showsImportSheet) { importSheet }
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("Nova tarefa", text: $viewModel.newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.addTask() }

            TextField("tags (vírgula)", text: $viewModel.newTags)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
                .onSubmit { viewModel.addTask() }

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

    /// Picker de lembretes: busca por título + clique importa um por vez (RF-09.3).
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
        let alreadyImported = viewModel.importedReminderIDs.contains(reminder.reminderID)
        return Button {
            Task { await viewModel.importOne(reminder) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: alreadyImported ? "checkmark.circle.fill" : "plus.circle")
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

    private func tagChip(_ tag: String) -> some View {
        Text(tag)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Brand.cyan)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Brand.cyan.opacity(0.14), in: Capsule())
    }

    /// Popover de edição de tags (vírgula separa; normalização no Domain).
    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(.system(size: 13, weight: .semibold))
            TextField("trabalho, estudo…", text: $viewModel.editingTagsText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { viewModel.saveEditingTags() }
            HStack {
                Spacer()
                Button("Cancelar") { viewModel.editingTagsTask = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") { viewModel.saveEditingTags() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
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
        HStack(spacing: 10) {
            Button {
                viewModel.setCompleted(task, !task.isCompleted)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Brand.cyan : Brand.textFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Reabrir tarefa" : "Concluir tarefa")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? Brand.textFaint : Brand.textPrimary)
                HStack(spacing: 6) {
                    if task.source == .reminders {
                        Label("Lembretes", systemImage: "square.and.arrow.down")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.textFaint)
                    }
                    if let due = task.dueDate {
                        Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.textFaint)
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
                viewModel.beginEditingTags(task)
            } label: {
                Image(systemName: "tag")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.textFaint)
            .accessibilityLabel("Editar tags")
            .popover(isPresented: Binding(
                get: { viewModel.editingTagsTask?.id == task.id },
                set: { if !$0 { viewModel.editingTagsTask = nil } }
            )) {
                tagEditor
            }

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
    }
}
