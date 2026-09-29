import XCTest
import TomafocoDomain
@testable import TomafocoInfrastructure

private final class MemorySecretStorage: SecretStorage, @unchecked Sendable {
    var data: Data?
    func read() -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() { data = nil }
}

final class KeychainAppUnlockPasswordStoreTests: XCTestCase {

    private var storage: MemorySecretStorage!
    private var store: KeychainAppUnlockPasswordStore!

    override func setUp() {
        storage = MemorySecretStorage()
        // Poucas iterações: o custo do PBKDF2 não é o que está sob teste.
        store = KeychainAppUnlockPasswordStore(storage: storage, iterations: 1_000)
    }

    func test_semSenha_naoTemSenhaENadaVerifica() {
        XCTAssertFalse(store.hasPassword)
        XCTAssertFalse(store.verify(""))
        XCTAssertFalse(store.verify("qualquer"))
    }

    func test_senhaCerta_verificaErradaNao() throws {
        try store.setPassword("foco123")
        XCTAssertTrue(store.hasPassword)
        XCTAssertTrue(store.verify("foco123"))
        XCTAssertFalse(store.verify("foco124"))
        XCTAssertFalse(store.verify("Foco123"))
    }

    func test_naoGuardaSenhaEmClaro() throws {
        try store.setPassword("segredo-unico")
        let raw = try XCTUnwrap(storage.data)
        XCTAssertNil(String(data: raw, encoding: .utf8)?.range(of: "segredo-unico"))
    }

    func test_saltDiferentePorCadastro() throws {
        try store.setPassword("mesma")
        let first = try JSONDecoder().decode(KeychainAppUnlockPasswordStore.Record.self, from: XCTUnwrap(storage.data))
        try store.setPassword("mesma")
        let second = try JSONDecoder().decode(KeychainAppUnlockPasswordStore.Record.self, from: XCTUnwrap(storage.data))
        XCTAssertNotEqual(first.salt, second.salt)
        XCTAssertNotEqual(first.hash, second.hash)
    }

    func test_trocarSenha_antigaDeixaDeValer() throws {
        try store.setPassword("antiga1")
        try store.setPassword("nova123")
        XCTAssertFalse(store.verify("antiga1"))
        XCTAssertTrue(store.verify("nova123"))
    }

    func test_remover_limpa() throws {
        try store.setPassword("foco123")
        store.removePassword()
        XCTAssertFalse(store.hasPassword)
        XCTAssertFalse(store.verify("foco123"))
    }

    func test_senhaCurta_lancaENaoGrava() {
        XCTAssertThrowsError(try store.setPassword("abc")) { error in
            XCTAssertEqual(error as? DomainError, .weakPassword(minimumLength: 4))
        }
        XCTAssertNil(storage.data)
    }

    func test_registroCorrompido_tratadoComoSemSenha() {
        storage.data = Data("lixo".utf8)
        XCTAssertFalse(store.hasPassword)
        XCTAssertFalse(store.verify("lixo"))
    }

    func test_verificaComIteracoesDoRegistro() throws {
        try store.setPassword("foco123")
        let other = KeychainAppUnlockPasswordStore(storage: storage, iterations: 5_000)
        XCTAssertTrue(other.verify("foco123"))
    }

    func test_comparacaoConstante() {
        XCTAssertTrue(KeychainAppUnlockPasswordStore.constantTimeEquals(Data([1, 2]), Data([1, 2])))
        XCTAssertFalse(KeychainAppUnlockPasswordStore.constantTimeEquals(Data([1, 2]), Data([1, 3])))
        XCTAssertFalse(KeychainAppUnlockPasswordStore.constantTimeEquals(Data([1]), Data([1, 2])))
    }
}
