import XCTest
@testable import TomafocoDomain

final class BlockedDomainTests: XCTestCase {

    func test_normalize_removeEsquemaWwwCaminhoEPorta() throws {
        let d = try BlockedDomain(raw: "HTTPS://WWW.Twitter.com/feed?x=1")
        XCTAssertEqual(d.value, "twitter.com")
    }

    func test_normalize_aparaEspacosEAplicaLowercase() throws {
        let d = try BlockedDomain(raw: "   YouTube.COM  ")
        XCTAssertEqual(d.value, "youtube.com")
    }

    func test_normalize_removePorta() throws {
        let d = try BlockedDomain(raw: "example.com:8080")
        XCTAssertEqual(d.value, "example.com")
    }

    func test_init_rejeitaDominioSemPonto() {
        XCTAssertThrowsError(try BlockedDomain(raw: "localhost")) { error in
            XCTAssertEqual(error as? DomainError, .invalidDomain("localhost"))
        }
    }

    func test_init_rejeitaStringVazia() {
        XCTAssertThrowsError(try BlockedDomain(raw: "   "))
    }

    func test_init_rejeitaTldNumerico() {
        XCTAssertThrowsError(try BlockedDomain(raw: "1.2.3.4"))
    }

    func test_init_rejeitaHifenNasBordasDoRotulo() {
        XCTAssertThrowsError(try BlockedDomain(raw: "-bad.com"))
        XCTAssertThrowsError(try BlockedDomain(raw: "bad-.com"))
    }

    func test_init_aceitaSubdominioComHifenInterno() throws {
        let d = try BlockedDomain(raw: "my-site.co.uk")
        XCTAssertEqual(d.value, "my-site.co.uk")
    }

    func test_hashable_domíniosNormalizadosIguaisSaoIguais() throws {
        let a = try BlockedDomain(raw: "www.reddit.com")
        let b = try BlockedDomain(raw: "https://reddit.com/r/swift")
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func test_codable_roundTrip() throws {
        let original = try BlockedDomain(raw: "twitter.com")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BlockedDomain.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
