import Foundation
import TomafocoDomain

/// Bloqueio de sites por automação do navegador (ADR-8) — a mesma abordagem do Cisdem AppCrypt.
///
/// Enquanto a sessão está ativa, varre as abas abertas dos navegadores em execução e redireciona
/// as que casam com a lista para a página de bloqueio local.
///
/// Por que substituiu o `/etc/hosts` como mecanismo principal (2026-07-22): o `/etc/hosts` só vale
/// se o `mDNSResponder` reler o arquivo, o que o app não consegue forçar, e é contornado por
/// DNS de VPN corporativa e DNS-over-HTTPS do navegador. Aqui não há DNS no caminho — nem root,
/// nem prompt de senha.
///
/// Limites assumidos: só cobre os navegadores declarados em `browsers`, exige permissão de
/// Automação (uma vez por navegador) e não bloqueia tráfego fora do navegador.
public final class AppleScriptBrowserBlocker: WebsiteBlocking, @unchecked Sendable {

    private let browsers: [BrowserTarget]
    private let blockPageURL: String
    private let pollInterval: TimeInterval
    private let scriptRunner: AppleScriptRunning
    private let runningApps: RunningApplicationsProviding
    private let queue = DispatchQueue(label: "com.dsdumba.tomafoco.browser-blocker")

    private let lock = NSLock()
    private var blockedDomains: [BlockedDomain] = []
    private var timer: DispatchSourceTimer?
    /// Navegadores que recusaram automação — para não insistir a cada segundo.
    private var deniedBundleIDs: Set<String> = []

    public init(
        blockPageURL: String,
        scriptRunner: AppleScriptRunning,
        runningApps: RunningApplicationsProviding,
        browsers: [BrowserTarget] = BrowserTarget.all,
        pollInterval: TimeInterval = 1
    ) {
        self.blockPageURL = blockPageURL
        self.scriptRunner = scriptRunner
        self.runningApps = runningApps
        self.browsers = browsers
        self.pollInterval = pollInterval
    }

    // MARK: - WebsiteBlocking

    public func activate(domains: [BlockedDomain]) async throws {
        lock.lock()
        blockedDomains = domains
        deniedBundleIDs = []
        let alreadyRunning = timer != nil
        lock.unlock()

        // Passada imediata: a aba aberta agora não espera o próximo tick para ser bloqueada.
        sweep()

        guard !alreadyRunning, !domains.isEmpty else { return }
        startTimer()
    }

    public func deactivate() async throws {
        lock.lock()
        blockedDomains = []
        let current = timer
        timer = nil
        lock.unlock()
        current?.cancel()
    }

    public var isActive: Bool {
        get async {
            lock.lock(); defer { lock.unlock() }
            return timer != nil
        }
    }

    // MARK: - Varredura

    private func startTimer() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        source.setEventHandler { [weak self] in self?.sweep() }
        lock.lock(); timer = source; lock.unlock()
        source.resume()
    }

    /// Uma passada por todos os navegadores em execução.
    func sweep() {
        lock.lock()
        let domains = blockedDomains
        var denied = deniedBundleIDs
        lock.unlock()
        guard !domains.isEmpty else { return }

        let running = runningApps.runningBundleIDs()
        for browser in browsers where running.contains(browser.bundleID) && !denied.contains(browser.bundleID) {
            do {
                try redirectBlockedTabs(in: browser, domains: domains)
            } catch {
                // Permissão negada ou navegador ocupado: para de tentar até a próxima ativação.
                denied.insert(browser.bundleID)
            }
        }

        lock.lock(); deniedBundleIDs = denied; lock.unlock()
    }

    private func redirectBlockedTabs(in browser: BrowserTarget, domains: [BlockedDomain]) throws {
        let output = try scriptRunner.run(
            BrowserScript.listTabs(in: browser), targeting: browser.applicationName)
        let blocked = BrowserScript.parseTabs(output)
            .filter { URLBlockingPolicy.isBlocked(urlString: $0.url, domains: domains) }

        // De trás para frente: redirecionar não muda índices, mas se o navegador fechar uma aba
        // no meio da operação, os índices maiores são os que ficam inválidos primeiro.
        for tab in blocked.sorted(by: { $0.tabIndex > $1.tabIndex }) {
            try scriptRunner.run(
                BrowserScript.redirect(tab: tab, in: browser, to: blockPageURL),
                targeting: browser.applicationName)
        }
    }
}

// MARK: - Adapters reais

#if canImport(AppKit)
import AppKit

/// Executa AppleScript de verdade. `NSAppleScript` exige main thread.
public final class NSAppleScriptRunner: AppleScriptRunning {

    public init() {}

    /// Código do AppleScript para "Not authorized to send Apple events to <app>".
    private static let notAuthorizedCode = -1743

    public func run(_ source: String, targeting application: String) throws -> String {
        if Thread.isMainThread { return try execute(source, application) }
        return try DispatchQueue.main.sync { try execute(source, application) }
    }

    private func execute(_ source: String, _ application: String) throws -> String {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw AutomationError.executionFailed("script inválido")
        }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo["NSAppleScriptErrorNumber"] as? Int) ?? 0
            guard code != Self.notAuthorizedCode else {
                throw AutomationError.permissionDenied(application: application)
            }
            let message = (errorInfo["NSAppleScriptErrorMessage"] as? String) ?? "erro \(code)"
            throw AutomationError.executionFailed("AppleScript \(code): \(message)")
        }
        return result.stringValue ?? ""
    }
}

/// Apps em execução segundo o `NSWorkspace`.
public struct WorkspaceRunningApplications: RunningApplicationsProviding {

    public init() {}

    public func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
#endif
