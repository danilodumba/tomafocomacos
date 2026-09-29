import XCTest
@testable import TomafocoDomain

/// Falso positivo aqui fecha a aba errada do usuário — por isso a bateria puxa mais para
/// "o que NÃO pode bloquear" do que para o caminho feliz.
final class URLBlockingPolicyTests: XCTestCase {

    private func domains(_ raws: String...) throws -> [BlockedDomain] {
        try raws.map { try BlockedDomain(raw: $0) }
    }

    // MARK: - Bloqueia

    func test_hostExato_bloqueia() throws {
        XCTAssertTrue(URLBlockingPolicy.isBlocked(
            urlString: "https://globo.com/esporte", domains: try domains("globo.com")))
    }

    func test_curinga_bloqueiaRaizWwwEQualquerSubdominio() throws {
        let ds = try domains("*.globo.com")
        for url in ["https://globo.com", "https://www.globo.com", "https://m.globo.com",
                    "http://ge.globo.com/futebol", "https://a.b.globo.com"] {
            XCTAssertTrue(URLBlockingPolicy.isBlocked(urlString: url, domains: ds), url)
        }
    }

    func test_maiusculasEPorta_bloqueiam() throws {
        XCTAssertTrue(URLBlockingPolicy.isBlocked(
            urlString: "HTTPS://WWW.Globo.COM:443/feed", domains: try domains("www.globo.com")))
    }

    func test_hostComPontoFinal_bloqueia() throws {
        XCTAssertTrue(URLBlockingPolicy.isBlocked(
            urlString: "https://globo.com./", domains: try domains("globo.com")))
    }

    func test_httpTambemBloqueia() throws {
        XCTAssertTrue(URLBlockingPolicy.isBlocked(
            urlString: "http://globo.com", domains: try domains("globo.com")))
    }

    func test_qualquerDominioDaLista_bloqueia() throws {
        let ds = try domains("globo.com", "twitter.com")
        XCTAssertTrue(URLBlockingPolicy.isBlocked(urlString: "https://twitter.com/home", domains: ds))
    }

    // MARK: - NÃO bloqueia

    /// O caso perigoso: sufixo sem o ponto separador é outro site.
    func test_dominioComSufixoParecido_naoBloqueia() throws {
        let ds = try domains("globo.com", "*.globo.com")
        for url in ["https://naoglobo.com", "https://globo.com.br.evil.com", "https://xglobo.com"] {
            XCTAssertFalse(URLBlockingPolicy.isBlocked(urlString: url, domains: ds), url)
        }
    }

    /// Substring no caminho ou na query não é o host.
    func test_dominioNoCaminhoOuQuery_naoBloqueia() throws {
        let ds = try domains("globo.com")
        for url in ["https://exemplo.com/globo.com", "https://busca.com/?q=globo.com"] {
            XCTAssertFalse(URLBlockingPolicy.isBlocked(urlString: url, domains: ds), url)
        }
    }

    /// Páginas internas do navegador — e a NOSSA página de bloqueio — nunca são tocadas.
    /// Sem isso o adapter reescreveria a própria página de bloqueio em loop.
    func test_esquemasInternos_naoBloqueiam() throws {
        let ds = try domains("globo.com")
        for url in ["about:blank", "chrome://newtab", "file:///Applications/Tomafoco.app/blocked.html",
                    "safari-resource://start", "javascript:void(0)"] {
            XCTAssertFalse(URLBlockingPolicy.isBlocked(urlString: url, domains: ds), url)
        }
    }

    func test_listaVaziaOuUrlInvalida_naoBloqueiam() throws {
        XCTAssertFalse(URLBlockingPolicy.isBlocked(urlString: "https://globo.com", domains: []))
        XCTAssertFalse(URLBlockingPolicy.isBlocked(urlString: "", domains: try domains("globo.com")))
        XCTAssertFalse(URLBlockingPolicy.isBlocked(urlString: "não é url", domains: try domains("globo.com")))
    }

    // MARK: - Host completo (FEAT-002)

    func test_www_bloqueiaSoOWww() throws {
        let ds = try domains("www.globo.com")
        XCTAssertTrue(URLBlockingPolicy.isBlocked(urlString: "https://www.globo.com/x", domains: ds))
        for url in ["https://ge.globo.com", "https://globo.com", "https://m.www.globo.com"] {
            XCTAssertFalse(URLBlockingPolicy.isBlocked(urlString: url, domains: ds), url)
        }
    }

    func test_raizSemCuringa_naoBloqueiaWwwNemSubdominios() throws {
        let ds = try domains("globo.com")
        for url in ["https://www.globo.com", "https://ge.globo.com"] {
            XCTAssertFalse(URLBlockingPolicy.isBlocked(urlString: url, domains: ds), url)
        }
    }

    func test_subdominioCadastrado_bloqueiaSoEle() throws {
        let ds = try domains("ge.globo.com")
        XCTAssertTrue(URLBlockingPolicy.isBlocked(urlString: "https://ge.globo.com/futebol", domains: ds))
        for url in ["https://globo.com", "https://www.globo.com", "https://g1.globo.com",
                    "https://oge.globo.com", "https://www.ge.globo.com", "https://m.ge.globo.com"] {
            XCTAssertFalse(URLBlockingPolicy.isBlocked(urlString: url, domains: ds), url)
        }
    }

    func test_curingaDeSubdominio_bloqueiaEleEFilhosMasNaoOPai() throws {
        let ds = try domains("*.ge.globo.com")
        for url in ["https://ge.globo.com", "https://www.ge.globo.com", "https://m.ge.globo.com"] {
            XCTAssertTrue(URLBlockingPolicy.isBlocked(urlString: url, domains: ds), url)
        }
        for url in ["https://globo.com", "https://g1.globo.com"] {
            XCTAssertFalse(URLBlockingPolicy.isBlocked(urlString: url, domains: ds), url)
        }
    }

    // MARK: - host(of:)

    func test_host_extraiENormaliza() {
        XCTAssertEqual(URLBlockingPolicy.host(of: "https://WWW.Globo.com:8080/a?b=1"), "www.globo.com")
        XCTAssertNil(URLBlockingPolicy.host(of: "about:blank"))
        XCTAssertNil(URLBlockingPolicy.host(of: "https://"))
    }
}
