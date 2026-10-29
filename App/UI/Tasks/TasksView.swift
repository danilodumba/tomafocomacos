import SwiftUI
import TomafocoDomain

/// Janela Tarefas (RF-09). Ativas por padrão; concluídas aparecem opcionalmente no fim da
/// lista (checkbox "Mostrar concluídas") e seguem nos Relatórios (item 3).
/// Traz busca, ordenação, filtros, prioridade e destaque de atraso (itens 4–7).
struct TasksView: View {
    @ObservedObject var viewModel: TasksViewModel
    @Environment(\.openWindow) private var openWindow
    /// Linha sob o cursor durante o arraste de outra tarefa (FEAT-003: soltar = virar subtarefa).
    @State private var targetedTaskID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            addRow
            controlBar

            if let feedback = viewModel.feedback {
                feedbackRow(feedback)
            }

            // Uma avaliação por render (filtro + ordenação) — antes eram duas (FEAT-006).
            let displayed = viewModel.displayedTasks
            List {
                if displayed.isEmpty {
                    Text(emptyMessage)
                        .foregroundStyle(Brand.textFaint)
                }
                ForEach(displayed) { task in
                    row(task)
                    // FEAT-003: subtarefas aninhadas logo abaixo do pai — linhas completas
                    // (concluir, prioridade, editar, apagar), só indentadas.
                    if viewModel.isExpanded(task) {
                        ForEach(viewModel.children(of: task)) { child in
                            row(child, depth: 1)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(16)
        .onAppear { viewModel.didAppear() }
        .onDisappear { viewModel.didDisappear() }
        .sheet(isPresented: $viewModel.showsImportSheet) { importSheet }
        .sheet(isPresented: $viewModel.showsTagManager) {
            TagManagerView(viewModel: viewModel)
        }
        .sheet(item: $viewModel.bulkAdd) { bulk in
            BulkAddTasksView(viewModel: bulk)
        }
        .sheet(item: $viewModel.projectsSheet) { projects in
            ProjectsSheet(viewModel: projects)
        }
        .sheet(item: $viewModel.editor) { editor in
            TaskEditorSheet(viewModel: editor)
        }
        // FEAT-003: apagar o pai leva as subtarefas junto — confirmar antes.
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Apagar tudo", role: .destructive) { viewModel.confirmPendingDeletion() }
            Button("Cancelar", role: .cancel) { viewModel.pendingDeletion = nil }
        } message: {
            Text("As subtarefas são apagadas junto com a tarefa. Isso não pode ser desfeito.")
        }
    }

    private var deletionTitle: String {
        guard let task = viewModel.pendingDeletion else { return "" }
        let count = viewModel.subtaskProgress(of: task).total
        return "Apagar \"\(task.title)\" e \(count) subtarefa\(count == 1 ? "" : "s")?"
    }

    private var emptyMessage: String {
        if !viewModel.activeTasks.isEmpty
            || (viewModel.showsCompleted && !viewModel.completedTasks.isEmpty) {
            return "Nenhuma tarefa corresponde aos filtros."
        }
        return "Nenhuma tarefa ativa. Crie acima ou importe do Lembretes."
    }

    /// Com projeto filtrado, a tarefa nasce nele (FEAT-006) — o campo avisa.
    private var newTaskPlaceholder: String {
        guard let project = viewModel.newTaskProject else { return "Nova tarefa" }
        return "Nova tarefa em \(project.title)"
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField(newTaskPlaceholder, text: $viewModel.newTitle)
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
                ForEach(TaskSortOrder.allCases) { order in
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

            ProjectFilterMenu(projects: viewModel.projects, filter: $viewModel.projectFilter)

            Picker("Vencimento", selection: $viewModel.dueFilter) {
                ForEach(TaskDueFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Toggle("Mostrar concluídas", isOn: $viewModel.showsCompleted)
                .toggleStyle(.checkbox)

            Spacer()

            Button {
                viewModel.openProjects()
            } label: {
                Label("Projetos…", systemImage: "folder")
            }

            Button {
                viewModel.showsTagManager = true
            } label: {
                Label("Tags…", systemImage: "tag.circle")
            }

            // FEAT-005: o quadro mora em janela própria (tela cheia / Split View).
            Button {
                openWindow(id: "kanban")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Kanban", systemImage: "rectangle.split.3x1")
            }
            .help("Abrir o quadro Kanban (⌥⌘K)")
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

    // MARK: - Subtarefas (FEAT-003)

    /// Chip `checklist 2/5 subtarefas` + chevron na linha do título (era um badge miúdo no meio
    /// dos metadados — passava despercebido). Clicar abre/fecha as subtarefas embaixo da linha.
    /// Cyan cheio quando tudo está feito.
    private func subtaskBadge(_ task: FocusTask) -> some View {
        let progress = viewModel.subtaskProgress(of: task)
        let expanded = viewModel.isExpanded(task)
        let allDone = progress.done == progress.total
        let tint = allDone ? Brand.cyan : Brand.textSecondary
        return Button {
            viewModel.toggleExpanded(task.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                Text("\(progress.done)/\(progress.total)")
                    .fontWeight(.semibold)
                Text(progress.total == 1 ? "subtarefa" : "subtarefas")
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(expanded ? "Ocultar subtarefas" : "Mostrar subtarefas")
        .accessibilityLabel("\(progress.done) de \(progress.total) subtarefas · \(expanded ? "ocultar" : "mostrar")")
    }

    /// Submenu "Tornar subtarefa de ▸" — alternativa acessível (VoiceOver/teclado) ao arraste.
    @ViewBuilder
    private func makeSubtaskMenu(_ task: FocusTask) -> some View {
        let parents = viewModel.possibleParents(for: task)
        if !parents.isEmpty {
            Menu("Tornar subtarefa de") {
                ForEach(parents) { parent in
                    Button(parent.title) { viewModel.makeSubtask(task, of: parent) }
                }
            }
            .disabled(viewModel.isMutatingTask)
        }
    }

    // MARK: - Prioridade

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

    /// `depth == 1` é subtarefa (FEAT-003): mesma linha, indentada e com a seta de "filha de".
    private func row(_ task: FocusTask, depth: Int = 0) -> some View {
        let overdue = task.isOverdue(now: viewModel.now)
        let urgent = task.showsUrgent
        let targeted = targetedTaskID == task.id
        let project = viewModel.project(of: task)
        return HStack(spacing: 10) {
            // FEAT-006: faixa com a cor do projeto. Urgente perdeu a faixa vermelha (decisão 10)
            // — segue com selo, título vermelho/negrito e fundo.
            if let project {
                ProjectStripe(project: project)
            }
            if depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textFaint)
                    .padding(.leading, CGFloat(depth) * 22)
                    .accessibilityHidden(true)
            }
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
                    // Projeto primeiro, depois urgente — mesmo selo do cartão do Kanban (FEAT-006).
                    // Subtarefa não repete: herda o projeto do pai, que está logo acima.
                    if let project, depth == 0 {
                        ProjectBadge(project: project)
                    }
                    if urgent {
                        UrgentBadge()
                    }
                    if overdue {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.danger)
                    }
                    Text(task.title)
                        .fontWeight(urgent ? .semibold : .regular)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? Brand.textFaint
                                         : (overdue || urgent ? Brand.danger : Brand.textPrimary))
                    if depth == 0, viewModel.subtaskProgress(of: task).total > 0 {
                        subtaskBadge(task)
                    }
                }
                HStack(spacing: 6) {
                    if task.source == .reminders {
                        Label("Lembretes", systemImage: "square.and.arrow.down")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.textFaint)
                    }
                    if task.repeatsDaily {
                        Label("Diária", systemImage: "repeat")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.cyan)
                            .help("Repete todo dia: ao concluir, uma cópia é criada com vencimento amanhã")
                    }
                    if let due = task.dueDate {
                        Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .font(.system(size: 10))
                            .foregroundStyle(overdue ? Brand.danger : Brand.textFaint)
                    }
                    if let url = task.linkURL {
                        Link(destination: url) {
                            Label(url.host ?? "Link", systemImage: "link")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Brand.cyan)
                        .help(url.absoluteString)
                    }
                    if !task.history.isEmpty {
                        Label("\(task.history.count)", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.textFaint)
                            .help("\(task.history.count) entrada(s) no histórico")
                    }
                    ForEach(task.tags, id: \.self) { tag in
                        TagChip(tag: tag)
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
        .padding(.horizontal, urgent || targeted ? 6 : 0)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(targeted ? Brand.cyan.opacity(0.12)
                      : (urgent ? Brand.danger.opacity(0.08) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Brand.cyan, lineWidth: targeted ? 2 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { viewModel.beginEditing(task) }
        // FEAT-003: arrastar uma linha sobre a outra torna a arrastada subtarefa da alvo. O
        // payload é o UUID em texto (mesmo formato dos cartões do Kanban). A regra (pai com
        // filhas, alvo já subtarefa…) mora no use case; a recusa vira `feedback` e o arraste volta.
        .draggable(task.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            viewModel.handleDrop(items, onto: task)
        } isTargeted: { isTargeted in
            if isTargeted {
                targetedTaskID = task.id
            } else if targetedTaskID == task.id {
                targetedTaskID = nil
            }
        }
        .contextMenu {
            Button("Editar…") { viewModel.beginEditing(task) }
            if depth == 0 {
                // A criação fica no formulário do pai (campo "Nova subtarefa").
                Button("Adicionar subtarefa…") { viewModel.beginEditing(task) }
            }
            makeSubtaskMenu(task)
            Toggle("Urgente", isOn: Binding(
                get: { task.isUrgent },
                set: { viewModel.setUrgent(task, $0) }))
            Toggle("Repetir diariamente", isOn: Binding(
                get: { task.repeatsDaily },
                set: { viewModel.setRepeatsDaily(task, $0) }))
            if let url = task.linkURL {
                Link("Abrir link", destination: url)
            }
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
