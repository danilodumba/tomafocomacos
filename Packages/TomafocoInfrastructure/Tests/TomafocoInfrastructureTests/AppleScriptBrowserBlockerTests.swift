import XCTest
import TomafocoDomain
@testable import TomafocoInfrastructure

/// Cobre a varredura de abas sem disparar um único Apple Event de verdade.
final class AppleScriptBrowserBlockerTests: XCTestCase {

    private static let blockPage = "file:///Applications/Tomafoco.app/Contents/Resources/blocked.html"

    // MARK: - Duplos

    private final class SpyScriptRunner: AppleScriptRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var _executed: [String] = []
        /// Saída devolvida para scripts de listagem, por nome de aplicativo.
        var tabListing: [String: String] = [:]
        var failingApplications: Set<String> = []

        var executed: [String] {
            lock.lock(); defer { lock.unlock() }
            return _executed
        }

        var redirects: [String] { executed.filter { $0.contains("set URL of tab") } }

        func run(_ source: String, targeting application: String) throws -> String {
            lock.lock(); _executed.append(source); lock.unlock()

            if failingApplications.contains(application) {
                throw AutomationError.permissionDenied(application: application)
            }
            guard source.contains("count of windows") else { return "" }
            let app = tabListing.keys.first { source.contains("\"\($0)\"") }
            return app.flatMap { tabListing[$0] } ?? ""
        }
    }

    private struct StubRunningApps: RunningApplicationsProviding {
        let bundleIDs: Set<String>
        func runningBundleIDs() -> Set<String> { bundleIDs }
    }

    // MARK: - Helpers

    private func listing(_ tabs: [(Int, Int, String)]) -> String {
        tabs.map { "\($0.0)\(BrowserScript.fieldSeparator)\($0.1)\(BrowserScript.fieldSeparator)\($0.2)" }
            .joined(separator: "\n")
    }

    private func domains(_ raws: String...) throws -> [BlockedDomain] {
        try raws.map { try BlockedDomain(raw: $0) }
    }

    private func makeSUT(
        running: Set<String> = [BrowserTarget.safari.bundleID],
        browsers: [BrowserTarget] = [.safari]
    ) -> (AppleScriptBrowserBlocker, SpyScriptRunner) {
        let runner = SpyScriptRunner()
        let sut = AppleScriptBrowserBlocker(
            blockPageURL: Self.blockPage,
            scriptRunner: runner,
            runningApps: StubRunningApps(bundleIDs: running),
            browsers: browsers,
            pollInterval: 60          // varredura periódica não interfere: os testes chamam sweep()
        )
        return (sut, runner)
    }

    // MARK: - Redirecionamento

    func test_abaBloqueada_ehRedirecionadaParaAPaginaDeBloqueio() async throws {
        let (sut, runner) = makeSUT()
        runner.tabListing = ["Safari": listing([(1, 2, "https://www.globo.com/esporte")])]

        try await sut.activate(domains: try domains("globo.com"))

        XCTAssertEqual(runner.redirects.count, 1)
        XCTAssertTrue(runner.redirects[0].contains("set URL of tab 2 of window 1"))
        XCTAssertTrue(runner.redirects[0].contains(Self.blockPage))
    }

    func test_abaPermitida_naoEhTocada() async throws {
        let (sut, runner) = makeSUT()
        runner.tabListing = ["Safari": listing([(1, 1, "https://developer.apple.com")])]

        try await sut.activate(domains: try domains("globo.com"))

        XCTAssertTrue(runner.redirects.isEmpty)
    }

    func test_varreTodasAsJanelasEAbas() async throws {
        let (sut, runner) = makeSUT()
        runner.tabListing = ["Safari": listing([
            (1, 1, "https://apple.com"),
            (1, 2, "https://globo.com"),
            (2, 1, "https://ge.globo.com/futebol"),
            (2, 2, "https://swift.org")
        ])]

        try await sut.activate(domains: try domains("globo.com"))

        XCTAssertEqual(runner.redirects.count, 2)
    }

    /// A própria página de bloqueio usa `file:` — se fosse reescrita, viraria loop infinito.
    func test_paginaDeBloqueio_naoEhReescrita() async throws {
        let (sut, runner) = makeSUT()
        runner.tabListing = ["Safari": listing([(1, 1, Self.blockPage)])]

        try await sut.activate(domains: try domains("globo.com"))

        XCTAssertTrue(runner.redirects.isEmpty)
    }

    // MARK: - Navegadores

    /// `tell application "Google Chrome"` ABRE o Chrome. Abrir navegador durante o foco seria
    /// o oposto do produto — por isso só se fala com quem já está rodando.
    func test_navegadorFechado_naoRecebeNenhumScript() async throws {
        let (sut, runner) = makeSUT(running: [BrowserTarget.safari.bundleID],
                                    browsers: [.safari, .chrome])
        runner.tabListing = ["Safari": listing([(1, 1, "https://globo.com")])]

        try await sut.activate(domains: try domains("globo.com"))

        XCTAssertFalse(runner.executed.contains { $0.contains("Google Chrome") })
        XCTAssertEqual(runner.redirects.count, 1)
    }

    func test_variosNavegadoresRodando_todosSaoVarridos() async throws {
        let (sut, runner) = makeSUT(
            running: [BrowserTarget.safari.bundleID, BrowserTarget.chrome.bundleID],
            browsers: [.safari, .chrome])
        runner.tabListing = [
            "Safari": listing([(1, 1, "https://globo.com")]),
            "Google Chrome": listing([(1, 1, "https://www.globo.com/tv")])
        ]

        try await sut.activate(domains: try domains("globo.com"))

        XCTAssertEqual(runner.redirects.count, 2)
    }

    /// Permissão de automação negada num navegador não pode impedir o bloqueio nos outros.
    func test_navegadorQueRecusaAutomacao_naoImpedeOsDemais() async throws {
        let (sut, runner) = makeSUT(
            running: [BrowserTarget.safari.bundleID, BrowserTarget.chrome.bundleID],
            browsers: [.safari, .chrome])
        runner.failingApplications = ["Safari"]
        runner.tabListing = ["Google Chrome": listing([(1, 1, "https://globo.com")])]

        try await sut.activate(domains: try domains("globo.com"))

        XCTAssertEqual(runner.redirects.count, 1)
        XCTAssertTrue(runner.redirects[0].contains("Google Chrome"))
    }

    /// Sem isso, um navegador sem permissão geraria um prompt/erro por segundo, para sempre.
    func test_navegadorQueRecusa_naoEhTentadoDeNovoNaMesmaSessao() async throws {
        let (sut, runner) = makeSUT()
        runner.failingApplications = ["Safari"]

        try await sut.activate(domains: try domains("globo.com"))
        let afterFirst = runner.executed.count
        sut.sweep()

        XCTAssertEqual(runner.executed.count, afterFirst)
    }

    // MARK: - Ciclo de vida

    func test_activate_ligaAVarreduraEDeactivateDesliga() async throws {
        let (sut, _) = makeSUT()

        try await sut.activate(domains: try domains("globo.com"))
        var active = await sut.isActive
        XCTAssertTrue(active)

        try await sut.deactivate()
        active = await sut.isActive
        XCTAssertFalse(active)
    }

    func test_aposDeactivate_varreduraNaoRedirecionaMais() async throws {
        let (sut, runner) = makeSUT()
        runner.tabListing = ["Safari": listing([(1, 1, "https://globo.com")])]
        try await sut.activate(domains: try domains("globo.com"))
        try await sut.deactivate()

        let afterDeactivate = runner.executed.count
        sut.sweep()

        XCTAssertEqual(runner.executed.count, afterDeactivate)
    }

    func test_listaVazia_naoLigaVarredura() async throws {
        let (sut, runner) = makeSUT()

        try await sut.activate(domains: [])

        let active = await sut.isActive
        XCTAssertFalse(active)
        XCTAssertTrue(runner.executed.isEmpty)
    }
}

/// Geração e leitura dos scripts — puro, sem AppleScript no caminho.
final class BrowserScriptTests: XCTestCase {

    func test_listTabs_usaONomeDoAplicativoEVarreJanelasEAbas() {
        let script = BrowserScript.listTabs(in: .chrome)

        XCTAssertTrue(script.contains("tell application \"Google Chrome\""))
        XCTAssertTrue(script.contains("count of windows"))
        XCTAssertTrue(script.contains("URL of tab t of window w"))
    }

    func test_redirect_apontaAAbaCertaEEscapaAspas() {
        let tab = BrowserTab(windowIndex: 2, tabIndex: 5, url: "https://globo.com")
        let script = BrowserScript.redirect(tab: tab, in: .safari, to: "file:///a\"b.html")

        XCTAssertTrue(script.contains("set URL of tab 5 of window 2"))
        XCTAssertTrue(script.contains("file:///a\\\"b.html"), "aspas na URL precisam ser escapadas")
    }

    func test_parseTabs_leAsLinhasValidas() {
        let separator = BrowserScript.fieldSeparator
        let output = """
        1\(separator)1\(separator)https://globo.com
        2\(separator)3\(separator)https://apple.com

        linha lixo
        """

        let tabs = BrowserScript.parseTabs(output)

        XCTAssertEqual(tabs, [
            BrowserTab(windowIndex: 1, tabIndex: 1, url: "https://globo.com"),
            BrowserTab(windowIndex: 2, tabIndex: 3, url: "https://apple.com")
        ])
    }

    func test_parseTabs_saidaVazia_naoQuebra() {
        XCTAssertTrue(BrowserScript.parseTabs("").isEmpty)
    }

    /// Firefox não expõe abas por AppleScript; declarar suporte seria mentira.
    func test_firefoxNaoEstaNaListaPadrao() {
        XCTAssertFalse(BrowserTarget.all.contains { $0.bundleID.contains("firefox") })
        XCTAssertEqual(BrowserTarget.all.count, 6)
    }
}
