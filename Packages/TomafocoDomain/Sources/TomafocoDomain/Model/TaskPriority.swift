import Foundation

/// Nível de prioridade de uma tarefa, no mesmo modelo do app Lembretes (nenhuma / baixa / média / alta).
///
/// O armazenamento em `FocusTask.priority` continua sendo o `Int?` do EventKit (1–9, menor = mais
/// urgente; `nil`/0 = nenhuma). Este enum é a tradução pura desse número cru para os quatro níveis
/// que a UI mostra e edita — reusado na importação e na tela de tarefas para não espalhar mágica de
/// faixas (1–4 alta, 5 média, 6–9 baixa) por várias camadas.
public enum TaskPriority: String, CaseIterable, Equatable, Sendable, Codable {
    case none
    case low
    case medium
    case high

    /// Interpreta o valor cru do EventKit. `nil`/`0` → `.none`; 1–4 → `.high`; 5 → `.medium`; 6–9 → `.low`.
    public init(rawPriority: Int?) {
        switch rawPriority {
        case .none, .some(0):
            self = .none
        case .some(let value) where value <= 4:
            self = .high
        case .some(5):
            self = .medium
        default:
            self = .low
        }
    }

    /// Valor canônico gravado em `FocusTask.priority`. `.none` → `nil`; alta 1, média 5, baixa 9 —
    /// os mesmos números que o Lembretes usa, então a conclusão espelhada de volta bate.
    public var rawPriority: Int? {
        switch self {
        case .none: return nil
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        }
    }
}
