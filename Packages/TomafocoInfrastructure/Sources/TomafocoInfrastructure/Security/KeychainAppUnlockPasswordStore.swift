import Foundation
import TomafocoDomain

#if canImport(CommonCrypto) && canImport(Security)
import CommonCrypto
import Security

/// Onde o segredo derivado mora. Existe para testar hash/verificação sem tocar o Keychain
/// (testes SPM rodam sem assinatura e sem acesso garantido ao chaveiro).
public protocol SecretStorage: AnyObject, Sendable {
    func read() -> Data?
    func write(_ data: Data) throws
    func delete()
}

/// Senha de desbloqueio de apps (FEAT-002).
///
/// Nunca guarda a senha: guarda PBKDF2-SHA256 com salt aleatório por senha. A comparação é em
/// tempo constante. O formato é versionado para permitir trocar parâmetros no futuro sem
/// invalidar senhas antigas.
public final class KeychainAppUnlockPasswordStore: AppUnlockPasswordStoring, @unchecked Sendable {

    struct Record: Codable, Equatable {
        var version = 1
        var iterations: Int
        var salt: Data
        var hash: Data
    }

    static let defaultIterations = 100_000
    private static let saltLength = 16
    private static let keyLength = 32

    private let storage: SecretStorage
    private let iterations: Int

    public convenience init() {
        self.init(storage: KeychainSecretStorage(
            service: "com.dsdumba.tomafoco.unlock", account: "app-unlock-password"))
    }

    init(storage: SecretStorage, iterations: Int = defaultIterations) {
        self.storage = storage
        self.iterations = iterations
    }

    public var hasPassword: Bool { record() != nil }

    public func setPassword(_ password: String) throws {
        try AppUnlockPasswordRule.validate(password)
        let salt = try Self.randomBytes(Self.saltLength)
        let hash = try Self.derive(password, salt: salt, iterations: iterations)
        let record = Record(iterations: iterations, salt: salt, hash: hash)
        try storage.write(JSONEncoder().encode(record))
    }

    public func verify(_ password: String) -> Bool {
        guard let record = record(),
              let candidate = try? Self.derive(password, salt: record.salt, iterations: record.iterations)
        else { return false }
        return Self.constantTimeEquals(candidate, record.hash)
    }

    public func removePassword() {
        storage.delete()
    }

    private func record() -> Record? {
        storage.read().flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }

    // MARK: - Cripto

    static func derive(_ password: String, salt: Data, iterations: Int) throws -> Data {
        let passwordData = Data(password.utf8)
        var derived = Data(count: keyLength)
        let status = derived.withUnsafeMutableBytes { derivedPtr in
            salt.withUnsafeBytes { saltPtr in
                passwordData.withUnsafeBytes { pwPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.baseAddress?.assumingMemoryBound(to: CChar.self), passwordData.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        derivedPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), keyLength)
                }
            }
        }
        guard status == kCCSuccess else { throw AutomationError.executionFailed("PBKDF2 \(status)") }
        return derived
    }

    private static func randomBytes(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw AutomationError.executionFailed("SecRandom \(status)") }
        return bytes
    }

    static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) { diff |= x ^ y }
        return diff == 0
    }
}

/// Item genérico do Keychain do usuário.
public final class KeychainSecretStorage: SecretStorage, @unchecked Sendable {

    private let service: String
    private let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    public func write(_ data: Data) throws {
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw AutomationError.executionFailed("Keychain \(status)")
        }
    }

    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
#endif
