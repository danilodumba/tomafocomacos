import XCTest
import TomafocoDomain
@testable import TomafocoInfrastructure

#if canImport(AppKit)

/// Testa a conversão URL → `BlockedApp` contra bundles `.app` sintéticos em pasta temporária.
/// A apresentação do `NSOpenPanel` em si não é testada (exige interação do usuário — T-20 é validado à mão).
final class NSOpenPanelApplicationPickerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tomafoco-picker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
        try super.tearDownWithError()
    }

    /// Cria `<nome>.app/Contents/Info.plist` com as chaves informadas.
    private func makeBundle(named name: String, info: [String: String]) throws -> URL {
        let appURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        return appURL
    }

    func test_makeResult_leBundleIDENomeDeExibicao() throws {
        let url = try makeBundle(named: "Slack", info: [
            "CFBundleIdentifier": "com.tinyspeck.slackmacgap",
            "CFBundleName": "Slack"
        ])

        let result = NSOpenPanelApplicationPicker.makeResult(from: [url])

        XCTAssertEqual(result.apps, [BlockedApp(bundleID: "com.tinyspeck.slackmacgap", displayName: "Slack")])
        XCTAssertEqual(result.unreadableNames, [])
    }

    func test_makeResult_prefereDisplayNameSobreBundleName() throws {
        let url = try makeBundle(named: "Whats", info: [
            "CFBundleIdentifier": "net.whatsapp.WhatsApp",
            "CFBundleName": "WhatsApp",
            "CFBundleDisplayName": "WhatsApp Desktop"
        ])

        let result = NSOpenPanelApplicationPicker.makeResult(from: [url])

        XCTAssertEqual(result.apps.first?.displayName, "WhatsApp Desktop")
    }

    func test_makeResult_semNomeNoPlist_usaNomeDoArquivo() throws {
        let url = try makeBundle(named: "Sem Nome", info: ["CFBundleIdentifier": "com.exemplo.semnome"])

        let result = NSOpenPanelApplicationPicker.makeResult(from: [url])

        XCTAssertEqual(result.apps.first?.displayName, "Sem Nome")
    }

    func test_makeResult_semBundleID_vaiParaUnreadable() throws {
        let url = try makeBundle(named: "Quebrado", info: ["CFBundleName": "Quebrado"])

        let result = NSOpenPanelApplicationPicker.makeResult(from: [url])

        XCTAssertTrue(result.apps.isEmpty)
        XCTAssertEqual(result.unreadableNames, ["Quebrado"])
    }

    func test_makeResult_urlInexistente_vaiParaUnreadable() {
        let url = root.appendingPathComponent("Fantasma.app", isDirectory: true)

        let result = NSOpenPanelApplicationPicker.makeResult(from: [url])

        XCTAssertTrue(result.apps.isEmpty)
        XCTAssertEqual(result.unreadableNames, ["Fantasma"])
    }

    func test_makeResult_selecaoMultipla_separaValidosDeInvalidos() throws {
        let ok = try makeBundle(named: "Discord", info: ["CFBundleIdentifier": "com.hnc.Discord"])
        let broken = try makeBundle(named: "Quebrado", info: ["CFBundleName": "Quebrado"])

        let result = NSOpenPanelApplicationPicker.makeResult(from: [ok, broken])

        XCTAssertEqual(result.apps.map(\.bundleID), ["com.hnc.Discord"])
        XCTAssertEqual(result.unreadableNames, ["Quebrado"])
    }

    func test_makeResult_listaVazia_indicaCancelamento() {
        XCTAssertTrue(NSOpenPanelApplicationPicker.makeResult(from: []).isEmpty)
    }
}

#endif
