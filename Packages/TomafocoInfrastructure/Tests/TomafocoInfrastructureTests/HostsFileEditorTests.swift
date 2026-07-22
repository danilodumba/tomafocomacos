import XCTest
import TomafocoDomain
@testable import TomafocoInfrastructure

/// Cobertura de RNF-01: a lógica que jamais pode corromper o /etc/hosts (T-13).
final class HostsFileEditorTests: XCTestCase {

    private let original = """
    ##
    # Host Database
    ##
    127.0.0.1\tlocalhost
    255.255.255.255\tbroadcasthost
    ::1\tlocalhost

    """

    private func domains(_ raws: [String]) throws -> [BlockedDomain] {
        try raws.map { try BlockedDomain(raw: $0) }
    }

    func test_inserting_anexaBlocoPreservandoOriginal() throws {
        let result = HostsFileEditor.inserting(domains: try domains(["twitter.com"]), into: original)
        XCTAssertTrue(result.hasPrefix(original.trimmingCharacters(in: .newlines)))
        XCTAssertTrue(result.contains("127.0.0.1\ttwitter.com"))
        XCTAssertTrue(result.contains("127.0.0.1\twww.twitter.com"))
        XCTAssertTrue(result.contains(HostsFileEditor.markerStart))
        XCTAssertTrue(result.contains(HostsFileEditor.markerEnd))
    }

    /// Sem o `::1` do `www.`, um host com registro AAAA continuava resolvendo por IPv6 e o
    /// bloqueio vazava — foi o que aconteceu na validação manual de 2026-07-22.
    func test_blockText_cobreIPv4EIPv6_paraRaizEWww() throws {
        let block = HostsFileEditor.blockText(for: try domains(["twitter.com"]))

        for line in ["127.0.0.1\ttwitter.com", "127.0.0.1\twww.twitter.com",
                     "::1\ttwitter.com", "::1\twww.twitter.com"] {
            XCTAssertTrue(block.contains(line), "faltou a linha: \(line)")
        }
    }

    func test_inserting_ehIdempotente_naoDuplicaBloco() throws {
        let ds = try domains(["youtube.com"])
        let once = HostsFileEditor.inserting(domains: ds, into: original)
        let twice = HostsFileEditor.inserting(domains: ds, into: once)
        XCTAssertEqual(once, twice)
        // apenas um par de marcadores
        XCTAssertEqual(occurrences(of: HostsFileEditor.markerStart, in: twice), 1)
    }

    func test_removingBlock_restauraConteudoOriginal() throws {
        let blocked = HostsFileEditor.inserting(domains: try domains(["twitter.com", "reddit.com"]), into: original)
        let restored = HostsFileEditor.removingBlock(from: blocked)
        // idempotência do ciclo: original a menos de newline final normalizada
        XCTAssertEqual(restored.trimmingCharacters(in: .newlines),
                       original.trimmingCharacters(in: .newlines))
    }

    func test_removingBlock_semBloco_ehNoOp() {
        XCTAssertEqual(HostsFileEditor.removingBlock(from: original), original)
    }

    func test_removingBlock_comBlocoNoMeio_removeApenasOBloco() throws {
        // Simula edição externa que deixou o bloco no meio do arquivo.
        let blockText = HostsFileEditor.blockText(for: try domains(["twitter.com"]))
        let middle = """
        127.0.0.1\tlocalhost
        \(blockText)
        10.0.0.5\tmeu-servidor.local
        """
        let restored = HostsFileEditor.removingBlock(from: middle)
        XCTAssertFalse(restored.contains(HostsFileEditor.markerStart))
        XCTAssertTrue(restored.contains("127.0.0.1\tlocalhost"))
        XCTAssertTrue(restored.contains("10.0.0.5\tmeu-servidor.local"))
    }

    func test_inserting_arquivoSemNewlineFinal_naoCorrompe() throws {
        let noNewline = "127.0.0.1\tlocalhost"
        let result = HostsFileEditor.inserting(domains: try domains(["x.com"]), into: noNewline)
        XCTAssertTrue(result.contains("127.0.0.1\tlocalhost\n"))
        XCTAssertTrue(result.contains(HostsFileEditor.markerStart))
    }

    func test_inserting_arquivoVazio_geraApenasBloco() throws {
        let result = HostsFileEditor.inserting(domains: try domains(["x.com"]), into: "")
        XCTAssertTrue(result.hasPrefix(HostsFileEditor.markerStart))
    }

    // MARK: helpers

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
