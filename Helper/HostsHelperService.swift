import Foundation
import TomafocoDomain
import TomafocoInfrastructure

/// Implementação do serviço privilegiado. Roda como root sob o launchd.
///
/// Regra de ouro: **nada que vem do cliente é confiável**. Os domínios são revalidados pelo
/// `BlockedDomain` do Domain antes de tocar no `/etc/hosts`, e o conteúdo do bloco é montado aqui
/// pelo `HostsFileEditor` — o cliente nunca envia texto que vá parar no arquivo.
final class HostsHelperService: NSObject, HostsHelperProtocol {

    private let hostsPath = "/etc/hosts"
    private let backupPath = "/etc/hosts.tomafoco.bak"

    func applyBlock(domains: [String], reply: @escaping (String?) -> Void) {
        do {
            // Domínios inválidos são descartados, não abortam a operação: um item ruim na lista
            // não pode impedir o bloqueio dos demais.
            let validated = domains.compactMap { try? BlockedDomain(raw: $0) }
            let current = try readHosts()
            let updated = HostsFileEditor.inserting(domains: validated, into: current)
            guard updated != current else { return reply(nil) }   // idempotência (RNF-01)

            try? FileManager.default.removeItem(atPath: backupPath)
            try? FileManager.default.copyItem(atPath: hostsPath, toPath: backupPath)
            try write(updated)
            flushDNS()
            reply(nil)
        } catch {
            reply("falha ao aplicar bloqueio: \(error.localizedDescription)")
        }
    }

    func removeBlock(reply: @escaping (String?) -> Void) {
        do {
            let current = try readHosts()
            guard HostsFileEditor.containsBlock(current) else { return reply(nil) }
            try write(HostsFileEditor.removingBlock(from: current))
            flushDNS()
            reply(nil)
        } catch {
            reply("falha ao remover bloqueio: \(error.localizedDescription)")
        }
    }

    func version(reply: @escaping (String) -> Void) {
        reply(HostsHelperInfo.version)
    }

    // MARK: - I/O

    private func readHosts() throws -> String {
        try String(contentsOfFile: hostsPath, encoding: .utf8)
    }

    /// Escrita atômica preservando dono/permissões do `/etc/hosts` (root:wheel 0644).
    private func write(_ content: String) throws {
        let temp = "/etc/.tomafoco-hosts-\(UUID().uuidString)"
        try content.write(toFile: temp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0],
            ofItemAtPath: temp
        )
        _ = try? FileManager.default.replaceItemAt(
            URL(fileURLWithPath: hostsPath), withItemAt: URL(fileURLWithPath: temp))
        try? FileManager.default.removeItem(atPath: temp)
    }

    /// Limpar o cache não basta: o `mDNSResponder` só relê o `/etc/hosts` quando recarrega.
    /// O `kickstart` é o que realmente funciona (o `SIGHUP` nem sempre chega ao daemon).
    private func flushDNS() {
        run("/usr/bin/dscacheutil", ["-flushcache"])
        run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        // O rótulo mudou entre versões do macOS; a primeira que existir resolve.
        for label in HostsFileWebsiteBlocker.resolverServiceLabels
        where run("/bin/launchctl", ["kickstart", "-k", label]) == 0 {
            break
        }
    }

    @discardableResult
    private func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
