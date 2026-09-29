import XCTest
@testable import TomafocoDomain

final class BlockedDomainTests: XCTestCase {

    func test_normalize_removeEsquemaCaminhoEPortaMasPreservaWww() throws {
        let d = try BlockedDomain(raw: "HTTPS://WWW.Twitter.com/feed?x=1")
        XCTAssertEqual(d.value, "www.twitter.com")
    }

    func test_normalize_aparaEspacosEAplicaLowercase() throws {
        let d = try BlockedDomain(raw: "   YouTube.COM  ")
        XCTAssertEqual(d.value, "youtube.com")
    }

    func test_normalize_preservaHostCompleto() throws {
        XCTAssertEqual(try BlockedDomain(raw: "ge.globo.com").value, "ge.globo.com")
        XCTAssertEqual(try BlockedDomain(raw: "https://www.ge.globo.com/futebol").value, "www.ge.globo.com")
        XCTAssertEqual(try BlockedDomain(raw: "globo.com.").value, "globo.com")
    }

    func test_curinga_aceitoENormalizado() throws {
        let d = try BlockedDomain(raw: " HTTPS://*.Globo.com/x ")
        XCTAssertEqual(d.value, "*.globo.com")
        XCTAssertEqual(d.host, "globo.com")
        XCTAssertTrue(d.includesSubdomains)
        XCTAssertFalse(try BlockedDomain(raw: "globo.com").includesSubdomains)
    }

    func test_curingaMalFormado_rejeitado() {
        for raw in ["*globo.com", "*.com", "globo.*.com", "*.", "**.globo.com"] {
            XCTAssertThrowsError(try BlockedDomain(raw: raw), raw)
        }
    }

    func test_codable_listaAntigaViraCuringa() throws {
        // Antes da FEAT-002 "globo.com" casava todos os subdomínios — migra sem perder bloqueio.
        let legacy = Data(#"[{"value":"globo.com"}]"#.utf8)
        let decoded = try JSONDecoder().decode([BlockedDomain].self, from: legacy)
        XCTAssertEqual(decoded.map(\.value), ["*.globo.com"])
    }

    func test_codable_formatoNovoPreservaExatoECuringa() throws {
        let original = [try BlockedDomain(raw: "www.globo.com"), try BlockedDomain(raw: "*.globo.com")]
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode([BlockedDomain].self, from: data), original)
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
        let a = try BlockedDomain(raw: "reddit.com")
        let b = try BlockedDomain(raw: "https://Reddit.com/r/swift")
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func test_hashable_wwwECuringaSaoEntradasDistintas() throws {
        let entries = try ["reddit.com", "www.reddit.com", "*.reddit.com"].map { try BlockedDomain(raw: $0) }
        XCTAssertEqual(Set(entries).count, 3)
    }

    func test_codable_roundTrip() throws {
        let original = try BlockedDomain(raw: "twitter.com")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BlockedDomain.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
