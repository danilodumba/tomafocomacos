import SwiftUI

/// Faixa horizontal rolável de tags clicáveis — usada como autocomplete leve (item 1).
/// Rolagem horizontal em vez de wrap para não brigar com o tamanho do popover.
struct FlowChips: View {
    let tags: [String]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Button { onTap(tag) } label: {
                        Text(tag)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Brand.cyan)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Brand.cyan.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
