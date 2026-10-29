import Foundation

/// Cor do projeto (FEAT-006): paleta fixa. O App mapeia cada tom para uma cor adaptativa
/// claro/escuro — hex livre ficaria ilegível num dos temas. Persistida pelo `rawValue`
/// (acrescentar caso é seguro; renomear não — o valor gravado deixaria de bater).
/// Ordem de declaração = ordem na grade (por matiz).
public enum ProjectColor: String, CaseIterable, Codable, Sendable {
    case red, wine, orange, amber, brown, yellow, olive, green, mint, teal, cyan, sky
    case blue, navy, indigo, purple, lavender, magenta, pink, gray, charcoal

    /// Valor desconhecido (gravado por versão futura) cai em `.cyan` em vez de derrubar a
    /// leitura do projeto inteiro.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProjectColor(rawValue: raw) ?? .cyan
    }
}
