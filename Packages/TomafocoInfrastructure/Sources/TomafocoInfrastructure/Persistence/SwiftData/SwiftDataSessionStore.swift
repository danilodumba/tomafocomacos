import Foundation
import os
import SwiftData
import TomafocoDomain

/// `SessionRepository` sobre o banco (FEAT-006): sessão ativa (failsafe pós-crash) numa linha
/// única, gravada na hora (sem autosave), e histórico de sessões **só por inserção** — o
/// `history.json` era lido e reescrito inteiro a cada fim de etapa.
@MainActor
public final class SwiftDataSessionStore: SessionRepository {

    private let database: TomafocoDatabase
    /// Próximo `sequence` do histórico — lido do banco uma vez. Preserva a ordem de inserção,
    /// a mesma do array do `history.json`.
    private var nextSequence: Int?
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "SwiftDataSessionStore")

    public init(database: TomafocoDatabase) {
        self.database = database
        database.onRollback { [weak self] in self?.nextSequence = nil }
    }

    public func saveActive(_ session: PomodoroSession) throws {
        try database.setSingleton(SingletonKey.activeSession, payload: PayloadCoding.encoder.encode(session))
        try database.commit()
    }

    public func loadActive() throws -> PomodoroSession? {
        guard let record = try database.singleton(SingletonKey.activeSession) else { return nil }
        return try PayloadCoding.decoder.decode(PomodoroSession.self, from: record.payload)
    }

    public func clearActive() throws {
        try database.deleteSingleton(SingletonKey.activeSession)
        try database.commit()
    }

    public func appendToHistory(_ record: SessionRecord) throws {
        try insertHistory([record])
        try database.commit()
    }

    /// Ordem de inserção. Linha ilegível é pulada (e logada) — um registro ruim não pode
    /// esconder o histórico inteiro, como o `.bak` do arquivo fazia.
    public func loadHistory() throws -> [SessionRecord] {
        let rows = try database.context.fetch(
            FetchDescriptor<SessionHistoryRecord>(sortBy: [SortDescriptor(\.sequence)]))
        return rows.compactMap { row in
            do {
                return try PayloadCoding.decoder.decode(SessionRecord.self, from: row.payload)
            } catch {
                Self.logger.error("Sessão \(row.sequence) ilegível no banco: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    /// Insere sem gravar — o importador usa dentro da transação dele.
    func insertHistory(_ records: [SessionRecord]) throws {
        var sequence = try currentNextSequence()
        for record in records {
            database.context.insert(SessionHistoryRecord(
                sequence: sequence, startedAt: record.startedAt, endedAt: record.endedAt,
                payload: try PayloadCoding.encoder.encode(record)))
            sequence += 1
        }
        nextSequence = sequence
    }

    private func currentNextSequence() throws -> Int {
        if let nextSequence { return nextSequence }
        var descriptor = FetchDescriptor<SessionHistoryRecord>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        let next = (try database.context.fetch(descriptor).first?.sequence ?? -1) + 1
        nextSequence = next
        return next
    }
}
