import Foundation
import TomafocoDomain

/// Serializa um relatório de tarefas concluídas em CSV (RF-10.1). PURO: sem `Date()` nem I/O —
/// a formatação de datas entra por `dateString` (a UI passa um formatador localizado; os testes,
/// um fixo). Quem grava em disco (NSSavePanel) é a camada App.
public enum ReportCSVExporter {

    /// Uma linha por tarefa concluída, com o tempo de foco vindo do `report` (casado por `id`).
    /// Colunas: Tarefa, Tags, Prioridade, Tempo de foco (min), Sessões, Concluída em.
    public static func completedTasksCSV(
        tasks: [FocusTask],
        report: FocusReport,
        dateString: (Date) -> String
    ) -> String {
        let totalsByID: [UUID: FocusReport.TaskTotal] = Dictionary(
            uniqueKeysWithValues: report.taskTotals.compactMap { total in
                total.taskID.map { ($0, total) }
            }
        )
        let header = ["Tarefa", "Tags", "Prioridade", "Tempo de foco (min)", "Sessões", "Concluída em"]
        var lines = [row(header)]
        for task in tasks {
            let total = totalsByID[task.id]
            let minutes = Int(((total?.focusTime ?? 0) / 60).rounded())
            lines.append(row([
                task.title,
                task.tags.joined(separator: ", "),
                priorityLabel(task.priority),
                String(minutes),
                String(total?.sessionCount ?? 0),
                task.completedAt.map(dateString) ?? ""
            ]))
        }
        return lines.joined(separator: "\r\n")
    }

    /// Uma linha por entrada de histórico (FEAT-001), mais recente primeiro — a ordem chega
    /// pronta do `ReportBuilder`. Colunas: Tarefa, Data, Descrição.
    /// CSV separado do de tarefas concluídas de propósito: a granularidade é outra (uma tarefa
    /// tem N entradas), e concatenar tudo numa célula estragaria a leitura em planilha.
    public static func taskHistoryCSV(
        entries: [FocusReport.HistoryItem],
        dateString: (Date) -> String
    ) -> String {
        var lines = [row(["Tarefa", "Data", "Descrição"])]
        for entry in entries {
            lines.append(row([entry.taskTitle, dateString(entry.date), entry.text]))
        }
        return lines.joined(separator: "\r\n")
    }

    /// Rótulo PT-BR da prioridade, no mesmo vocabulário do Lembretes.
    static func priorityLabel(_ raw: Int?) -> String {
        switch TaskPriority(rawPriority: raw) {
        case .none: return "Nenhuma"
        case .low: return "Baixa"
        case .medium: return "Média"
        case .high: return "Alta"
        }
    }

    private static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    /// Escapa um campo CSV: envolve em aspas e duplica aspas internas quando há vírgula, aspas
    /// ou quebra de linha. Evita que uma tarefa com vírgula no título estoure as colunas.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
