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
    /// Código do projeto (RF-09.22): prefixo de até 5 caracteres (ex.: "PSC") que numera as tarefas
    /// do projeto — "PSC0001", "PSC0002"… `nil` = projeto sem código (tarefas não ganham código).
    public var code: String?
    /// Número que a PRÓXIMA tarefa vai receber (começa no "número inicial" do cadastro). Avança a
    /// cada código gerado. Sempre ≥ 1.
    public var nextCodeNumber: Int

    public static let defaultIcon = "folder"
    public static let maxCodeLength = 5

    public init(id: UUID, title: String, createdAt: Date, dueDate: Date? = nil,
                color: ProjectColor = .cyan, icon: String = Project.defaultIcon, details: String? = nil,
                code: String? = nil, nextCodeNumber: Int = 1) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.color = color
        self.icon = icon
        self.details = details
        self.code = code
        self.nextCodeNumber = max(nextCodeNumber, 1)
    }

    // MARK: - Código (RF-09.22)

    /// Código limpo: trim e maiúsculas; vazio vira `nil`. Lança `invalidProjectCode` com mais de 5
    /// caracteres ou com espaço no meio (o código vai colado ao número: "PS C0001" não faz sentido).
    public static func normalizeCode(_ raw: String?) throws -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= maxCodeLength, !trimmed.contains(where: \.isWhitespace) else {
            throw DomainError.invalidProjectCode(maxLength: maxCodeLength)
        }
        return trimmed
    }

    /// Código de tarefa para um número: prefixo + número com pelo menos 4 dígitos ("PSC0001";
    /// a partir de 10000 o número aparece inteiro).
    public static func taskCode(prefix: String, number: Int) -> String {
        prefix + String(format: "%04d", number)
    }

    /// Gera o código da próxima tarefa e avança o contador. `nil` (e nada muda) sem código.
    public mutating func takeNextTaskCode() -> String? {
        guard let code else { return nil }
        defer { nextCodeNumber += 1 }
        return Self.taskCode(prefix: code, number: nextCodeNumber)
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
        case id, title, createdAt, dueDate, color, icon, details, code, nextCodeNumber
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
        self.code = try c.decodeIfPresent(String.self, forKey: .code)
        self.nextCodeNumber = max(try c.decodeIfPresent(Int.self, forKey: .nextCodeNumber) ?? 1, 1)
    }
}
