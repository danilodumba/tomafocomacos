import Foundation
import os
import SwiftData
import TomafocoDomain

/// Banco do app (FEAT-006, ADR-11): `ModelContainer` + o `mainContext` que todos os stores
/// compartilham. `@MainActor` porque o `ModelContext` não é `Sendable` — os ports também são.
///
/// Sem autosave: cada operação de store chama `commit()`, que grava na hora — o failsafe da
/// sessão ativa não pode depender de um autosave que talvez não rode antes de um crash. Dentro
/// de `perform(_:)` o `commit()` é adiado até o fim do bloco (uma transação só) e um erro
/// desfaz tudo (`rollback`).
@MainActor
public final class TomafocoDatabase: UnitOfWork {

    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }
    /// O store existente não abriu e foi trocado por um vazio (o antigo ficou como `.bak-…`).
    /// O importador usa isso para recuperar dos `*.json.migrated`, e o app avisa o usuário.
    public let wasReset: Bool
    /// Banco só em memória (testes, ou o app quando nem um banco novo abriu): nada vai para o
    /// disco, então o importador **não** pode rodar — renomearia os JSON sem ter salvo nada.
    public let isInMemory: Bool

    private var transactionDepth = 0
    /// Um `perform` aninhado falhou: o externo tem que desfazer tudo ao terminar.
    private var rollbackOnly = false
    /// Avisados quando um `rollback` descarta gravações — stores com espelho em memória
    /// (`SwiftDataTaskStore`) precisam reler do banco.
    private var rollbackObservers: [() -> Void] = []
    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "Database")

    private init(container: ModelContainer, wasReset: Bool, isInMemory: Bool = false) {
        self.container = container
        self.wasReset = wasReset
        self.isInMemory = isInMemory
        container.mainContext.autosaveEnabled = false
    }

    /// Banco em memória — testes.
    public static func inMemory() throws -> TomafocoDatabase {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return TomafocoDatabase(container: try makeContainer(configuration), wasReset: false, isInMemory: true)
    }

    /// Abre (ou cria) o banco em `url`. Se o arquivo existente não abrir (corrompido, esquema
    /// incompatível), renomeia o trio `.store`/`-wal`/`-shm` para `.bak-<data>` — dado do usuário
    /// nunca é apagado — e cria um novo.
    ///
    /// `wasReset` sai do **disco**, não só desta execução: banco criado do zero com um `.bak-…`
    /// ao lado também conta (a tentativa anterior renomeou e depois falhou ao criar o novo). Assim
    /// o aviso ao usuário não depende de o processo que fez o rename ter sobrevivido.
    public static func open(at url: URL, fileManager: FileManager = .default, now: Date = Date(),
                            retryDelay: TimeInterval = 0.3) throws -> TomafocoDatabase {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existed = fileManager.fileExists(atPath: url.path)
        let resetBefore = !existed && hasBackup(of: url, fileManager: fileManager)
        do {
            return TomafocoDatabase(container: try makeContainer(ModelConfiguration(url: url)), wasReset: resetBefore)
        } catch {
            logger.error("Banco não abriu, tentando de novo: \(String(describing: error), privacy: .public)")
        }
        // Segunda tentativa, com uma pausa, antes de mexer no arquivo: falha passageira (volume
        // montando, arquivo em uso por outro processo) não pode mandar os dados para o `.bak`.
        Thread.sleep(forTimeInterval: retryDelay)
        do {
            return TomafocoDatabase(container: try makeContainer(ModelConfiguration(url: url)), wasReset: resetBefore)
        } catch {
            logger.error("Banco não abriu, preservando como .bak: \(String(describing: error), privacy: .public)")
            backUp(storeAt: url, fileManager: fileManager, now: now)
            return TomafocoDatabase(container: try makeContainer(ModelConfiguration(url: url)), wasReset: true)
        }
    }

    /// `~/Library/Application Support/Tomafoco/Tomafoco.store`, ao lado dos JSON antigos.
    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("Tomafoco", isDirectory: true)
            .appendingPathComponent("Tomafoco.store")
    }

    // MARK: - Transação

    /// Executa `work` como uma transação só: as gravações dos stores lá dentro só vão para o
    /// disco no fim; erro → `rollback` e relança.
    ///
    /// Aninhado: o SwiftData não tem savepoint, então um bloco interno que falha **condena a
    /// transação inteira** — mesmo que o externo capture o erro e siga, ao terminar ele desfaz
    /// tudo e lança `TransactionError.aborted`. Gravar a metade do bloco interno quebraria o
    /// "tudo ou nada" do `UnitOfWork`.
    public func perform<T>(_ work: () throws -> T) throws -> T {
        transactionDepth += 1
        let result: T
        do {
            result = try work()
        } catch {
            transactionDepth -= 1
            if transactionDepth == 0 {
                rollbackOnly = false
                rollback()
            } else {
                rollbackOnly = true
            }
            throw error
        }
        // Profundidade ajustada UMA vez, antes do commit: se o `save()` lançar, o erro sobe sem
        // passar de novo por aqui (antes o catch decrementava de novo e a profundidade ia a -1,
        // desligando todas as gravações seguintes da sessão).
        transactionDepth -= 1
        if transactionDepth == 0 && rollbackOnly {
            rollbackOnly = false
            rollback()
            throw TransactionError.aborted
        }
        try commit()
        return result
    }

    public enum TransactionError: Error, Equatable {
        /// Um bloco interno falhou; a transação externa foi desfeita inteira.
        case aborted
    }

    /// Grava o que está pendente — exceto dentro de `perform`, onde quem grava é o fim do bloco.
    func commit() throws {
        guard transactionDepth == 0, context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            rollback()
            throw error
        }
    }

    func onRollback(_ observer: @escaping () -> Void) {
        rollbackObservers.append(observer)
    }

    private func rollback() {
        context.rollback()
        rollbackObservers.forEach { $0() }
    }

    // MARK: - Linhas únicas (`SingletonRecord`)

    func singleton(_ key: String) throws -> SingletonRecord? {
        var descriptor = FetchDescriptor<SingletonRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func setSingleton(_ key: String, payload: Data) throws {
        if let record = try singleton(key) {
            record.payload = payload
        } else {
            context.insert(SingletonRecord(key: key, payload: payload))
        }
    }

    func deleteSingleton(_ key: String) throws {
        if let record = try singleton(key) { context.delete(record) }
    }

    // MARK: - Privado

    private static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: TomafocoSchemaV1.self),
            migrationPlan: TomafocoMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func hasBackup(of url: URL, fileManager: FileManager) -> Bool {
        let directory = url.deletingLastPathComponent().path
        let prefix = url.lastPathComponent + ".bak-"
        return ((try? fileManager.contentsOfDirectory(atPath: directory)) ?? []).contains { $0.hasPrefix(prefix) }
    }

    private static func backUp(storeAt url: URL, fileManager: FileManager, now: Date) {
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let target = URL(fileURLWithPath: url.path + suffix + ".bak-" + stamp)
            try? fileManager.moveItem(at: source, to: target)
        }
    }
}

/// JSON do payload das linhas. Datas no formato padrão (`Double`): o banco guarda o valor exato,
/// sem a perda de frações de segundo do ISO 8601 que os arquivos usavam. `sortedKeys` deixa a
/// saída determinística.
enum PayloadCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    static let decoder = JSONDecoder()
}
