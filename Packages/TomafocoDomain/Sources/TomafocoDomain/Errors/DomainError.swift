import Foundation

/// Erros de regra de negócio do domínio. Nunca use `fatalError` em fluxo de produção (ver arquitetura §8).
public enum DomainError: Error, Equatable {
    /// Domínio informado é inválido (formato) — carrega o valor cru para exibição na UI.
    case invalidDomain(String)
    /// Tentativa de adicionar um item já existente na lista de bloqueio.
    case duplicateEntry(String)
    /// Cancelamento rejeitado por estar dentro da carência do modo hardcore.
    case cancellationBlockedByHardcore(remainingSeconds: Int)
    /// Motivo obrigatório (modo hardcore) não informado ao iniciar a sessão.
    case reasonRequired
    /// Título de tarefa vazio após normalização (RF-09).
    case emptyTaskTitle
}
