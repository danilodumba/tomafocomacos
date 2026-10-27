import Foundation

/// Leituras puras da hierarquia pai → subtarefas (FEAT-003 / RF-09.14). A relação mora em
/// `FocusTask.parentID`; aqui ficam as consultas que lista, quadro, timer e relatórios repetem,
/// para a semântica ser uma só. Um nível: filho de filho não existe (regra do use case).
public enum TaskTree {

    /// Tarefas sem pai, na ordem recebida.
    public static func topLevel(_ tasks: [FocusTask]) -> [FocusTask] {
        tasks.filter { $0.parentID == nil }
    }

    /// Subtarefas de `parentID`, na ordem recebida (quem ordena para exibição é a UI).
    public static func children(of parentID: UUID, in tasks: [FocusTask]) -> [FocusTask] {
        tasks.filter { $0.parentID == parentID }
    }

    /// Pai da tarefa, se ela tiver um e ele existir na lista.
    public static func parent(of task: FocusTask, in tasks: [FocusTask]) -> FocusTask? {
        guard let parentID = task.parentID else { return nil }
        return tasks.first { $0.id == parentID }
    }

    /// Progresso do checklist do pai: `(feitas, total)`. `total == 0` = sem subtarefas.
    public static func progress(of parentID: UUID, in tasks: [FocusTask]) -> (done: Int, total: Int) {
        let kids = children(of: parentID, in: tasks)
        return (kids.filter(\.isCompleted).count, kids.count)
    }

    /// Título para exibição fora do contexto do pai (seletor do timer, anel, relatórios):
    /// subtarefa vira `"Pai › Filha"`; tarefa de topo (ou pai não encontrado) é o próprio título.
    public static func displayTitle(of task: FocusTask, in tasks: [FocusTask]) -> String {
        guard let parent = parent(of: task, in: tasks) else { return task.title }
        return "\(parent.title) › \(task.title)"
    }

    /// Reagrupa mantendo a ordem relativa: cada tarefa de topo seguida das suas subtarefas (na
    /// ordem em que vieram). Subtarefa cujo pai não está na lista fica onde estava, como topo.
    public static func grouped(_ tasks: [FocusTask]) -> [FocusTask] {
        let ids = Set(tasks.map(\.id))
        var result: [FocusTask] = []
        for task in tasks where task.parentID.map({ !ids.contains($0) }) ?? true {
            result.append(task)
            result += children(of: task.id, in: tasks)
        }
        return result
    }
}
