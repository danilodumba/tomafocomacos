import Foundation
import TomafocoDomain

/// Manipulação PURA do conteúdo do `/etc/hosts` (RNF-01). Sem I/O e sem privilégio — recebe e
/// devolve `String`. Toda a garantia de "nunca corromper o hosts" é testável aqui, isoladamente.
///
/// Invariantes:
/// - `inserting` é idempotente: aplicar 2x não duplica o bloco.
/// - `removingBlock` sem bloco presente é no-op.
/// - `removingBlock(inserting(x)) == x` (a menos de uma newline final normalizada).
public enum HostsFileEditor {
    public static let markerStart = "# Tomafoco-START (não edite este bloco manualmente)"
    public static let markerEnd = "# Tomafoco-END"

    /// Linhas de bloqueio para os domínios (host raiz + `www.`), redirecionando para loopback.
    public static func blockText(for domains: [BlockedDomain]) -> String {
        guard !domains.isEmpty else { return "\(markerStart)\n\(markerEnd)" }
        // IPv4 e IPv6 para raiz E `www.`: faltando o `::1` do `www.`, um host com AAAA resolvia
        // normalmente por IPv6 e o bloqueio vazava.
        let entries = domains.flatMap { domain -> [String] in
            [
                "127.0.0.1\t\(domain.value)",
                "127.0.0.1\twww.\(domain.value)",
                "::1\t\(domain.value)",
                "::1\twww.\(domain.value)"
            ]
        }
        return ([markerStart] + entries + [markerEnd]).joined(separator: "\n")
    }

    /// Insere (ou substitui) o bloco delimitado ao final do arquivo, preservando o conteúdo original.
    public static func inserting(domains: [BlockedDomain], into hosts: String) -> String {
        let base = removingBlock(from: hosts)
        let trimmed = base.hasSuffix("\n") ? String(base.dropLast()) : base
        let prefix = trimmed.isEmpty ? "" : "\(trimmed)\n"
        return "\(prefix)\(blockText(for: domains))\n"
    }

    /// Remove SOMENTE as linhas entre os marcadores (inclusive). Sem bloco → devolve inalterado.
    public static func removingBlock(from hosts: String) -> String {
        guard hosts.contains(markerStart) else { return hosts }

        // Preserva a terminação de linha original ao remontar.
        let lines = hosts.components(separatedBy: "\n")
        var result: [String] = []
        var insideBlock = false
        for line in lines {
            if line == markerStart { insideBlock = true; continue }
            if line == markerEnd { insideBlock = false; continue }
            if !insideBlock { result.append(line) }
        }
        // Remove uma eventual linha em branco deixada onde estava o bloco, no fim do arquivo.
        while result.count > 1, result.last == "", result[result.count - 2] == "" {
            result.removeLast()
        }
        return result.joined(separator: "\n")
    }

    /// O conteúdo contém o bloco do Tomafoco?
    public static func containsBlock(_ hosts: String) -> Bool {
        hosts.contains(markerStart)
    }
}
