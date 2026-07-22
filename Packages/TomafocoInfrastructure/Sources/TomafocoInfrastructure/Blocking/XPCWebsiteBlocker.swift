import Foundation
import TomafocoDomain

/// Bloqueio de sites via helper privilegiado (ADR-4, v2) — **zero prompts de senha** depois da
/// instalação única do helper.
///
/// Implementa o mesmo port `WebsiteBlocking` do `HostsFileWebsiteBlocker`, então a troca acontece
/// só no Composition Root (OCP). Degrada para o `fallback` (AppleScript, com prompt) em dois casos:
/// helper não instalado, ou helper instalado mas falhando. O usuário nunca fica sem bloqueio.
public final class XPCWebsiteBlocker: WebsiteBlocking, @unchecked Sendable {

    private let client: HostsHelperClient
    private let fallback: WebsiteBlocking
    private let isHelperReady: @Sendable () -> Bool

    /// - Parameter isHelperReady: consultado a cada operação e **de fora da main actor**.
    ///   Precisa ser thread-safe (ver `HelperReadiness`) — ler estado `@MainActor` daqui derruba o app.
    public init(
        client: HostsHelperClient,
        fallback: WebsiteBlocking,
        isHelperReady: @escaping @Sendable () -> Bool
    ) {
        self.client = client
        self.fallback = fallback
        self.isHelperReady = isHelperReady
    }

    public func activate(domains: [BlockedDomain]) async throws {
        guard isHelperReady() else { return try await fallback.activate(domains: domains) }
        do {
            try await client.applyBlock(domains: domains)
        } catch {
            try await fallback.activate(domains: domains)
        }
    }

    public func deactivate() async throws {
        guard isHelperReady() else { return try await fallback.deactivate() }
        do {
            try await client.removeBlock()
        } catch {
            try await fallback.deactivate()
        }
    }

    /// Lê direto o `/etc/hosts` (world-readable) pelo fallback — não custa uma ida ao helper.
    public var isActive: Bool {
        get async { await fallback.isActive }
    }
}
