import Foundation

/// Value object de um domínio bloqueado. Sempre normalizado: lowercase, sem esquema, sem
/// porta, sem query/fragmento. A validação acontece na construção (fail fast).
///
/// Casamento pelo **host completo** (FEAT-002): `www.globo.com` bloqueia só `www.globo.com` —
/// não `ge.globo.com` nem `globo.com`. Para pegar o domínio e todos os subdomínios, o usuário
/// cadastra o curinga `*.globo.com`.
///
/// Caminho opcional: `www.youtube.com/shorts` bloqueia `/shorts` e tudo abaixo dele
/// (`/shorts/abc`), mas não o resto de `www.youtube.com`.
public struct BlockedDomain: Equatable, Hashable, Sendable {
    /// Host sem o curinga (`globo.com` para `*.globo.com`).
    public let host: String
    /// `true` para `*.host`: casa o próprio host e qualquer subdomínio.
    public let includesSubdomains: Bool
    /// Prefixo de caminho (`/shorts`), sem barra final; `nil` bloqueia o host inteiro.
    public let path: String?

    /// Forma exibida e digitada: `ge.globo.com`, `*.globo.com` ou `www.youtube.com/shorts`.
    public var value: String { (includesSubdomains ? "*.\(host)" : host) + (path ?? "") }

    public init(raw: String) throws {
        var (normalized, path) = Self.normalize(raw)
        let wildcard = normalized.hasPrefix("*.")
        if wildcard { normalized.removeFirst(2) }
        guard Self.isValid(normalized), path.map(Self.isValidPath) ?? true else {
            throw DomainError.invalidDomain(raw)
        }
        self.host = normalized
        self.includesSubdomains = wildcard
        self.path = path
    }

    init(host: String, includesSubdomains: Bool, path: String? = nil) {
        self.host = host
        self.includesSubdomains = includesSubdomains
        self.path = path
    }

    /// Remove esquema, porta, query, fragmento e espaços; aplica lowercase. Preserva `www.` e
    /// qualquer outro subdomínio — o host é casado inteiro. Devolve o caminho separado, sem
    /// barras finais; caminho vazio ou só `/` vira `nil` (host inteiro).
    static func normalize(_ raw: String) -> (host: String, path: String?) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        // query e fragmento nunca fazem parte do padrão
        if let idx = s.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            s = String(s[..<idx])
        }
        var path = ""
        if let slash = s.firstIndex(of: "/") {
            path = String(s[slash...])
            s = String(s[..<slash])
        }
        // porta
        if let colon = s.firstIndex(of: ":") {
            s = String(s[..<colon])
        }
        // Raiz DNS explícita ("globo.com.") é o mesmo host.
        while s.hasSuffix(".") { s.removeLast() }
        while path.hasSuffix("/") { path.removeLast() }
        return (s, path.isEmpty ? nil : path)
    }

    /// Caminho não pode ter espaço nem segmento vazio (`//`).
    static func isValidPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("//") else { return false }
        return !path.contains { $0.isWhitespace }
    }

    /// Aceita apenas hosts com pelo menos um ponto, rótulos alfanuméricos/hífen, sem hífen nas bordas.
    static func isValid(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, host.contains(".") else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard (1...63).contains(label.count) else { return false }
            guard label.first != "-", label.last != "-" else { return false }
            let allowed = label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
            guard allowed else { return false }
        }
        // o TLD (último rótulo) não pode ser puramente numérico
        if let tld = labels.last, tld.allSatisfy(\.isNumber) { return false }
        return true
    }
}

// MARK: - Codable com migração

/// Formato atual: `{"pattern": "ge.globo.com", "value": "ge.globo.com"}` (ou `*.globo.com`,
/// `www.youtube.com/shorts`).
/// Listas gravadas antes da FEAT-002 só têm `value` — e naquela época `globo.com` casava todos
/// os subdomínios. Elas decodificam como curinga (`*.globo.com`) para ninguém perder bloqueio
/// ao atualizar. `value` continua sendo gravado (só o host) para que uma versão anterior do app
/// ainda consiga ler a lista, tratando tudo como curinga.
extension BlockedDomain: Codable {
    private enum CodingKeys: String, CodingKey { case pattern, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let pattern = try c.decodeIfPresent(String.self, forKey: .pattern) {
            try self.init(raw: pattern)
        } else {
            let legacy = try c.decode(String.self, forKey: .value)
            let parsed = try BlockedDomain(raw: legacy)
            self.init(host: parsed.host, includesSubdomains: true, path: parsed.path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .pattern)
        try c.encode(host, forKey: .value)
    }
}
