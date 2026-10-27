import SwiftUI
import TomafocoDomain

/// Campos secundários do formulário que capturam o Return (FEAT-001/FEAT-003). Com qualquer um
/// focado, "Salvar" perde o `.defaultAction` — senão o Return vira key equivalent da janela (roda
/// ANTES do `onSubmit` do campo), salva e fecha o sheet sem acrescentar a entrada/subtarefa.
enum TaskEditorField: Hashable {
    case history
    case newSubtask
}

/// Formulário de edição da tarefa (RF-09.6) + histórico (FEAT-001) + subtarefas (FEAT-003), usado
/// pela janela Tarefas e pelo Kanban. Edita título, prioridade, tags, vencimento e repetição de
/// uma vez; nada é gravado até "Salvar" — erro de validação mantém o sheet aberto. Histórico e
/// subtarefas gravam na hora.
struct TaskEditorSheet: View {
    @ObservedObject var viewModel: TaskEditorViewModel

    var body: some View {
        FocusHost { focused in content(focused: focused) }
    }

    /// Header e footer fixos; só o **body** rola (formulário + subtarefas + histórico numa
    /// `ScrollView` única — as seções não têm rolagem própria, senão vira scroll dentro de scroll).
    private func content(focused: FocusState<TaskEditorField?>.Binding) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            scrollBody(focused: focused)
            Divider()
            footer(focused: focused)
        }
        .frame(width: 560, height: 760)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.parentTitle == nil ? "Editar tarefa" : "Editar subtarefa")
                .font(.system(size: 14, weight: .semibold))
            // FEAT-003: subtarefa mostra de quem é — e o clique abre o editor do pai (troca o
            // sheet; o rascunho daqui NÃO é gravado, igual a abrir uma filha pelo pai).
            if let parentTitle = viewModel.parentTitle {
                Button {
                    viewModel.openParent()
                } label: {
                    HStack(spacing: 4) {
                        Label(parentTitle, systemImage: "arrow.turn.down.right")
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.cyan)
                }
                .buttonStyle(.plain)
                .help("Abrir a tarefa pai (alterações não salvas aqui são descartadas)")
                .accessibilityLabel("Abrir a tarefa pai: \(parentTitle)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Body (rola)

    private func scrollBody(focused: FocusState<TaskEditorField?>.Binding) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                draftForm

                // Fora do `Form` de propósito: em `.grouped`, linha com `Button` vira alvo de clique
                // inteira — o clique no campo "Nova entrada" ia para o botão e o campo nunca focava.
                if viewModel.canHaveSubtasks {
                    subtasksSection(focused: focused)
                        .padding(.horizontal, 4)
                }

                historySection(focused: focused)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Footer

    private func footer(focused: FocusState<TaskEditorField?>.Binding) -> some View {
        HStack(spacing: 12) {
            if let error = viewModel.feedback {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Cancelar") { viewModel.cancel() }
                .keyboardShortcut(.cancelAction)
            Button("Salvar") { viewModel.save() }
                .keyboardShortcut(focused.wrappedValue == nil ? .defaultAction : nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Rascunho (RF-09.6)

    /// Campos transacionais — só `save()` grava. `fixedSize` vertical: o `Form` deixa de rolar
    /// sozinho e entra com a altura do conteúdo na rolagem do body.
    private var draftForm: some View {
        Form {
            TextField("Título", text: $viewModel.title)
                .onSubmit { viewModel.save() }

            Picker("Prioridade", selection: $viewModel.priority) {
                ForEach(TaskPriority.displayOrder, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 4) {
                TextField("Tags (vírgula)", text: $viewModel.tags)
                TagSuggestionsMenu(knownTags: viewModel.knownTags, text: $viewModel.tags)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Vencimento", isOn: $viewModel.hasDueDate)
                DatePicker(
                    "", selection: $viewModel.dueDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .disabled(!viewModel.hasDueDate)
                .opacity(viewModel.hasDueDate ? 1 : 0.4)
            }

            // FEAT-004: concluída num dia, volta a ficar ativa no dia seguinte.
            Toggle("Repetir diariamente", isOn: $viewModel.repeatsDaily)

            // RF-09.13: destaque forte na lista e no quadro; vai para o topo.
            Toggle(isOn: $viewModel.isUrgent) {
                Label("Urgente", systemImage: "flame.fill")
                    .foregroundStyle(viewModel.isUrgent ? Brand.danger : Brand.textPrimary)
            }

            // RF-09.13: link abre no navegador/app padrão; `https://` é completado ao salvar.
            HStack(spacing: 6) {
                // Sem `.textContentType(.URL)`: é macOS 14+ (deployment target 13).
                TextField("Link (opcional)", text: $viewModel.link)
                    .autocorrectionDisabled()
                if let url = viewModel.linkURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .help("Abrir link")
                    .accessibilityLabel("Abrir link")
                }
            }

            // RF-09.13: nota livre, multilinha (Return quebra linha; o Return do título salva).
            TextField("Nota (opcional)", text: $viewModel.notes, axis: .vertical)
                .lineLimit(2...6)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Subtarefas (FEAT-003)

    /// Subtarefas: tarefas completas com pai. Aqui se cria (só título), conclui e apaga — tudo
    /// **grava na hora**. Lápis troca este editor pelo da subtarefa (tags, prioridade, data…).
    private func subtasksSection(focused: FocusState<TaskEditorField?>.Binding) -> some View {
        let progress = viewModel.subtaskProgress
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Subtarefas")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textSecondary)
                if progress.total > 0 {
                    Text("\(progress.done)/\(progress.total)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(progress.done == progress.total ? Brand.cyan : Brand.textSecondary)
                }
                Text("· gravado na hora")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textFaint)
            }

            HStack(spacing: 6) {
                TextField("Nova subtarefa", text: $viewModel.newSubtaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused(focused, equals: .newSubtask)
                    // Return adiciona e mantém o foco: 3 subtarefas em sequência sem tocar no mouse.
                    .onSubmit { viewModel.addSubtask() }
                Button("Adicionar") { viewModel.addSubtask() }
                    .disabled(viewModel.newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !viewModel.subtasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.subtasks) { subtask in
                        subtaskRow(subtask)
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
                )
            }
        }
    }

    /// Linha da subtarefa: círculo (conclui/reabre), título, prioridade/urgente como pistas,
    /// lápis (abre o editor dela) e lixeira.
    private func subtaskRow(_ subtask: FocusTask) -> some View {
        let priority = TaskPriority(rawPriority: subtask.priority)
        return HStack(spacing: 8) {
            if viewModel.busySubtaskIDs.contains(subtask.id) {
                ProgressView().controlSize(.small).frame(width: 14, height: 14)
            } else {
                Button {
                    viewModel.toggleSubtask(subtask)
                } label: {
                    Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(subtask.isCompleted ? Brand.cyan : Brand.textFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(subtask.isCompleted ? "Reabrir subtarefa" : "Concluir subtarefa")
            }

            if subtask.showsUrgent {
                Image(systemName: "flame.fill").foregroundStyle(Brand.danger)
            }
            if priority != .none {
                Text(priority.glyph).fontWeight(.bold).foregroundStyle(priority.displayColor)
            }
            Text(subtask.title)
                .strikethrough(subtask.isCompleted)
                .foregroundStyle(subtask.isCompleted ? Brand.textFaint : Brand.textPrimary)
                .lineLimit(1)
            if let due = subtask.dueDate {
                Text(due.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 10))
                    .foregroundStyle(subtask.isOverdue ? Brand.danger : Brand.textFaint)
            }

            Spacer()

            Button {
                viewModel.openSubtask(subtask)
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.textFaint)
            .help("Editar subtarefa (tags, prioridade, vencimento…)")
            .accessibilityLabel("Editar subtarefa")

            Button(role: .destructive) {
                viewModel.deleteSubtask(subtask)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.textFaint)
            .accessibilityLabel("Apagar subtarefa")
        }
        .font(.system(size: 11))
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Brand.surface))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { viewModel.openSubtask(subtask) }
    }

    // MARK: - Histórico da tarefa (FEAT-001)

    /// Entradas datadas da tarefa. Ao contrário do resto do formulário, adicionar/apagar aqui
    /// **grava na hora** — histórico é log, não rascunho. A legenda avisa o usuário.
    /// `VStack` em vez de `List` (altura do conteúdo; quem rola é o body do sheet).
    private func historySection(focused: FocusState<TaskEditorField?>.Binding) -> some View {
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
                    .focused(focused, equals: .history)
                    .onSubmit { viewModel.addHistoryEntry() }
                Button("Adicionar") { viewModel.addHistoryEntry() }
                    .disabled(viewModel.newHistoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Lista longa (conclusões diárias da FEAT-004, movimentações do Kanban) cresce e rola
            // junto com o body — o footer fica fixo, nunca é empurrado para fora.
            Group {
                if viewModel.history.isEmpty {
                    Text("Sem entradas ainda.")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.history) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
            )
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
}

/// Dono do `@FocusState` do formulário de edição. Precisa morar DENTRO do sheet: `@FocusState`
/// declarado na view que apresenta não atravessa a fronteira do sheet de forma confiável.
private struct FocusHost<Content: View>: View {
    @FocusState private var focused: TaskEditorField?
    let content: (FocusState<TaskEditorField?>.Binding) -> Content

    var body: some View { content($focused) }
}
