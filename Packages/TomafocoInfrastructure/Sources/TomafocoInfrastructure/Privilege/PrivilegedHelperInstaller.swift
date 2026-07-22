import Foundation

/// Estado do helper privilegiado do ponto de vista do app.
public enum HelperStatus: Equatable, Sendable {
    case notInstalled
    case awaitingApproval          // registrado; falta o usuário liberar em Ajustes do Sistema
    case installed
    case unsupported(String)       // build sem assinatura válida, helper ausente do bundle, etc.

    public var isReady: Bool { self == .installed }
}

/// Operações de registro do daemon. Abstrai `SMAppService` para permitir teste sem tocar no launchd.
public protocol HelperServiceControlling: Sendable {
    var status: HelperStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// Snapshot thread-safe de "o helper está pronto?".
///
/// Existe porque `WebsiteBlocking` roda fora da main actor (pool cooperativo): ler dali um estado
/// `@MainActor` é data race — e `MainActor.assumeIsolated` **derruba o processo** quando a
/// suposição é falsa (foi exatamente o crash de 2026-07-22). Aqui a leitura é segura de qualquer thread.
public final class HelperReadiness: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    public init(isReady: Bool = false) {
        self.value = isReady
    }

    public var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func set(_ newValue: Bool) {
        lock.lock(); value = newValue; lock.unlock()
    }
}

/// Instala/remove o helper privilegiado e mantém o `readiness` sincronizado.
///
/// Sem SwiftUI/Combine: quem observa é um ViewModel na camada de apresentação.
public final class PrivilegedHelperInstaller: @unchecked Sendable {

    public private(set) var status: HelperStatus = .notInstalled
    public private(set) var lastError: String?

    /// Consultado pelo `XPCWebsiteBlocker` de fora da main actor.
    public let readiness = HelperReadiness()

    private let service: HelperServiceControlling

    public init(service: HelperServiceControlling) {
        self.service = service
        refresh()
    }

    @discardableResult
    public func refresh() -> HelperStatus {
        status = service.status
        readiness.set(status.isReady)
        return status
    }

    public func install() {
        lastError = nil
        do {
            try service.register()
        } catch {
            // Caso típico: build de desenvolvimento sem Developer ID.
            lastError = "não foi possível registrar o helper: \(error.localizedDescription)"
        }
        refresh()
    }

    public func uninstall() {
        lastError = nil
        do {
            try service.unregister()
        } catch {
            lastError = "não foi possível remover o helper: \(error.localizedDescription)"
        }
        refresh()
    }

    public func openSystemSettings() {
        service.openSystemSettings()
    }
}

#if canImport(ServiceManagement)
import ServiceManagement

/// Implementação real sobre `SMAppService.daemon` (macOS 13+).
public struct SMAppServiceControl: HelperServiceControlling {

    private let plistName: String

    public init(plistName: String = HostsHelperInfo.plistName) {
        self.plistName = plistName
    }

    private var service: SMAppService { .daemon(plistName: plistName) }

    public var status: HelperStatus {
        switch service.status {
        case .enabled: return .installed
        case .requiresApproval: return .awaitingApproval
        case .notRegistered: return .notInstalled
        case .notFound: return .unsupported("helper não encontrado no bundle do app")
        @unknown default: return .notInstalled
        }
    }

    public func register() throws { try service.register() }
    public func unregister() throws { try service.unregister() }
    public func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
#endif
