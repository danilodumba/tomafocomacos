import SwiftUI
import TomafocoDomain

/// Aba Kanban das Configurações (FEAT-005; vários quadros desde a FEAT-008): quadros e, para o
/// quadro selecionado, raias, por quantos dias a concluída fica no Done e quais tarefas entram.
/// Observa o VM direto (nested ObservableObject não propaga).
struct KanbanSettingsTab: View {
    @ObservedObject var viewModel: KanbanSettingsViewModel

    var body: some View {
        Form {
            boardsSection
            lanesSection
            doneSection
            scopeSection

            if let feedback = viewModel.feedback {
                Text(feedback)
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { viewModel.didAppear() }
        .onDisappear { viewModel.didDisappear() }
        .confirmationDialog(
            "Apagar a raia \"\(viewModel.pendingDeletion?.lane.title ?? "")\"?",
            isPresented: Binding(
                get: { viewModel.pendingDeletion != nil },
                set: { if !$0 { viewModel.pendingDeletion = nil } }),
            presenting: viewModel.pendingDeletion
        ) { _ in
            Button("Apagar raia", role: .destructive) { viewModel.confirmPendingDeletion() }
            Button("Cancelar", role: .cancel) { viewModel.pendingDeletion = nil }
        } message: { pending in
            Text(pending.openTaskCount == 1
                 ? "1 tarefa volta para \"\(viewModel.firstOpenLaneTitle)\"."
                 : "\(pending.openTaskCount) tarefas voltam para \"\(viewModel.firstOpenLaneTitle)\".")
        }
        .confirmationDialog(
            "Apagar o quadro \"\(viewModel.pendingBoardDeletion?.board.name ?? "")\"?",
            isPresented: Binding(
                get: { viewModel.pendingBoardDeletion != nil },
                set: { if !$0 { viewModel.pendingBoardDeletion = nil } }),
            presenting: viewModel.pendingBoardDeletion
        ) { _ in
            Button("Apagar quadro", role: .destructive) { viewModel.confirmBoardDeletion() }
            Button("Cancelar", role: .cancel) { viewModel.pendingBoardDeletion = nil }
        } message: { pending in
            Text(boardDeletionMessage(pending.openTaskCount))
        }
    }

    private func boardDeletionMessage(_ count: Int) -> String {
        let tasks = count == 0 ? "Nenhuma tarefa aberta está nele."
            : count == 1 ? "1 tarefa aberta está nele." : "\(count) tarefas abertas estão nele."
        return "\(tasks) As tarefas não são apagadas — continuam na lista e nos outros quadros."
    }

    // MARK: - Quadros (FEAT-008)

    private var boardsSection: some View {
        Section {
            Picker("Quadro", selection: Binding(
                get: { viewModel.selectedBoardID },
                set: { if let id = $0 { viewModel.selectBoard(id) } }
            )) {
                ForEach(viewModel.boards) { board in
                    Text(board.name).tag(Optional(board.id))
                }
            }

            if let board = viewModel.board {
                HStack(spacing: 8) {
                    BoardNameField(board: board, viewModel: viewModel)
                    Button(role: .destructive) { viewModel.requestDeleteBoard() } label: {
                        Label("Apagar quadro", systemImage: "trash")
                    }
                    .disabled(!viewModel.canDeleteBoard)
                    .help(viewModel.canDeleteBoard ? "Apagar este quadro" : "É preciso ter pelo menos um quadro")
                }
            }

            HStack(spacing: 8) {
                TextField("Novo quadro", text: $viewModel.newBoardName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.createBoard() }
                Button("Criar quadro") { viewModel.createBoard() }
                    .disabled(viewModel.newBoardName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Quadros")
        } footer: {
            Text("As configurações abaixo valem para o quadro selecionado. Uma tarefa pode aparecer em vários quadros, cada um com sua raia; concluir em qualquer um conclui a tarefa.")
                .font(.system(size: 11))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Raias

    private var lanesSection: some View {
        Section {
            ForEach(viewModel.board?.lanes ?? []) { lane in
                LaneRow(lane: lane, viewModel: viewModel)
            }
            HStack(spacing: 8) {
                TextField("Nova raia", text: $viewModel.newLaneTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.addLane() }
                Button("Adicionar raia") { viewModel.addLane() }
                    .disabled(viewModel.newLaneTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Raias")
        } footer: {
            Text("A raia de concluídas é sempre a última: soltar uma tarefa nela conclui a tarefa.")
                .font(.system(size: 11))
                .foregroundStyle(Brand.textSecondary)
        }
    }

    // MARK: - Concluídas

    private var doneSection: some View {
        Section("Concluídas") {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manter no quadro por")
                        .foregroundStyle(Brand.textPrimary)
                    Text("Depois disso a tarefa some do quadro, mas continua na lista e nos relatórios. 1 dia = só as concluídas hoje.")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(viewModel.doneRetentionDays == 1 ? "1 dia" : "\(viewModel.doneRetentionDays) dias")
                    .monospacedDigit()
                    .foregroundStyle(Brand.textPrimary)
                    .frame(width: 64, alignment: .trailing)
                Stepper("", value: Binding(
                    get: { viewModel.doneRetentionDays },
                    set: { viewModel.setDoneRetentionDays($0) }
                ), in: KanbanBoard.doneRetentionRange)
                .labelsHidden()
            }
        }
    }

    // MARK: - Tarefas no quadro

    private var scopeSection: some View {
        Section("Tarefas no quadro") {
            Picker("Projeto", selection: Binding(
                get: { viewModel.projectScope },
                set: { viewModel.setProjectScope($0) }
            )) {
                Text("Todos os projetos").tag(ProjectFilter.all)
                Text("Sem projeto").tag(ProjectFilter.none)
                if !viewModel.projects.isEmpty { Divider() }
                ForEach(viewModel.projects) { project in
                    Text(project.title).tag(ProjectFilter.project(project.id))
                }
            }

            Picker("", selection: Binding(
                get: { viewModel.scopeIsByTag },
                set: { viewModel.setScopeByTag($0) }
            )) {
                Text("Todas as tarefas").tag(false)
                Text("Só com as tags marcadas").tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if viewModel.scopeIsByTag {
                if viewModel.selectableTags.isEmpty {
                    Text("Nenhuma tag cadastrada. Crie tags na janela Tarefas.")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textFaint)
                } else {
                    ForEach(viewModel.selectableTags, id: \.self) { tag in
                        Toggle(tag, isOn: Binding(
                            get: { viewModel.isSelected(tag) },
                            set: { viewModel.setTag(tag, selected: $0) }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                if viewModel.board?.taskScope.selectedTags.isEmpty == true {
                    Label("Nenhuma tag marcada — o quadro fica vazio.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.danger)
                } else {
                    Text("Entra no quadro a tarefa que tiver qualquer uma das tags marcadas (e for do projeto escolhido).")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
    }
}

/// Nome do quadro selecionado: grava ao confirmar ou ao sair do campo; vazio volta ao atual.
private struct BoardNameField: View {
    let board: KanbanBoard
    @ObservedObject var viewModel: KanbanSettingsViewModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Nome do quadro", text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onAppear { draft = board.name }
            .onChange(of: board) { _, board in draft = board.name }
    }

    private func commit() {
        viewModel.renameBoard(to: draft)
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.feedback != nil {
            draft = board.name
        }
    }
}

/// Uma raia: nome editável (grava ao confirmar ou ao sair do campo), subir/descer e apagar.
private struct LaneRow: View {
    let lane: KanbanLane
    @ObservedObject var viewModel: KanbanSettingsViewModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let openLanes = viewModel.board?.openLanes ?? []
        let index = openLanes.firstIndex { $0.id == lane.id }
        HStack(spacing: 8) {
            Image(systemName: lane.isDone ? "checkmark.circle.fill" : "rectangle.portrait")
                .foregroundStyle(lane.isDone ? Brand.cyan : Brand.textFaint)
                .frame(width: 16)

            TextField("Nome da raia", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }

            if lane.isDone {
                Text("concluídas")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textFaint)
                    .frame(width: 70)
            } else {
                Button { viewModel.moveLane(lane, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                    .accessibilityLabel("Subir raia")
                Button { viewModel.moveLane(lane, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == openLanes.count - 1)
                    .accessibilityLabel("Descer raia")
            }

            Button(role: .destructive) { viewModel.requestDelete(lane) } label: {
                Image(systemName: "trash")
            }
            .disabled(!viewModel.canDelete(lane))
            .help(lane.isDone ? "A raia de concluídas não pode ser apagada" : "Apagar raia")
            .accessibilityLabel("Apagar raia")
        }
        .buttonStyle(.borderless)
        .onAppear { draft = lane.title }
        .onChange(of: lane.title) { _, title in draft = title }
    }

    private func commit() {
        viewModel.renameLane(lane, to: draft)
        // Nome rejeitado (vazio) volta ao atual em vez de ficar em branco no campo.
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft = lane.title }
    }
}
