import Foundation

/// Decide se uma URL aberta no navegador deve ser bloqueada (RF-02).
///
/// Pura e sem dependência de AppKit: o adapter de navegador lê as abas e pergunta aqui.
/// Bloquear a URL errada é pior que deixar passar — fechar a aba de trabalho de alguém destrói
/// contexto —, então o casamento é conservador: só `http`/`https`, por host e (opcionalmente) por
/// segmento inteiro de caminho, nunca por substring.
public enum URLBlockingPolicy {

    /// Esquemas em que faz sentido intervir. `file:`, `about:`, `chrome:` etc. ficam de fora:
    /// são páginas internas do navegador (inclusive a nossa própria página de bloqueio).
    private static let interceptableSchemes: Set<String> = ["http", "https"]

    /// A URL pertence a algum dos domínios bloqueados?
    public static func isBlocked(urlString: String, domains: [BlockedDomain]) -> Bool {
        guard !domains.isEmpty, let components = components(of: urlString),
              let host = normalizedHost(components) else { return false }
        let path = components.path.lowercased()
        return domains.contains { matches(host: host, path: path, domain: $0) }
    }

    /// Host normalizado da URL, ou `nil` quando não há o que bloquear.
    public static func host(of urlString: String) -> String? {
        components(of: urlString).flatMap(normalizedHost)
    }

    private static func components(of urlString: String) -> URLComponents? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              interceptableSchemes.contains(scheme) else { return nil }
        return components
    }

    private static func normalizedHost(_ components: URLComponents) -> String? {
        guard var host = components.host?.lowercased(), !host.isEmpty else { return nil }
        // Raiz DNS explícita ("globo.com.") é o mesmo host.
        while host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }

    /// Host completo (FEAT-002): `www.globo.com` casa só `www.globo.com`. O curinga `*.globo.com`
    /// casa `globo.com` e qualquer subdomínio. `naoglobo.com` **nunca** casa: exige o ponto separador.
    ///
    /// Com caminho, casa por segmento inteiro: `/shorts` pega `/shorts` e `/shorts/abc`, nunca
    /// `/shortsxyz` nem `/`.
    private static func matches(host: String, path: String, domain: BlockedDomain) -> Bool {
        let hostMatches = host == domain.host
            || (domain.includesSubdomains && host.hasSuffix(".\(domain.host)"))
        guard hostMatches else { return false }
        guard let prefix = domain.path else { return true }
        return path == prefix || path.hasPrefix(prefix + "/")
    }
}
