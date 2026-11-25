import SwiftUI
import TomafocoMarkdown

/// Janela do documento em markdown de uma tarefa (FEAT-007 / RF-09.17): editar, visualizar ou os
/// dois lado a lado. Salva sozinha — não há Salvar/Cancelar.
struct TaskDocumentWindow: View {
    static let sceneID = "task-document"

    @StateObject private var viewModel: TaskDocumentViewModel

    /// `@autoclosure`: o `WindowGroup` reavalia o conteúdo, mas o VM nasce uma vez por janela.
    init(viewModel: @autoclosure @escaping () -> TaskDocumentViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let banner = viewModel.loadError
                ?? (viewModel.isTaskMissing ? "A tarefa foi apagada. O documento está só para leitura e não será salvo." : nil) {
                Label(banner, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                Divider()
            }
            content
        }
        .background(Brand.background)
        .navigationTitle(viewModel.windowTitle)
        .onDisappear { viewModel.flush() }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.taskTitle.isEmpty ? "Documento" : viewModel.taskTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                if let parentTitle = viewModel.parentTitle {
                    Label(parentTitle, systemImage: "arrow.turn.down.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textFaint)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(viewModel.statusText)
                .font(.system(size: 11))
                .foregroundStyle(viewModel.isStatusError ? Brand.danger : Brand.textFaint)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
            Picker("Modo", selection: $viewModel.mode) {
                ForEach(TaskDocumentViewModel.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Menu {
                Button("Copiar markdown") { viewModel.copyMarkdown() }
                Button("Exportar .md…") { viewModel.exportMarkdown() }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Copiar ou exportar o markdown")
            .accessibilityLabel("Copiar ou exportar")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Conteúdo

    @ViewBuilder
    private var content: some View {
        switch viewModel.mode {
        case .edit:
            editorPane
        case .preview:
            previewPane
        case .split:
            HSplitView {
                editorPane.frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                previewPane.frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            formatBar
            Divider()
            MarkdownTextView(text: $viewModel.text, controller: viewModel.editor,
                             isEditable: !viewModel.isReadOnly)
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if viewModel.text.allSatisfy(\.isWhitespace) {
            emptyGuide
        } else {
            MarkdownView(blocks: viewModel.blocks, version: viewModel.blocksVersion,
                         onToggleChecklist: viewModel.isReadOnly ? nil : { viewModel.toggleChecklist(at: $0) })
                .equatable()
        }
    }

    private var formatBar: some View {
        HStack(spacing: 2) {
            formatButton(.bold, "bold", "Negrito (⌘B)", shortcut: "b")
            formatButton(.italic, "italic", "Itálico (⌘I)", shortcut: "i")
            formatButton(.strikethrough, "strikethrough", "Tachado")
            formatButton(.code, "chevron.left.forwardslash.chevron.right", "Código")
            formatButton(.link, "link", "Link (⌘K)", shortcut: "k")
            Divider().frame(height: 16).padding(.horizontal, 4)
            formatButton(.heading, "textformat.size", "Título")
            formatButton(.bulletList, "list.bullet", "Lista")
            formatButton(.checklist, "checklist", "Checklist")
            formatButton(.quote, "text.quote", "Citação")
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .disabled(viewModel.isReadOnly)
    }

    private func formatButton(_ format: MarkdownFormat, _ symbol: String, _ help: String,
                              shortcut: KeyEquivalent? = nil) -> some View {
        Button {
            viewModel.editor.apply(format)
        } label: {
            Image(systemName: symbol)
                .frame(width: 24, height: 20)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Brand.textSecondary)
        .help(help)
        .accessibilityLabel(help)
        .modifier(OptionalShortcut(key: shortcut))
    }

    private var emptyGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Documento vazio")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.textPrimary)
            Text("Escreva em markdown no editor. Alguns exemplos:")
                .foregroundStyle(Brand.textSecondary)
            Text("""
            # Título           ## Subtítulo
            **negrito**   _itálico_   ~~tachado~~   `código`
            - item de lista
            - [ ] item de checklist (clique para marcar)
            1. lista numerada
            > citação
            [texto do link](https://exemplo.com)
            | Coluna | Outra |
            |--------|-------|
            | a      | b     |
            """)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Brand.textSecondary)
            .textSelection(.enabled)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// `.keyboardShortcut` só quando há atalho (o modificador não aceita opcional).
private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}
