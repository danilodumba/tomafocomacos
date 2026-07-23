import Foundation
import TomafocoDomain

/// `SessionRepository` que persiste a sessão ativa (failsafe) e o histórico como JSON em
/// Application Support, com escrita atômica (sobrevive a `kill -9` — RNF-02/T-15).
public final class FileSessionSnapshotStore: SessionRepository {

    private let activeURL: URL
    private let historyURL: URL
    /// Destino do histórico corrompido — preservado em vez de apagado (ver `appendToHistory`).
    private let historyBackupURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base = directory ?? Self.defaultDirectory(fileManager)
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.activeURL = base.appendingPathComponent("active-session.json")
        self.historyURL = base.appendingPathComponent("history.json")
        self.historyBackupURL = base.appendingPathComponent("history.json.bak")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func saveActive(_ session: PomodoroSession) throws {
        let data = try encoder.encode(session)
        try data.write(to: activeURL, options: .atomic)
    }

    public func loadActive() throws -> PomodoroSession? {
        guard fileManager.fileExists(atPath: activeURL.path) else { return nil }
        let data = try Data(contentsOf: activeURL)
        return try decoder.decode(PomodoroSession.self, from: data)
    }

    public func clearActive() throws {
        guard fileManager.fileExists(atPath: activeURL.path) else { return }
        try fileManager.removeItem(at: activeURL)
    }

    public func appendToHistory(_ record: SessionRecord) throws {
        var records: [SessionRecord]
        do {
            records = try loadHistory()
        } catch {
            // Arquivo ilegível NÃO pode ser sobrescrito em silêncio — apagaria todo o histórico
            // do usuário por um byte corrompido. Preserva como .bak para diagnóstico e recomeça.
            try? fileManager.removeItem(at: historyBackupURL)
            try? fileManager.moveItem(at: historyURL, to: historyBackupURL)
            records = []
        }
        records.append(record)
        let data = try encoder.encode(records)
        try data.write(to: historyURL, options: .atomic)
    }

    public func loadHistory() throws -> [SessionRecord] {
        guard fileManager.fileExists(atPath: historyURL.path) else { return [] }
        let data = try Data(contentsOf: historyURL)
        return try decoder.decode([SessionRecord].self, from: data)
    }

    private static func defaultDirectory(_ fm: FileManager) -> URL {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return support.appendingPathComponent("Tomafoco", isDirectory: true)
    }
}
