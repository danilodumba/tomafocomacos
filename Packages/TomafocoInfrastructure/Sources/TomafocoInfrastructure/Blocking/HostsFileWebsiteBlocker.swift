import Foundation
import TomafocoDomain

/// Bloqueio de sites via `/etc/hosts` (RF-02, RNF-01).
///
/// A lógica de string vive em `HostsFileEditor` (pura/testável). Este adapter só faz I/O:
/// lê o hosts (world-readable, sem privilégio), calcula o novo conteúdo e o grava com privilégio
/// (escreve num temporário próprio e faz `cp` privilegiado, preservando permissões do destino).
///
/// Tudo é injetável (`hostsPath`, `privilege`, `dnsFlush`, `fileManager`) para permitir testes de
/// integração contra um arquivo temporário sem root e sem depender de `dscacheutil` (RNF-05).
public final class HostsFileWebsiteBlocker: WebsiteBlocking, @unchecked Sendable {

    /// Flush de DNS padrão. Vai **concatenado** ao comando de escrita: cada elevação separada
    /// abriria um prompt de senha a mais, então tudo que precisa de root anda junto.
    ///
    /// Detalhes que custaram uma sessão de depuração (2026-07-22):
    /// - `dscacheutil -flushcache` limpa o cache de DNS mas **não** faz o `mDNSResponder` reler o
    ///   `/etc/hosts`. Sem recarregar o resolver, o bloqueio simplesmente "não funciona".
    /// - `killall -HUP` funciona no Terminal com `sudo`, mas NÃO a partir do
    ///   `do shell script`: o daemon é protegido pelo SIP e o sinal não chega (comprovado —
    ///   o PID do `mDNSResponder` não mudava nem recarregava). Por isso o `launchctl kickstart -k`,
    ///   que reinicia o serviço pela via do launchd em vez de sinal.
    /// - Caminhos absolutos: `do shell script` roda com PATH mínimo.
    /// - `|| true` em cada etapa: falha no flush não pode reprovar uma escrita que já deu certo.
    /// Rótulos do serviço do resolver, em ordem de tentativa. O nome mudou entre versões do
    /// macOS (`.reloaded` no 26); tentar os dois evita quebrar de novo num upgrade.
    public static let resolverServiceLabels = [
        "system/com.apple.mDNSResponder.reloaded",
        "system/com.apple.mDNSResponder"
    ]

    public static let defaultDNSFlushCommand: String = {
        let kickstarts = resolverServiceLabels
            .map { "/bin/launchctl kickstart -k \($0)" }
            .joined(separator: " || ")
        return [
            "/usr/bin/dscacheutil -flushcache || true",
            "/usr/bin/killall -HUP mDNSResponder || true",
            "\(kickstarts) || true"
        ].joined(separator: "; ")
    }()

    private let hostsPath: String
    private let backupPath: String
    private let tempDirectory: URL
    private let privilege: PrivilegeEscalating
    private let dnsFlushCommand: String?
    private let fileManager: FileManager

    public init(
        privilege: PrivilegeEscalating,
        hostsPath: String = "/etc/hosts",
        backupPath: String? = nil,
        tempDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default,
        dnsFlushCommand: String? = defaultDNSFlushCommand
    ) {
        self.hostsPath = hostsPath
        self.backupPath = backupPath ?? (hostsPath + ".tomafoco.bak")
        self.tempDirectory = tempDirectory
        self.privilege = privilege
        self.fileManager = fileManager
        self.dnsFlushCommand = dnsFlushCommand
    }

    public func activate(domains: [BlockedDomain]) async throws {
        let current = readHosts()
        let updated = HostsFileEditor.inserting(domains: domains, into: current)
        guard updated != current else { return }         // idempotência: nada a fazer
        try await writePrivileged(updated, backupFirst: true)
    }

    public func deactivate() async throws {
        let current = readHosts()
        guard HostsFileEditor.containsBlock(current) else { return }   // no-op se não há bloco
        let updated = HostsFileEditor.removingBlock(from: current)
        try await writePrivileged(updated, backupFirst: false)
    }

    public var isActive: Bool {
        get async { HostsFileEditor.containsBlock(readHosts()) }
    }

    // MARK: - I/O

    private func readHosts() -> String {
        (try? String(contentsOfFile: hostsPath, encoding: .utf8)) ?? ""
    }

    private func writePrivileged(_ content: String, backupFirst: Bool) async throws {
        let temp = tempDirectory.appendingPathComponent("tomafoco-hosts-\(UUID().uuidString)")
        try content.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: temp) }

        let quotedTemp = shellQuote(temp.path)
        let quotedHosts = shellQuote(hostsPath)
        var command = ""
        if backupFirst {
            command += "cp \(quotedHosts) \(shellQuote(backupPath)) 2>/dev/null; "
        }
        command += "cp \(quotedTemp) \(quotedHosts)"
        if let dnsFlushCommand { command += "; \(dnsFlushCommand)" }
        try await privilege.runPrivileged(command: command)
    }

    private func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
