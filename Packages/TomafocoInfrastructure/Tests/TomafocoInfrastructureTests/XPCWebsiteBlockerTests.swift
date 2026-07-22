import XCTest
import TomafocoDomain
@testable import TomafocoInfrastructure

/// Cobre a política de degradação do bloqueio via helper: quando usa XPC, quando cai no fallback
/// e o que NUNCA pode acontecer (foco sem bloqueio porque o helper falhou).
final class XPCWebsiteBlockerTests: XCTestCase {

    // MARK: - Duplos

    private final class SpyClient: HostsHelperClient, @unchecked Sendable {
        private(set) var applyCallCount = 0
        private(set) var removeCallCount = 0
        private(set) var lastDomains: [BlockedDomain] = []
        var errorToThrow: Error?

        func applyBlock(domains: [BlockedDomain]) async throws {
            applyCallCount += 1
            lastDomains = domains
            if let errorToThrow { throw errorToThrow }
        }

        func removeBlock() async throws {
            removeCallCount += 1
            if let errorToThrow { throw errorToThrow }
        }
    }

    private final class SpyFallback: WebsiteBlocking, @unchecked Sendable {
        private(set) var activateCallCount = 0
        private(set) var deactivateCallCount = 0
        private(set) var lastDomains: [BlockedDomain] = []
        var errorToThrow: Error?
        var active = false

        func activate(domains: [BlockedDomain]) async throws {
            activateCallCount += 1
            lastDomains = domains
            if let errorToThrow { throw errorToThrow }
            active = true
        }

        func deactivate() async throws {
            deactivateCallCount += 1
            if let errorToThrow { throw errorToThrow }
            active = false
        }

        var isActive: Bool { get async { active } }
    }

    private struct Boom: Error {}

    private func makeSUT(helperReady: Bool) -> (XPCWebsiteBlocker, SpyClient, SpyFallback) {
        let client = SpyClient()
        let fallback = SpyFallback()
        let sut = XPCWebsiteBlocker(
            client: client, fallback: fallback, isHelperReady: { helperReady })
        return (sut, client, fallback)
    }

    private func domains(_ values: String...) throws -> [BlockedDomain] {
        try values.map { try BlockedDomain(raw: $0) }
    }

    // MARK: - Helper pronto

    func test_activate_comHelperPronto_usaXPCENaoPedeSenha() async throws {
        let (sut, client, fallback) = makeSUT(helperReady: true)

        try await sut.activate(domains: try domains("twitter.com", "reddit.com"))

        XCTAssertEqual(client.applyCallCount, 1)
        XCTAssertEqual(client.lastDomains.map(\.value), ["twitter.com", "reddit.com"])
        XCTAssertEqual(fallback.activateCallCount, 0)   // nenhum prompt de senha
    }

    func test_deactivate_comHelperPronto_usaXPC() async throws {
        let (sut, client, fallback) = makeSUT(helperReady: true)

        try await sut.deactivate()

        XCTAssertEqual(client.removeCallCount, 1)
        XCTAssertEqual(fallback.deactivateCallCount, 0)
    }

    // MARK: - Helper ausente

    func test_activate_semHelper_caiNoFallbackSemChamarXPC() async throws {
        let (sut, client, fallback) = makeSUT(helperReady: false)
        let list = try domains("youtube.com")

        try await sut.activate(domains: list)

        XCTAssertEqual(client.applyCallCount, 0)
        XCTAssertEqual(fallback.activateCallCount, 1)
        XCTAssertEqual(fallback.lastDomains.map(\.value), ["youtube.com"])
    }

    func test_deactivate_semHelper_caiNoFallback() async throws {
        let (sut, client, fallback) = makeSUT(helperReady: false)

        try await sut.deactivate()

        XCTAssertEqual(client.removeCallCount, 0)
        XCTAssertEqual(fallback.deactivateCallCount, 1)
    }

    // MARK: - Helper instalado mas falhando

    /// Regra crítica (RNF-02): helper quebrado não pode deixar a sessão de foco sem bloqueio.
    func test_activate_comHelperFalhando_degradaParaFallback() async throws {
        let (sut, client, fallback) = makeSUT(helperReady: true)
        client.errorToThrow = Boom()

        try await sut.activate(domains: try domains("x.com"))

        XCTAssertEqual(client.applyCallCount, 1)
        XCTAssertEqual(fallback.activateCallCount, 1)   // degradou
        XCTAssertEqual(fallback.lastDomains.map(\.value), ["x.com"])
    }

    func test_deactivate_comHelperFalhando_degradaParaFallback() async throws {
        let (sut, client, fallback) = makeSUT(helperReady: true)
        client.errorToThrow = Boom()

        try await sut.deactivate()

        XCTAssertEqual(fallback.deactivateCallCount, 1)
    }

    /// Se o fallback também falhar, o erro precisa subir — o coordinator marca o bloqueio
    /// como indisponível e avisa o usuário (UC-01, fluxo 4a). Engolir aqui esconderia a falha.
    func test_activate_comHelperEFallbackFalhando_propagaErro() async {
        let (sut, client, fallback) = makeSUT(helperReady: true)
        client.errorToThrow = Boom()
        fallback.errorToThrow = Boom()

        do {
            try await sut.activate(domains: try domains("x.com"))
            XCTFail("esperava erro propagado")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }

    // MARK: - isActive

    func test_isActive_leDoFallback_semIrAoHelper() async throws {
        let (sut, client, fallback) = makeSUT(helperReady: true)
        fallback.active = true

        let active = await sut.isActive

        XCTAssertTrue(active)
        XCTAssertEqual(client.applyCallCount, 0)
        XCTAssertEqual(client.removeCallCount, 0)
    }

    // MARK: - Isolamento

    /// Regressão do crash de 2026-07-22: `activate` roda fora da main actor, então o closure de
    /// prontidão é chamado de um executor arbitrário. Se alguém voltar a usar
    /// `MainActor.assumeIsolated` ali, este teste aborta o processo em vez de passar silenciosamente.
    func test_isHelperReady_ehChamadoForaDaMainActor() async throws {
        let client = SpyClient()
        let fallback = SpyFallback()
        let wasOnMainThread = UncheckedBox(false)
        let sut = XPCWebsiteBlocker(client: client, fallback: fallback, isHelperReady: {
            wasOnMainThread.value = Thread.isMainThread
            return true
        })

        try await Task.detached { try await sut.activate(domains: []) }.value

        XCTAssertFalse(wasOnMainThread.value)
    }

    private final class UncheckedBox<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }
}
