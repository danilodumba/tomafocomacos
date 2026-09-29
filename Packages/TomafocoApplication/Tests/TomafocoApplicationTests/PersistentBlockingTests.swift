import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

final class PersistentBlockingTests: XCTestCase {

    private var settings: InMemorySettingsRepository!
    private var appSpy: SpyAppBlocker!
    private var siteSpy: SpyWebsiteBlocker!
    private var apps: PersistentAppBlocker!
    private var sites: PersistentWebsiteBlocker!

    override func setUpWithError() throws {
        settings = InMemorySettingsRepository()
        settings.blockList = BlockList(
            domains: [try BlockedDomain(raw: "ge.globo.com")],
            apps: [BlockedApp(bundleID: "com.slack", displayName: "Slack")])
        appSpy = SpyAppBlocker()
        siteSpy = SpyWebsiteBlocker()
        apps = PersistentAppBlocker(wrapping: appSpy, settings: settings)
        sites = PersistentWebsiteBlocker(wrapping: siteSpy, settings: settings)
    }

    private func setFlags(apps: Bool, sites: Bool) {
        settings.configuration.blockAppsWhileRunning = apps
        settings.configuration.blockSitesWhileRunning = sites
    }

    // MARK: - Flags desligadas: comportamento clássico

    func test_flagsDesligadas_fimDoFocoLibera() async throws {
        setFlags(apps: false, sites: false)
        apps.activate(blockedBundleIDs: ["com.slack"])
        try await sites.activate(domains: settings.blockList.domains)

        apps.deactivate()
        try await sites.deactivate()

        XCTAssertFalse(appSpy.isActive)
        let siteActive = await siteSpy.isActive
        XCTAssertFalse(siteActive)
    }

    func test_flagsDesligadas_refreshOciosoNaoBloqueia() async throws {
        setFlags(apps: false, sites: false)
        apps.refresh()
        try await sites.refresh()
        XCTAssertEqual(appSpy.activateCallCount, 0)
        XCTAssertEqual(siteSpy.activateCallCount, 0)
    }

    // MARK: - Flags ligadas

    func test_flagsLigadas_refreshOciosoBloqueiaComListaAtual() async throws {
        setFlags(apps: true, sites: true)
        apps.refresh()
        try await sites.refresh()
        XCTAssertTrue(appSpy.isActive)
        XCTAssertEqual(appSpy.lastBundleIDs, ["com.slack"])
        XCTAssertEqual(siteSpy.lastDomains.map(\.value), ["ge.globo.com"])
    }

    func test_flagsLigadas_fimDoFocoMantemBloqueio() async throws {
        setFlags(apps: true, sites: true)
        apps.activate(blockedBundleIDs: ["com.slack"])
        try await sites.activate(domains: settings.blockList.domains)

        apps.deactivate()
        try await sites.deactivate()

        XCTAssertTrue(appSpy.isActive)
        XCTAssertEqual(appSpy.deactivateCallCount, 0)
        XCTAssertEqual(siteSpy.deactivateCallCount, 0)
        let siteActive = await siteSpy.isActive
        XCTAssertTrue(siteActive)
    }

    func test_flagsIndependentes_soAppsLigada() async throws {
        setFlags(apps: true, sites: false)
        apps.refresh()
        try await sites.refresh()
        XCTAssertTrue(appSpy.isActive)
        XCTAssertEqual(siteSpy.activateCallCount, 0)
    }

    func test_desligarFlagForaDoFoco_libera() async throws {
        setFlags(apps: true, sites: true)
        apps.refresh()
        try await sites.refresh()

        setFlags(apps: false, sites: false)
        apps.refresh()
        try await sites.refresh()

        XCTAssertFalse(appSpy.isActive)
        let siteActive = await siteSpy.isActive
        XCTAssertFalse(siteActive)
    }

    func test_listaAlteradaForaDoFoco_refreshAplicaNovaLista() async throws {
        setFlags(apps: true, sites: false)
        apps.refresh()
        settings.blockList.apps.append(BlockedApp(bundleID: "com.spotify", displayName: "Spotify"))
        apps.refresh()
        XCTAssertEqual(appSpy.lastBundleIDs, ["com.slack", "com.spotify"])
    }

    func test_listaDeSitesVazia_naoLigaVarredura() async throws {
        setFlags(apps: false, sites: true)
        settings.blockList.domains = []
        try await sites.refresh()
        XCTAssertEqual(siteSpy.activateCallCount, 0)
    }

    // MARK: - Durante o foco

    func test_refreshNoFoco_eNoOp() async throws {
        apps.activate(blockedBundleIDs: ["com.foco"])
        try await sites.activate(domains: [])
        setFlags(apps: false, sites: false)

        apps.refresh()
        try await sites.refresh()

        XCTAssertTrue(appSpy.isActive)
        XCTAssertEqual(appSpy.lastBundleIDs, ["com.foco"])
        XCTAssertEqual(appSpy.deactivateCallCount, 0)
        XCTAssertEqual(siteSpy.deactivateCallCount, 0)
    }

    // MARK: - Controller

    @MainActor
    func test_controller_refreshRepassaEReportaFalhaDeSites() async {
        setFlags(apps: true, sites: true)
        siteSpy.activationError = AutomationError.executionFailed("x")
        var failures = 0
        let controller = PersistentBlockingController(apps: apps, websites: sites) { _ in failures += 1 }

        await controller.refresh()

        XCTAssertTrue(appSpy.isActive)
        XCTAssertEqual(failures, 1)
    }
}
