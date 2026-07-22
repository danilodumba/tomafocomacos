import Foundation
import TomafocoDomain

/// Canal com o helper privilegiado, visto pelo `XPCWebsiteBlocker`.
///
/// Existe como protocolo para que o blocker seja testável sem XPC real: os testes injetam um
/// duplo que responde sucesso/erro, e o transporte fica isolado no `XPCHostsHelperClient`.
public protocol HostsHelperClient: Sendable {
    func applyBlock(domains: [BlockedDomain]) async throws
    func removeBlock() async throws
}

#if canImport(ServiceManagement)

/// Transporte real: uma conexão XPC por chamada (o helper é sem estado e as chamadas são raras).
public final class XPCHostsHelperClient: HostsHelperClient {

    private let machServiceName: String

    public init(machServiceName: String = HostsHelperInfo.machServiceName) {
        self.machServiceName = machServiceName
    }

    public func applyBlock(domains: [BlockedDomain]) async throws {
        let values = domains.map(\.value)
        try await call { proxy, reply in proxy.applyBlock(domains: values, reply: reply) }
    }

    public func removeBlock() async throws {
        try await call { proxy, reply in proxy.removeBlock(reply: reply) }
    }

    private func call(
        _ body: @escaping (HostsHelperProtocol, @escaping (String?) -> Void) -> Void
    ) async throws {
        let connection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // O error handler do XPC e o reply são mutuamente exclusivos, mas ambos podem chegar
            // em corrida; `OnceContinuation` garante um único resume (dois = crash).
            let once = OnceContinuation(continuation)

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                once.resume(throwing: PrivilegeError.executionFailed(error.localizedDescription))
            }) as? HostsHelperProtocol else {
                once.resume(throwing: PrivilegeError.executionFailed("proxy XPC inválido"))
                return
            }

            body(proxy) { errorMessage in
                if let errorMessage {
                    once.resume(throwing: PrivilegeError.executionFailed(errorMessage))
                } else {
                    once.resume(returning: ())
                }
            }
        }
    }
}

/// Garante `resume` único numa continuation compartilhada entre o error handler do XPC e o reply.
private final class OnceContinuation: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Void) {
        take()?.resume(returning: ())
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<Void, Error>? {
        lock.lock(); defer { lock.unlock() }
        let current = continuation
        continuation = nil
        return current
    }
}

#endif
