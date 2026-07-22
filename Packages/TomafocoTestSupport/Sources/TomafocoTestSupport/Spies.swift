import Foundation
import TomafocoDomain

/// Spy do bloqueio de apps — registra chamadas para asserção de ordem/estado.
public final class SpyAppBlocker: AppBlocking, @unchecked Sendable {
    public private(set) var activateCallCount = 0
    public private(set) var deactivateCallCount = 0
    public private(set) var lastBundleIDs: Set<String> = []
    public var isActive = false

    public init() {}

    public func activate(blockedBundleIDs: Set<String>) {
        activateCallCount += 1
        lastBundleIDs = blockedBundleIDs
        isActive = true
    }
    public func deactivate() {
        deactivateCallCount += 1
        isActive = false
    }
}

/// Spy do bloqueio de sites. Pode simular falha na ativação (fluxo 4a do UC-01).
public final class SpyWebsiteBlocker: WebsiteBlocking, @unchecked Sendable {
    public private(set) var activateCallCount = 0
    public private(set) var deactivateCallCount = 0
    public private(set) var lastDomains: [BlockedDomain] = []
    public var activationError: Error?
    private var _isActive = false

    public init() {}

    public func activate(domains: [BlockedDomain]) async throws {
        activateCallCount += 1
        lastDomains = domains
        if let activationError { throw activationError }
        _isActive = true
    }
    public func deactivate() async throws {
        deactivateCallCount += 1
        _isActive = false
    }
    public var isActive: Bool { get async { _isActive } }
}

/// Spy de notificações.
public final class SpyNotifier: UserNotifying {
    public private(set) var events: [NotificationEvent] = []
    public init() {}
    public func notify(_ event: NotificationEvent) { events.append(event) }
}

/// Stub do seletor de aplicativos (T-20) — devolve um resultado pré-programado, sem AppKit.
public final class StubApplicationPicker: ApplicationPicking, @unchecked Sendable {
    public private(set) var pickCallCount = 0
    public var result: ApplicationPickResult

    public init(result: ApplicationPickResult = ApplicationPickResult()) {
        self.result = result
    }

    public private(set) var lastResolvedURLs: [URL] = []

    public func pickApplications() async -> ApplicationPickResult {
        pickCallCount += 1
        return result
    }

    public func applications(at urls: [URL]) -> ApplicationPickResult {
        lastResolvedURLs = urls
        return result
    }
}
