import Foundation
import TomafocoDomain

/// Uma conclusão de tarefa para relatório (RF-10). Tarefa comum gera uma; tarefa diária
/// (FEAT-004) gera uma por dia concluído — o `completedAt` dela é zerado na virada, então o
/// histórico vem do `completionLog`.
public struct CompletedTaskOccurrence: Equatable, Identifiable, Sendable {
    /// Tarefa + instante: a mesma diária aparece várias vezes, e `ForEach` precisa de id único.
    public let id: String
    /// Cópia da tarefa com `completedAt` = esta conclusão (o CSV e a linha leem dali).
    public let task: FocusTask

    /// Todas as conclusões, mais recente primeiro. Junta `completionLog` com o `completedAt`
    /// corrente sem repetir — cobre a diária concluída antes de virar diária e a que deixou de ser.
    public static func occurrences(of tasks: [FocusTask]) -> [CompletedTaskOccurrence] {
        tasks.flatMap { task -> [CompletedTaskOccurrence] in
            var dates = task.completionLog
            if let completedAt = task.completedAt, !dates.contains(completedAt) { dates.append(completedAt) }
            return dates.map { date in
                var copy = task
                copy.completedAt = date
                return CompletedTaskOccurrence(
                    id: "\(task.id.uuidString)-\(date.timeIntervalSinceReferenceDate)", task: copy)
            }
        }
        .sorted { ($0.task.completedAt ?? .distantPast) > ($1.task.completedAt ?? .distantPast) }
    }
}
