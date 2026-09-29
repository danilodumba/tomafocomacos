import Foundation
import TomafocoDomain

/// Bloqueio contínuo — "enquanto o Tomafoco estiver aberto" (FEAT-002).
///
/// Decoradores dos ports de bloqueio: o `SessionCoordinator` e o `RecoverFromCrashUseCase`
/// continuam pedindo `activate`/`deactivate` só no foco, e a máquina de estados segue pura.
/// A diferença mora aqui: quando o foco termina e a flag correspondente está ligada, em vez
/// de derrubar o bloqueio, ele volta a valer com a lista atual.
///
/// Invariante ajustado: "o fim do foco derruba o bloqueio" → "derruba, salvo flag ligada".
public final class PersistentAppBlocker: AppBlocking, @unchecked Sendable {

    private let inner: AppBlocking
    private let settings: SettingsRepository
    private let lock = NSLock()
    private var focusActive = false

    public init(wrapping inner: AppBlocking, settings: SettingsRepository) {
        self.inner = inner
        self.settings = settings
    }

    /// Vindo do foco: a lista do foco vale até ele acabar.
    public func activate(blockedBundleIDs: Set<String>) {
        withLock { focusActive = true }
        inner.activate(blockedBundleIDs: blockedBundleIDs)
    }

    /// Fim do foco: cai para o bloqueio contínuo (se ligado) ou libera.
    public func deactivate() {
        withLock { focusActive = false }
        applyIdleState()
    }

    /// Reaplica o estado fora do foco — chamar no lançamento e quando a flag ou a lista mudar.
    /// No foco é no-op: o foco usa a lista capturada na ativação, como sempre.
    public func refresh() {
        guard !withLock({ focusActive }) else { return }
        applyIdleState()
    }

    private func applyIdleState() {
        if settings.loadConfiguration().blockAppsWhileRunning {
            inner.activate(blockedBundleIDs: settings.loadBlockList().activeAppBundleIDs)
        } else {
            inner.deactivate()
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}

/// Contraparte de sites do `PersistentAppBlocker` — mesma regra.
public final class PersistentWebsiteBlocker: WebsiteBlocking, @unchecked Sendable {

    private let inner: WebsiteBlocking
    private let settings: SettingsRepository
    private let lock = NSLock()
    private var focusActive = false

    public init(wrapping inner: WebsiteBlocking, settings: SettingsRepository) {
        self.inner = inner
        self.settings = settings
    }

    public func activate(domains: [BlockedDomain]) async throws {
        withLock { focusActive = true }
        try await inner.activate(domains: domains)
    }

    public func deactivate() async throws {
        withLock { focusActive = false }
        try await applyIdleState()
    }

    public var isActive: Bool {
        get async { await inner.isActive }
    }

    /// Ver `PersistentAppBlocker.refresh()`.
    public func refresh() async throws {
        guard !withLock({ focusActive }) else { return }
        try await applyIdleState()
    }

    private func applyIdleState() async throws {
        let domains = settings.loadBlockList().activeDomains
        if settings.loadConfiguration().blockSitesWhileRunning, !domains.isEmpty {
            try await inner.activate(domains: domains)
        } else {
            try await inner.deactivate()
        }
    }

    /// Síncrona de propósito: `NSLock` direto em contexto async é erro no Swift 6.
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}

/// Fachada que a apresentação chama quando algo que afeta o bloqueio contínuo muda
/// (lançamento do app, flags, lista de bloqueio).
@MainActor
public final class PersistentBlockingController {

    private let apps: PersistentAppBlocker
    private let websites: PersistentWebsiteBlocker
    private let onWebsiteFailure: (Error) -> Void

    public init(
        apps: PersistentAppBlocker,
        websites: PersistentWebsiteBlocker,
        onWebsiteFailure: @escaping (Error) -> Void = { _ in }
    ) {
        self.apps = apps
        self.websites = websites
        self.onWebsiteFailure = onWebsiteFailure
    }

    public func refresh() async {
        apps.refresh()
        do { try await websites.refresh() } catch { onWebsiteFailure(error) }
    }
}
