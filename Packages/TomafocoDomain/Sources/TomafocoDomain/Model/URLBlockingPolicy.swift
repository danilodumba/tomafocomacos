import Foundation

/// Decide se uma URL aberta no navegador deve ser bloqueada (RF-02).
///
/// Pura e sem dependência de AppKit: o adapter de navegador lê as abas e pergunta aqui.
/// Bloquear a URL errada é pior que deixar passar — fechar a aba de trabalho de alguém destrói
/// contexto —, então o casamento é conservador: só `http`/`https`, só por host, nunca por substring.
public enum URLBlockingPolicy {

    /// Esquemas em que faz sentido intervir. `file:`, `about:`, `chrome:` etc. ficam de fora:
    /// são páginas internas do navegador (inclusive a nossa própria página de bloqueio).
    private static let interceptableSchemes: Set<String> = ["http", "https"]

    /// A URL pertence a algum dos domínios bloqueados?
    public static func isBlocked(urlString: String, domains: [BlockedDomain]) -> Bool {
        guard !domains.isEmpty, let host = host(of: urlString) else { return false }
        return domains.contains { matches(host: host, domain: $0.value) }
    }

    /// Host normalizado da URL, ou `nil` quando não há o que bloquear.
    public static func host(of urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              interceptableSchemes.contains(scheme),
              var host = components.host?.lowercased(),
              !host.isEmpty else { return nil }

        // Raiz DNS explícita ("globo.com.") é o mesmo host.
        while host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }

    /// Casa o host exato e qualquer subdomínio — `m.globo.com` e `www.globo.com` são `globo.com`.
    /// `naoglobo.com` **não** casa: a comparação exige o ponto separador.
    private static func matches(host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }
}
