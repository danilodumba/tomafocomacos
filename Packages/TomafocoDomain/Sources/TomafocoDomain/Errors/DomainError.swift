import Foundation

/// Erros de regra de negócio do domínio. Nunca use `fatalError` em fluxo de produção (ver arquitetura §8).
public enum DomainError: Error, Equatable {
    /// Domínio informado é inválido (formato) — carrega o valor cru para exibição na UI.
    case invalidDomain(String)
    /// Tentativa de adicionar um item já existente na lista de bloqueio.
    case duplicateEntry(String)
    /// Título de tarefa vazio após normalização (RF-09).
    case emptyTaskTitle
    /// Descrição de entrada de histórico vazia após trim (FEAT-001).
    case emptyHistoryEntry
    /// Senha de desbloqueio de apps curta demais (FEAT-002).
    case weakPassword(minimumLength: Int)
}
