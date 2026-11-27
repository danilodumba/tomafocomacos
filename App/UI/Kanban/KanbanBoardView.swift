import SwiftUI
import TomafocoDomain

/// Uma janela por quadro (FEAT-008): o `WindowGroup(for: UUID)` passa o id do quadro, e trocar de
/// quadro pelo seletor da barra atualiza esse valor — reabrir o mesmo quadro traz esta janela, e
/// a restauração de janelas reabre o quadro certo. O VM é `@StateObject`: nasce uma vez por janela.
struct KanbanBoardWindow: View {
    static let sceneID = "kanban"

    @Binding var boardID: UUID?
    @StateObject private var viewModel: KanbanViewModel
    let documentIndex: TaskDocumentIndex

    init(boardID: Binding<UUID?>, documentIndex: TaskDocumentIndex,
         viewModel: @autoclosure @escaping () -> KanbanViewModel) {
        _boardID = boardID
        self.documentIndex = documentIndex
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        KanbanBoardView(viewModel: viewModel, documentIndex: documentIndex)
            .navigationTitle(viewModel.board?.name ?? "Kanban")
            .onChange(of: viewModel.boardID) { _, id in
                if id != boardID { boardID = id }
            }
    }
}

/// Janela Kanban (FEAT-005): uma coluna por raia, cartões arrastáveis entre colunas. Soltar na
/// raia Done conclui; cada movimentação vai para o histórico da tarefa. Janela própria para
/// poder usar tela cheia e Split View.
struct KanbanBoardView: View {
    @ObservedObject var viewModel: KanbanViewModel
    /// Selo "tem documento" (FEAT-007) — observado direto: nested ObservableObject não propaga.
    @ObservedObject var documentIndex: TaskDocumentIndex
    @Environment(\.openWindow) private var openWindow
    /// Coluna sob o arraste — destaque visual.
    @State private var targetedLaneID: UUID?

    private let columnSpacing: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar

            if let feedback = viewModel.feedback {
                Text(feedback)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textSecondary)
            }

            if viewModel.scopeHasNoTags {
                emptyScope
            } else {
                columnsArea
            }
        }
        .padding(16)
        .onAppear { viewModel.didAppear() }
        .onDisappear { viewModel.didDisappear() }
        .sheet(item: $viewModel.editor) { editor in
            TaskEditorSheet(viewModel: editor, documentIndex: documentIndex)
        }
        .sheet(item: $viewModel.projectsSheet) { projects in
            ProjectsSheet(viewModel: projects)
        }
        .alert("Novo quadro", isPresented: Binding(
            get: { viewModel.newBoardName != nil },
            set: { if !$0 { viewModel.newBoardName = nil } }
        )) {
            TextField("Nome do quadro", text: Binding(
                get: { viewModel.newBoardName ?? "" },
                set: { viewModel.newBoardName = $0 }))
            Button("Criar") { viewModel.createBoard() }
            Button("Cancelar", role: .cancel) { viewModel.newBoardName = nil }
        } message: {
            Text("O quadro novo começa com as raias A fazer, Em andamento e Concluído, e mostra todas as tarefas.")
        }
    }

    // MARK: - Seletor de quadro (FEAT-008)

    private var boardPicker: some View {
        Menu {
            ForEach(viewModel.boards) { board in
                // `Toggle` dá o checkmark nativo do NSMenu no quadro atual.
                Toggle(board.name, isOn: Binding(
                    get: { board.id == viewModel.boardID },
                    set: { if $0 { viewModel.selectBoard(board.id) } }))
            }
            Divider()
            Button("Novo quadro…") { viewModel.beginCreatingBoard() }
        } label: {
            Label(viewModel.board?.name ?? "Kanban", systemImage: "rectangle.split.3x1")
                .font(.system(size: 13, weight: .semibold))
        }
        .fixedSize()
        .help("Trocar de quadro ou criar um novo")
    }

    private var configureBoardButton: some View {
        OpenSettingsControl(tab: .kanban, onOpen: {
            if let id = viewModel.boardID { KanbanSettingsBoard.save(id) }
        }) {
            Label("Configurar quadro…", systemImage: "slider.horizontal.3")
        }
    }

    // MARK: - Barra superior

    private var toolbar: some View {
        HStack(spacing: 10) {
            boardPicker

            Divider().frame(height: 18)

            TextField("Nova tarefa", text: $viewModel.newTitle)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit { viewModel.addTask() }

            Menu {
                // Com escopo por tag, tarefa sem tag nasceria fora do quadro e sumiria.
                if !viewModel.scopeIsByTag {
                    Button("Sem tag") { viewModel.newTag = nil }
                    Divider()
                }
                ForEach(viewModel.tagFilterOptions, id: \.self) { tag in
                    Button { viewModel.newTag = tag } label: {
                        Label(tag, systemImage: viewModel.newTag == tag ? "checkmark" : "")
                    }
                }
            } label: {
                Label(viewModel.newTag ?? "Sem tag", systemImage: "tag")
            }
            .fixedSize()
            .help("Tag da nova tarefa")

            Button("Adicionar") { viewModel.addTask() }
                .disabled(!viewModel.canAddTask)
                .help(newTaskHelp)

            Divider().frame(height: 18)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Brand.textFaint)
                TextField("Buscar", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 130)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.surface))

            Menu {
                Button("Todas") { viewModel.tagFilter = nil }
                Divider()
                ForEach(viewModel.tagFilterOptions, id: \.self) { tag in
                    Button { viewModel.tagFilter = tag } label: {
                        Label(tag, systemImage: viewModel.tagFilter == tag ? "checkmark" : "")
                    }
                }
            } label: {
                Label(viewModel.tagFilter ?? "Tag", systemImage: "line.3.horizontal.decrease.circle")
            }
            .fixedSize()

            if viewModel.showsProjectFilter {
                ProjectFilterMenu(projects: viewModel.projects, filter: $viewModel.projectFilter)
            }

            Picker("Vencimento", selection: $viewModel.dueFilter) {
                ForEach(TaskDueFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Picker("Ordenar", selection: $viewModel.sortOrder) {
                ForEach(TaskSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Spacer()

            // Espelho do botão "Kanban" da janela Tarefas: as duas janelas se abrem mutuamente.
            Button {
                openWindow(id: "tasks")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Tarefas", systemImage: "checklist")
            }
            .help("Abrir a janela de Tarefas")

            Button {
                viewModel.openProjects()
            } label: {
                Label("Projetos…", systemImage: "folder")
            }

            configureBoardButton
        }
        .font(.system(size: 12))
    }

    /// Com projeto filtrado, a tarefa nasce nele (FEAT-006).
    private var newTaskHelp: String {
        guard let project = viewModel.newTaskProject else { return "Cria na primeira raia" }
        return "Cria na primeira raia, no projeto \(project.title)"
    }

    private var emptyScope: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag.slash")
                .font(.system(size: 28))
                .foregroundStyle(Brand.textFaint)
            Text("Nenhuma tag selecionada — ajuste em Configurações › Kanban.")
                .font(.system(size: 13))
                .foregroundStyle(Brand.textSecondary)
            configureBoardButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Colunas

    /// Em janela pequena as colunas ficam com 260pt e o quadro rola na horizontal; em tela
    /// cheia crescem até 360pt para aproveitar a largura.
    private var columnsArea: some View {
        GeometryReader { geo in
            let columns = viewModel.columns
            let count = CGFloat(max(columns.count, 1))
            let fitted = (geo.size.width - columnSpacing * (count - 1)) / count
            let width = min(max(260, fitted), 360)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(columns) { column in
                        columnView(column, width: width, height: geo.size.height)
                    }
                }
            }
        }
    }

    private func columnView(_ column: KanbanColumn, width: CGFloat, height: CGFloat) -> some View {
        let targeted = targetedLaneID == column.lane.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if column.lane.isDone {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.cyan)
                }
                Text(column.lane.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                Text("\(column.tasks.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Brand.textFaint)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Brand.surface))
                Spacer()
            }
            .padding(.horizontal, 4)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if column.tasks.isEmpty {
                        Text(viewModel.hasActiveFilters ? "Nada com esses filtros." : "Solte tarefas aqui.")
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.textFaint)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    ForEach(column.tasks) { task in
                        card(task)
                    }
                }
                .padding(2)
            }
        }
        .padding(10)
        .frame(width: width, height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(targeted ? Brand.cyan.opacity(0.12) : Brand.surface.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(targeted ? Brand.cyan : Brand.surfaceStroke, lineWidth: targeted ? 2 : 1)
        )
        .dropDestination(for: String.self) { items, _ in
            viewModel.handleDrop(items, on: column.lane)
        } isTargeted: { isTargeted in
            if isTargeted {
                targetedLaneID = column.lane.id
            } else if targetedLaneID == column.lane.id {
                targetedLaneID = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Raia \(column.lane.title), \(column.tasks.count) tarefa(s)")
    }

    // MARK: - Cartão

    private func card(_ task: FocusTask) -> some View {
        let overdue = task.isOverdue(now: viewModel.now)
        let urgent = task.showsUrgent
        let priority = TaskPriority(rawPriority: task.priority)
        let busy = viewModel.busyTaskIDs.contains(task.id)
        let project = viewModel.project(of: task)
        return VStack(alignment: .leading, spacing: 6) {
            // Linha de topo: projeto primeiro, depois o selo de urgente (FEAT-006).
            if project != nil || urgent {
                HStack(spacing: 6) {
                    if let project {
                        ProjectBadge(project: project)
                    }
                    if urgent {
                        UrgentBadge()
                    }
                }
            }
            HStack(alignment: .top, spacing: 6) {
                if priority != .none {
                    Text(priority.glyph)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(priority.displayColor)
                }
                Text(task.displayTitle)
                    .font(.system(size: 12, weight: urgent ? .bold : .medium))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? Brand.textFaint
                                     : (overdue || urgent ? Brand.danger : Brand.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if busy {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Movendo tarefa")
                }
            }

            if let notes = task.notes {
                Text(notes)
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textFaint)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Metadados um por linha: na largura do cartão (260–360pt) a linha única cortava
            // data/link e empurrava o histórico e o pai para fora. Ordem: pai/subtarefas,
            // vencimento, link, e por fim "Diária" + histórico juntos (curtos, cabem lado a lado).
            VStack(alignment: .leading, spacing: 3) {
                // FEAT-003: pai mostra o progresso; subtarefa mostra de quem é (cartão próprio,
                // move independente).
                if let parentTitle = viewModel.parentTitle(of: task) {
                    Label(parentTitle, systemImage: "arrow.turn.down.right")
                        .foregroundStyle(Brand.textFaint)
                        .lineLimit(1)
                        .help("Subtarefa de \"\(parentTitle)\"")
                } else {
                    let progress = viewModel.subtaskProgress(of: task)
                    if progress.total > 0 {
                        Label("\(progress.done)/\(progress.total)", systemImage: "checklist")
                            .foregroundStyle(progress.done == progress.total ? Brand.cyan : Brand.textFaint)
                            .help("\(progress.done) de \(progress.total) subtarefa(s) concluída(s)")
                    }
                }
                if let due = task.dueDate {
                    Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        .foregroundStyle(overdue ? Brand.danger : Brand.textFaint)
                }
                if let completed = task.completedAt {
                    Label(completed.formatted(date: .abbreviated, time: .shortened), systemImage: "checkmark.circle")
                        .foregroundStyle(Brand.cyan)
                        .help("Concluída em \(completed.formatted(date: .long, time: .shortened))")
                }
                if let url = task.linkURL {
                    Link(destination: url) {
                        Label(url.host ?? "Link", systemImage: "link")
                            .lineLimit(1)
                    }
                    .foregroundStyle(Brand.cyan)
                    .help(url.absoluteString)
                }
                let hasDocument = documentIndex.contains(task.id)
                if task.repeatsDaily || !task.history.isEmpty || hasDocument {
                    HStack(spacing: 8) {
                        if let recurrence = task.recurrence {
                            RecurrenceBadge(recurrence: recurrence)
                        }
                        if !task.history.isEmpty {
                            Label("\(task.history.count)", systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(Brand.textFaint)
                                .help("\(task.history.count) entrada(s) no histórico")
                        }
                        if hasDocument {
                            Button { openWindow.taskDocument(task.id) } label: { DocumentBadge() }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .font(.system(size: 10))

            if !task.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(task.tags, id: \.self) { TagChip(tag: $0) }
                }
            }
        }
        .padding(10)
        .padding(.leading, project == nil ? 0 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // FEAT-006: faixa da cor do projeto na borda esquerda do cartão.
        .overlay(alignment: .leading) {
            if let project {
                ProjectStripe(project: project)
                    .padding(.vertical, 6)
                    .padding(.leading, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(urgent ? Brand.danger.opacity(0.10) : Brand.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(urgent ? Brand.danger : Brand.surfaceStroke, lineWidth: urgent ? 2 : 1)
        )
        .opacity(busy ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { viewModel.beginEditing(task) }
        .draggable(task.id.uuidString)
        .contextMenu { cardMenu(task) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Duplo clique edita. Use o menu de contexto para mover de raia.")
    }

    /// "Mover para ▸" é a alternativa acessível (VoiceOver/teclado) ao arraste.
    @ViewBuilder
    private func cardMenu(_ task: FocusTask) -> some View {
        Button("Editar…") { viewModel.beginEditing(task) }
        Button("Abrir documento") { openWindow.taskDocument(task.id) }
        Button("Duplicar") { viewModel.duplicate(task) }
        if !task.isSubtask {
            // A criação fica no formulário do pai (campo "Nova subtarefa").
            Button("Adicionar subtarefa…") { viewModel.beginEditing(task) }
        }
        Toggle("Urgente", isOn: Binding(
            get: { task.isUrgent },
            set: { viewModel.setUrgent(task, $0) }))
        RecurrenceMenu(task: task,
                       set: { viewModel.setRecurrence(task, $0) },
                       customize: { viewModel.beginEditing(task) })
        if let url = task.linkURL {
            Link("Abrir link", destination: url)
        }
        if let board = viewModel.board {
            let current = board.lane(for: task)
            Menu("Mover para") {
                ForEach(board.lanes) { lane in
                    Button(lane.title) { viewModel.move(task, to: lane) }
                        .disabled(lane.id == current.id || viewModel.isMutatingTask)
                }
            }
        }
    }
}
