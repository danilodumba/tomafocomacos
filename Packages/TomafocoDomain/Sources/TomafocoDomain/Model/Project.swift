import Foundation

/// Projeto (FEAT-006): agrupa tarefas (0..1 projeto por tarefa, `FocusTask.projectID`).
public struct Project: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    /// Data de cadastro — automática, só leitura na UI.
    public let createdAt: Date
    /// Prazo do projeto: **um dia** (sem hora). Guardado como o início do dia no fuso de quem
    /// gravou — `isOverdue` compara por dia.
    public var dueDate: Date?
    public var color: ProjectColor
    /// SF Symbol (lista curada no App). Símbolo inexistente vira o padrão na UI.
    public var icon: String
    /// Descrição livre, multilinha. `nil` = sem descrição.
    public var details: String?

    public static let defaultIcon = "folder"

    public init(id: UUID, title: String, createdAt: Date, dueDate: Date? = nil,
                color: ProjectColor = .cyan, icon: String = Project.defaultIcon, details: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.color = color
        self.icon = icon
        self.details = details
    }

    /// Vencido: o dia do prazo já passou (o próprio dia do prazo não está vencido).
    public func isOverdue(now: Date, calendar: Calendar) -> Bool {
        guard let dueDate else { return false }
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now)
    }

    /// Título limpo (trim).
    public static func normalizeTitle(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Decode tolerante: campo novo numa versão futura não pode quebrar a leitura do banco.
    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, dueDate, color, icon, details
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        self.color = try c.decodeIfPresent(ProjectColor.self, forKey: .color) ?? .cyan
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? Project.defaultIcon
        self.details = try c.decodeIfPresent(String.self, forKey: .details)
    }
}
