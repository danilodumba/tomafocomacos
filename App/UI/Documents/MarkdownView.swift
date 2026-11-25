import SwiftUI
import TomafocoMarkdown

/// Desenha o documento já convertido (`MarkdownBlock`, FEAT-007). Só apresentação: o que é
/// título, lista, checklist ou link chegou decidido e testado do pacote `TomafocoMarkdown`.
/// Cores só do `Brand` — claro/escuro automáticos.
struct MarkdownView: View, Equatable {
    let blocks: [MarkdownBlock]
    /// Muda a cada parse — é o que o `==` compara (ver abaixo).
    let version: Int
    /// Clique num item de checklist. `nil` = só leitura (tarefa apagada).
    let onToggleChecklist: ((MarkdownSourcePosition) -> Void)?

    /// Com `.equatable()`, digitar no editor (que republica o VM a cada tecla) não reconstrói a
    /// visualização: ela só muda quando um parse novo chega. Comparar pela versão, e não pelos
    /// blocos, evita um `==` O(tamanho do documento) por tecla.
    static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.version == rhs.version && (lhs.onToggleChecklist == nil) == (rhs.onToggleChecklist == nil)
    }

    var body: some View {
        ScrollView {
            // Lazy: documento longo não materializa todos os blocos de uma vez.
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block, onToggleChecklist: onToggleChecklist)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Cor padrão herdada: parágrafos não fixam cor própria, senão o esmaecido do item
            // marcado e da citação (aplicado no contêiner) não chegaria ao texto.
            .foregroundStyle(Brand.textPrimary)
        }
        .textSelection(.enabled)
        .tint(Brand.cyan)
    }
}

/// Um bloco. Filhos de lista/citação passam por `AnyView`: um `some View` que contém o próprio
/// tipo é recursão de tipo opaco, que o compilador recusa.
private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let onToggleChecklist: ((MarkdownSourcePosition) -> Void)?

    var body: some View {
        switch block {
        case .heading(let level, let content):
            heading(level: level, content: content)
        case .paragraph(let content):
            Text(content)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let list):
            listView(list)
        case .quote(let children):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Brand.cyan.opacity(0.7))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 8) { nested(children) }
                    .foregroundStyle(Brand.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let text):
            codeBlock(language: language, text: text)
        case .table(let table):
            MarkdownTableView(table: table)
        case .thematicBreak:
            Divider().padding(.vertical, 4)
        case .literal(let text):
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func heading(level: Int, content: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content)
                .font(.system(size: Self.headingSize(level), weight: level <= 2 ? .bold : .semibold))
                .foregroundStyle(level >= 5 ? Brand.textSecondary : Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if level <= 2 { Divider() }
        }
        .padding(.top, level <= 2 ? 8 : 4)
    }

    private static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 24
        case 2: 20
        case 3: 17
        case 4: 15
        default: 13
        }
    }

    private func listView(_ list: MarkdownList) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    marker(for: item, number: list.start + index, ordered: list.isOrdered)
                    VStack(alignment: .leading, spacing: 5) { nested(item.blocks) }
                        .foregroundStyle(item.checkbox == true ? Brand.textFaint : Brand.textPrimary)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItem, number: Int, ordered: Bool) -> some View {
        if let checked = item.checkbox {
            Toggle("", isOn: Binding(
                get: { checked },
                set: { _ in
                    if let position = item.position { onToggleChecklist?(position) }
                }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(onToggleChecklist == nil || item.position == nil)
                .accessibilityLabel(checked ? "Desmarcar item" : "Marcar item")
        } else if ordered {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(Brand.textSecondary)
        } else {
            Text("•").foregroundStyle(Brand.cyan)
        }
    }

    private func codeBlock(language: String?, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language {
                Text(language)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Brand.textFaint)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Brand.surface))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Brand.surfaceStroke))
    }

    private func nested(_ blocks: [MarkdownBlock]) -> some View {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, child in
            AnyView(MarkdownBlockView(block: child, onToggleChecklist: onToggleChecklist))
        }
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        self.cell(cell, column: column, isHeader: true)
                            .gridColumnAlignment(Self.alignment(table.alignments[column]))
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            self.cell(cell, column: column, isHeader: false)
                        }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.surfaceStroke))
            .fixedSize()
        }
    }

    /// Célula ocupa a largura da coluna (fundo do cabeçalho contínuo, sem buraco entre colunas).
    private func cell(_ content: AttributedString, column: Int, isHeader: Bool) -> some View {
        Text(content)
            .fontWeight(isHeader ? .semibold : .regular)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: Self.frameAlignment(table.alignments[column]))
            .background(isHeader ? Brand.surface : Color.clear)
    }

    private static func frameAlignment(_ alignment: MarkdownTable.Alignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private static func alignment(_ alignment: MarkdownTable.Alignment) -> HorizontalAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
