import SwiftUI
import TomafocoDomain

/// Apresentação da prioridade (nome, cor e glifo estilo Lembretes) — compartilhada entre a
/// lista de tarefas e a criação em lote.
extension TaskPriority {
    /// Ordem de exibição nos menus/pickers.
    static let displayOrder: [TaskPriority] = [.none, .low, .medium, .high]

    var displayName: String {
        switch self {
        case .none: return "Nenhuma"
        case .low: return "Baixa"
        case .medium: return "Média"
        case .high: return "Alta"
        }
    }

    var displayColor: Color {
        switch self {
        case .none: return Brand.textFaint
        case .low: return Brand.textSecondary
        case .medium: return .orange
        case .high: return Brand.danger
        }
    }

    var glyph: String {
        switch self {
        case .none: return ""
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }
}
