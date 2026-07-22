import XCTest
@testable import TomafocoDomain

final class BlockListTests: XCTestCase {

    func test_activeAppBundleIDs_incluiApenasHabilitados() {
        let list = BlockList(
            domains: [],
            apps: [
                BlockedApp(bundleID: "com.tinyspeck.slackmacgap", displayName: "Slack", isEnabled: true),
                BlockedApp(bundleID: "com.hnc.Discord", displayName: "Discord", isEnabled: false)
            ]
        )
        XCTAssertEqual(list.activeAppBundleIDs, ["com.tinyspeck.slackmacgap"])
    }

    func test_activeDomains_refleteDominios() throws {
        let d = try BlockedDomain(raw: "twitter.com")
        let list = BlockList(domains: [d], apps: [])
        XCTAssertEqual(list.activeDomains, [d])
    }

    func test_codable_roundTrip() throws {
        let list = BlockList(
            domains: [try BlockedDomain(raw: "youtube.com")],
            apps: [BlockedApp(bundleID: "com.apple.Safari", displayName: "Safari")]
        )
        let data = try JSONEncoder().encode(list)
        let decoded = try JSONDecoder().decode(BlockList.self, from: data)
        XCTAssertEqual(list, decoded)
    }
}
