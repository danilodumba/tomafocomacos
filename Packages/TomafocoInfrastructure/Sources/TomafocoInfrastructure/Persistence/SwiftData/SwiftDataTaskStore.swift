import Foundation
import os
import SwiftData
import TomafocoDomain

/// `TaskRepository` sobre o banco (FEAT-006).
///
/// Mantém um **espelho em memória** das tarefas (ordem + valores), carregado do banco uma vez:
/// todas as gravações do app passam por este store, então o espelho é sempre o estado do banco.
/// Ganhos: `loadTasks` não decodifica nada depois da 1ª leitura, e `saveTasks` (estado completo)
/// compara com o espelho e grava **só as tarefas que mudaram** — o `tasks.json` era reescrito
/// inteiro a cada clique. Se uma transação é desfeita, o espelho é descartado e relido.
@MainActor
public final class SwiftDataTaskStore: TaskRepository {

    private let database: TomafocoDatabase
    private var mirror: Mirror?
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "SwiftDataTaskStore")

    private struct Mirror {
        var order: [UUID]
        var values: [UUID: FocusTask]
        /// Inclui linhas cujo payload não decodificou (ficam fora de `order`/`values`): o diff do
        /// `saveTasks` só apaga ids que estavam em `order`, então uma linha ilegível nunca é
        /// apagada por "sumir da lista".
        var records: [UUID: TaskRecord]
        var nextPosition: Int
    }

    public init(database: TomafocoDatabase) {
        self.database = database
        database.onRollback { [weak self] in self?.mirror = nil }
    }

    public func loadTasks() throws -> [FocusTask] {
        let mirror = try loaded()
        return mirror.order.compactMap { mirror.values[$0] }
    }

    public func task(id: UUID) throws -> FocusTask? {
        try loaded().values[id]
    }

    public func saveTasks(_ tasks: [FocusTask]) throws {
        var mirror = try loaded()
        // Tudo que pode lançar (codificar) acontece ANTES de tocar o contexto: um erro no meio
        // deixaria metade das mudanças pendentes no `ModelContext`, gravadas pelo próximo
        // `commit()` de qualquer outro store, com o espelho desatualizado.
        let changes = try encodeChanged(tasks, against: mirror)
        let incoming = Set(tasks.map(\.id))
        for id in mirror.order where !incoming.contains(id) {
            if let record = mirror.records[id] { database.context.delete(record) }
            mirror.values[id] = nil
            mirror.records[id] = nil
        }
        for (task, payload) in changes {
            write(task, payload: payload, into: &mirror)
        }
        mirror.order = tasks.map(\.id)
        // Contrato do port é "estado completo", ordem inclusive: se quem chamou reordenou, a
        // `position` acompanha — senão a ordem nova só duraria até reabrir o app.
        reassignPositionsIfReordered(&mirror)
        self.mirror = mirror
        try database.commit()
    }

    public func upsert(_ tasks: [FocusTask]) throws {
        var mirror = try loaded()
        let changes = try encodeChanged(tasks, against: mirror)
        for task in tasks where mirror.values[task.id] == nil {
            mirror.order.append(task.id)
        }
        for (task, payload) in changes {
            write(task, payload: payload, into: &mirror)
        }
        self.mirror = mirror
        try database.commit()
    }

    // MARK: - Privado

    /// Payload das tarefas que mudaram em relação ao espelho (as iguais não são regravadas).
    private func encodeChanged(_ tasks: [FocusTask], against mirror: Mirror) throws -> [(FocusTask, Data)] {
        try tasks.compactMap { task in
            if let current = mirror.values[task.id], current == task { return nil }
            return (task, try PayloadCoding.encoder.encode(task))
        }
    }

    /// `position` crescente ao longo de `order`? Se não, renumera todas (raro: hoje nenhum caminho
    /// reordena; o custo é uma passada O(n) de comparação).
    private func reassignPositionsIfReordered(_ mirror: inout Mirror) {
        var last = Int.min
        for id in mirror.order {
            guard let position = mirror.records[id]?.position else { continue }
            if position <= last {
                for (index, id) in mirror.order.enumerated() where mirror.records[id]?.position != index {
                    mirror.records[id]?.position = index
                }
                mirror.nextPosition = mirror.order.count
                return
            }
            last = position
        }
    }

    /// Insere ou atualiza a linha. Não lança — o contexto só é tocado com tudo já codificado.
    private func write(_ task: FocusTask, payload: Data, into mirror: inout Mirror) {
        if let record = mirror.records[task.id] {
            record.createdAt = task.createdAt
            record.completedAt = task.completedAt
            record.dueDate = task.dueDate
            record.parentID = task.parentID
            record.payload = payload
        } else {
            let record = TaskRecord(
                id: task.id, position: mirror.nextPosition, createdAt: task.createdAt,
                completedAt: task.completedAt, dueDate: task.dueDate, parentID: task.parentID,
                payload: payload)
            mirror.nextPosition += 1
            database.context.insert(record)
            mirror.records[task.id] = record
        }
        mirror.values[task.id] = task
    }

    private func loaded() throws -> Mirror {
        if let mirror { return mirror }
        let records = try database.context.fetch(FetchDescriptor<TaskRecord>(sortBy: [SortDescriptor(\.position)]))
        var mirror = Mirror(order: [], values: [:], records: [:],
                            nextPosition: (records.last?.position ?? -1) + 1)
        for record in records {
            mirror.records[record.id] = record
            do {
                mirror.values[record.id] = try PayloadCoding.decoder.decode(FocusTask.self, from: record.payload)
                mirror.order.append(record.id)
            } catch {
                Self.logger.error("Tarefa \(record.id, privacy: .public) ilegível no banco: \(String(describing: error), privacy: .public)")
            }
        }
        self.mirror = mirror
        return mirror
    }
}
