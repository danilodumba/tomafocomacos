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
    /// Nome de quadro Kanban vazio após trim (FEAT-008).
    case emptyBoardName
    /// Já existe quadro com esse nome, sem distinção de caixa (FEAT-008) — valor para a UI.
    case duplicateBoardName(String)
    /// Sempre existe pelo menos um quadro (FEAT-008).
    case cannotDeleteLastBoard
    /// Quadro inexistente (apagado em outra janela) (FEAT-008).
    case boardNotFound
    /// Título de projeto vazio após trim (FEAT-006).
    case emptyProjectTitle
    /// Já existe projeto com esse título, sem distinção de caixa (FEAT-006) — valor para a UI.
    case duplicateProject(String)
    /// Código de projeto inválido (RF-09.22): mais caracteres que o limite ou espaço no meio.
    case invalidProjectCode(maxLength: Int)
    /// Já existe projeto com esse código (RF-09.22) — tarefas de dois projetos teriam o mesmo código.
    case duplicateProjectCode(String)
    /// Projeto inexistente (apagado em outra janela enquanto o formulário estava aberto).
    case projectNotFound
    /// Documento da tarefa acima do limite (FEAT-007) — limite em bytes para a mensagem da UI.
    case documentTooLarge(maxBytes: Int)
}
