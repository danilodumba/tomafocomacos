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
    /// Subtarefa pedida para um pai que não existe (FEAT-003).
    case parentTaskNotFound
    /// Subtarefa de subtarefa: a hierarquia tem um nível só (FEAT-003).
    case subtaskNestingNotAllowed
    /// Tarefa que já tem subtarefas não pode virar subtarefa de outra — viraria dois níveis (FEAT-003).
    case taskHasSubtasks
    /// Senha de desbloqueio de apps curta demais (FEAT-002).
    case weakPassword(minimumLength: Int)
    /// Link da tarefa que não vira URL nem com `https://` na frente (RF-09.13) — valor cru para a UI.
    case invalidLink(String)
    /// Nome de raia do Kanban vazio após trim (FEAT-005).
    case emptyLaneTitle
    /// A raia Done é fixa: renomeia, mas não é apagada nem movida (FEAT-005).
    case cannotDeleteDoneLane
    /// O quadro precisa de pelo menos uma raia aberta além da Done (FEAT-005).
    case cannotDeleteLastOpenLane
}
