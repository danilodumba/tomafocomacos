import SwiftUI
import TomafocoMarkdown

/// Janela de um documento em markdown — da tarefa (FEAT-007 / RF-09.17) ou do projeto (FEAT-009 /
/// RF-09.20): editar, visualizar ou os dois lado a lado. Salva sozinha — não há Salvar/Cancelar.
struct DocumentWindow: View {
    /// Cena do documento da tarefa (valor = id da tarefa).
    static let taskSceneID = "task-document"
    /// Cena do documento do projeto (valor = id do documento).
    static let projectSceneID = "project-document"

    @StateObject private var viewModel: DocumentViewModel
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    /// `@autoclosure`: o `WindowGroup` reavalia o conteúdo, mas o VM nasce uma vez por janela.
    init(viewModel: @autoclosure @escaping () -> DocumentViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let banner = viewModel.loadError
                ?? (viewModel.isOwnerMissing ? viewModel.source.missingMessage : nil) {
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
                if viewModel.source.canRename {
                    // Documento de projeto: o título se edita aqui (grava ao confirmar ou sair do campo).
                    TextField("Título do documento", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                        .focused($titleFocused)
                        .disabled(viewModel.isReadOnly)
                        .onSubmit { viewModel.rename(to: titleDraft) }
                        .onChange(of: titleFocused) { _, focused in
                            if !focused { viewModel.rename(to: titleDraft) }
                        }
                        .onAppear { titleDraft = viewModel.header.title }
                        .onChange(of: viewModel.header.title) { _, title in
                            if !titleFocused { titleDraft = title }
                        }
                } else {
                    Text(viewModel.header.title.isEmpty ? "Documento" : viewModel.header.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                }
                if let subtitle = viewModel.header.subtitle {
                    Label(subtitle, systemImage: viewModel.header.subtitleSymbol)
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
                ForEach(DocumentViewModel.Mode.allCases) { mode in
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
