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
    /// Site de redirecionamento configurado pelo usuário (cru). Lido a cada varredura, então
    /// mudar nas Configurações reflete na próxima passada sem religar o bloqueio. `nil`/vazio
    /// → `blockPageURL`.
    private let redirectURLProvider: @Sendable () -> String?
    private let pollInterval: TimeInterval
    private let scriptRunner: AppleScriptRunning
    private let runningApps: RunningApplicationsProviding
    private let queue = DispatchQueue(label: "com.dsdumba.tomafoco.browser-blocker")

    private let lock = NSLock()
    private var blockedDomains: [BlockedDomain] = []
    private var timer: DispatchSourceTimer?
    /// Navegadores que recusaram automação — para não insistir a cada segundo.
    private var deniedBundleIDs: Set<String> = []

    /// `pollInterval` padrão de 2s: o `NSAppleScript` executa na main thread, então cada varredura
    /// custa tempo de UI — 1s de intervalo com navegador aberto vira jank contínuo durante toda a
    /// sessão de foco. 2s corta esse custo pela metade e a aba bloqueada ainda cai em ≤2s.
    public init(
        blockPageURL: String,
        scriptRunner: AppleScriptRunning,
        runningApps: RunningApplicationsProviding,
        browsers: [BrowserTarget] = BrowserTarget.all,
        pollInterval: TimeInterval = 2,
        redirectURLProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.blockPageURL = blockPageURL
        self.scriptRunner = scriptRunner
        self.runningApps = runningApps
        self.browsers = browsers
        self.pollInterval = pollInterval
        self.redirectURLProvider = redirectURLProvider
    }

    // MARK: - WebsiteBlocking

    public func activate(domains: [BlockedDomain]) async throws {
        // O timer nasce dentro do lock: checar `timer != nil` e criar fora dele permitiria a duas
        // ativações concorrentes criarem dois timers — um vazaria varrendo para sempre.
        let timerToStart: DispatchSourceTimer? = withLock {
            blockedDomains = domains
            deniedBundleIDs = []
            guard timer == nil, !domains.isEmpty else { return nil }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
            source.setEventHandler { [weak self] in self?.sweep() }
            timer = source
            return source
        }

        // Passada imediata: a aba aberta agora não espera o próximo tick para ser bloqueada.
        sweep()
        timerToStart?.resume()
    }

    public func deactivate() async throws {
        let current: DispatchSourceTimer? = withLock {
            blockedDomains = []
            let current = timer
            timer = nil
            return current
        }
        current?.cancel()
    }

    public var isActive: Bool {
        get async { withLock { timer != nil } }
    }

    // MARK: - Varredura

    /// Uma passada por todos os navegadores em execução.
    func sweep() {
        let (domains, denied) = withLock { (blockedDomains, deniedBundleIDs) }
        guard !domains.isEmpty else { return }

        var newlyDenied: Set<String> = []
        let running = runningApps.runningBundleIDs()
        for browser in browsers where running.contains(browser.bundleID) && !denied.contains(browser.bundleID) {
            do {
                try redirectBlockedTabs(in: browser, domains: domains)
            } catch AutomationError.permissionDenied {
                // Sem permissão de Automação não adianta insistir: cada tentativa repetiria o
                // erro a cada tick. Só volta a tentar na próxima ativação.
                newlyDenied.insert(browser.bundleID)
            } catch {
                // Falha transiente (navegador ocupado, diálogo modal aberto): NÃO marca como
                // negado — um soluço não pode deixar o navegador sem bloqueio pelo resto da
                // sessão. Tenta de novo no próximo tick.
            }
        }

        // Une em vez de sobrescrever: se `activate` zerou a lista no meio desta varredura,
        // sobrescrever restauraria negações antigas que acabaram de ser perdoadas.
        if !newlyDenied.isEmpty {
            withLock { deniedBundleIDs.formUnion(newlyDenied) }
        }
    }

    private func redirectBlockedTabs(in browser: BrowserTarget, domains: [BlockedDomain]) throws {
        let output = try scriptRunner.run(
            BrowserScript.listTabs(in: browser), targeting: browser.applicationName)
        let blocked = BrowserScript.parseTabs(output)
            .filter { URLBlockingPolicy.isBlocked(urlString: $0.url, domains: domains) }

        let target = redirectTarget(domains: domains)

        // De trás para frente: redirecionar não muda índices, mas se o navegador fechar uma aba
        // no meio da operação, os índices maiores são os que ficam inválidos primeiro.
        for tab in blocked.sorted(by: { $0.tabIndex > $1.tabIndex }) {
            _ = try scriptRunner.run(
                BrowserScript.redirect(tab: tab, in: browser, to: target),
                targeting: browser.applicationName)
        }
    }

    /// URL de destino da aba bloqueada: o site configurado (normalizado) ou `blockPageURL`.
    /// Se o destino configurado for ele mesmo bloqueado, cai no `blockPageURL` — senão a aba
    /// entraria em laço de redirecionamento a cada varredura.
    func redirectTarget(domains: [BlockedDomain]) -> String {
        guard let custom = Self.normalizedRedirect(redirectURLProvider()),
              !URLBlockingPolicy.isBlocked(urlString: custom, domains: domains)
        else { return blockPageURL }
        return custom
    }

    /// Normaliza o site cru das Configurações: trim, vazio → `nil`, e adiciona `https://`
    /// quando falta esquema (o AppleScript `set URL` exige URL absoluta).
    static func normalizedRedirect(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") { return trimmed }
        return "https://\(trimmed)"
    }

    /// Ponto único de exclusão. Função síncrona de propósito: chamar `NSLock.lock()` direto num
    /// contexto async gera warning (erro no Swift 6) — e o corpo aqui nunca suspende.
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
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
