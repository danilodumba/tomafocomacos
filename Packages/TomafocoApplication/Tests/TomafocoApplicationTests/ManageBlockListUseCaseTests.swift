import XCTest
import TomafocoDomain
import TomafocoTestSupport
@testable import TomafocoApplication

final class ManageBlockListUseCaseTests: XCTestCase {

    private func makeSUT(blockList: BlockList = .init())
        -> (ManageBlockListUseCase, InMemorySettingsRepository) {
        let settings = InMemorySettingsRepository(blockList: blockList)
        return (ManageBlockListUseCase(settings: settings), settings)
    }

    private func app(_ id: String, _ name: String) -> BlockedApp {
        BlockedApp(bundleID: id, displayName: name)
    }

    // MARK: - addApps (T-20)

    func test_addApps_listaVazia_naoPersisteNada() {
        let (sut, settings) = makeSUT()
        let result = sut.addApps([])
        XCTAssertEqual(result.addedNames, [])
        XCTAssertEqual(result.duplicateNames, [])
        XCTAssertTrue(settings.blockList.apps.isEmpty)
    }

    func test_addApps_adicionaTodosEPersiste() {
        let (sut, settings) = makeSUT()
        let result = sut.addApps([app("com.slack", "Slack"), app("com.discord", "Discord")])
        XCTAssertEqual(result.addedNames, ["Slack", "Discord"])
        XCTAssertEqual(result.duplicateNames, [])
        XCTAssertEqual(settings.blockList.apps.map(\.bundleID), ["com.slack", "com.discord"])
    }

    func test_addApps_ignoraJaExistenteEReportaNome() {
        let (sut, settings) = makeSUT(blockList: BlockList(apps: [app("com.slack", "Slack")]))
        let result = sut.addApps([app("com.slack", "Slack"), app("com.discord", "Discord")])
        XCTAssertEqual(result.addedNames, ["Discord"])
        XCTAssertEqual(result.duplicateNames, ["Slack"])
        XCTAssertEqual(settings.blockList.apps.map(\.bundleID), ["com.slack", "com.discord"])
    }

    func test_addApps_deduplicaDentroDoProprioLote() {
        let (sut, _) = makeSUT()
        let result = sut.addApps([app("com.slack", "Slack"), app("com.slack", "Slack")])
        XCTAssertEqual(result.addedNames, ["Slack"])
        XCTAssertEqual(result.duplicateNames, ["Slack"])
        XCTAssertEqual(result.list.apps.count, 1)
    }

    func test_addApps_somenteDuplicatas_naoTocaNoRepositorio() {
        let existing = BlockList(apps: [app("com.slack", "Slack")])
        let settings = InMemorySettingsRepository(blockList: existing)
        let sut = ManageBlockListUseCase(settings: settings)

        let result = sut.addApps([app("com.slack", "Slack")])

        XCTAssertEqual(result.addedNames, [])
        XCTAssertEqual(settings.blockList, existing)
    }

    func test_addApps_preservaIsEnabledDoAppInformado() {
        let (sut, settings) = makeSUT()
        sut.addApps([BlockedApp(bundleID: "com.slack", displayName: "Slack", isEnabled: false)])
        XCTAssertEqual(settings.blockList.apps.first?.isEnabled, false)
    }
}
