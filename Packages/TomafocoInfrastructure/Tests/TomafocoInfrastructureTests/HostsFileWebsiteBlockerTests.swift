import XCTest
import TomafocoDomain
@testable import TomafocoInfrastructure

/// Teste de integração do bloqueador contra um arquivo temporário (sem root, sem dscacheutil).
/// Usa um `PrivilegeEscalating` que executa o comando via /bin/sh localmente.
final class HostsFileWebsiteBlockerTests: XCTestCase {

    /// Runner de teste: roda o shell SEM sudo (o hostsPath aponta para um temp gravável).
    private final class LocalShellPrivilegeRunner: PrivilegeEscalating, @unchecked Sendable {
        private(set) var commands: [String] = []
        func runPrivileged(command: String) async throws {
            commands.append(command)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw PrivilegeError.executionFailed("exit \(process.terminationStatus)")
            }
        }
    }

    private var hostsURL: URL!
    private var runner: LocalShellPrivilegeRunner!
    private var sut: HostsFileWebsiteBlocker!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tomafoco-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        hostsURL = dir.appendingPathComponent("hosts")
        try "127.0.0.1\tlocalhost\n".write(to: hostsURL, atomically: true, encoding: .utf8)

        runner = LocalShellPrivilegeRunner()
        sut = HostsFileWebsiteBlocker(
            privilege: runner,
            hostsPath: hostsURL.path,
            backupPath: hostsURL.path + ".bak",
            dnsFlushCommand: nil                  // não depende de dscacheutil no teste
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: hostsURL.deletingLastPathComponent())
    }

    private func readHosts() throws -> String {
        try String(contentsOf: hostsURL, encoding: .utf8)
    }

    func test_activateEntaoDeactivate_restauraArquivoOriginal() async throws {
        let before = try readHosts()

        try await sut.activate(domains: [try BlockedDomain(raw: "twitter.com")])
        let blocked = try readHosts()
        XCTAssertTrue(blocked.contains("127.0.0.1\ttwitter.com"))
        let active = await sut.isActive
        XCTAssertTrue(active)

        try await sut.deactivate()
        let after = try readHosts()
        XCTAssertEqual(after.trimmingCharacters(in: .newlines),
                       before.trimmingCharacters(in: .newlines))
        let stillActive = await sut.isActive
        XCTAssertFalse(stillActive)
    }

    func test_activateDuasVezes_naoDuplica() async throws {
        let ds = [try BlockedDomain(raw: "youtube.com")]
        try await sut.activate(domains: ds)
        try await sut.activate(domains: ds)
        let content = try readHosts()
        let count = content.components(separatedBy: HostsFileEditor.markerStart).count - 1
        XCTAssertEqual(count, 1)
    }

    func test_deactivateSemBloco_ehNoOp() async throws {
        let before = try readHosts()
        try await sut.deactivate()
        XCTAssertEqual(try readHosts(), before)
    }

    func test_activate_criaBackup() async throws {
        try await sut.activate(domains: [try BlockedDomain(raw: "x.com")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: hostsURL.path + ".bak"))
    }

    /// Cada elevação = um prompt de senha para o usuário. Escrita e flush de DNS têm que caber
    /// numa só; se alguém separar de novo, o número de prompts por ciclo dobra.
    func test_activateEDeactivate_usamUmaUnicaElevacaoCada() async throws {
        let flushing = HostsFileWebsiteBlocker(
            privilege: runner,
            hostsPath: hostsURL.path,
            backupPath: hostsURL.path + ".bak",
            dnsFlushCommand: "true"               // comando inócuo no lugar do dscacheutil
        )

        try await flushing.activate(domains: [try BlockedDomain(raw: "reddit.com")])
        XCTAssertEqual(runner.commands.count, 1)
        XCTAssertTrue(runner.commands[0].hasSuffix("; true"))

        try await flushing.deactivate()
        XCTAssertEqual(runner.commands.count, 2)
        XCTAssertTrue(runner.commands[1].hasSuffix("; true"))
    }

    /// O flush precisa RECARREGAR o resolver, não só limpar cache: `dscacheutil -flushcache`
    /// sozinho não faz o mDNSResponder reler o /etc/hosts, e o `killall -HUP` não chega ao daemon
    /// quando disparado via `do shell script`. Sem o `kickstart` o bloqueio não surte efeito.
    func test_comandoDeFlushPadrao_recarregaOResolver() {
        let command = HostsFileWebsiteBlocker.defaultDNSFlushCommand

        XCTAssertTrue(command.contains("/usr/bin/dscacheutil -flushcache"))
        XCTAssertTrue(command.contains("launchctl kickstart -k"))
        // O rótulo do macOS 26 precisa ser tentado primeiro.
        XCTAssertTrue(command.contains("system/com.apple.mDNSResponder.reloaded"))
        XCTAssertTrue(command.contains("system/com.apple.mDNSResponder "),
                      "faltou o rótulo antigo como alternativa")
        // Caminhos absolutos: `do shell script` roda com PATH mínimo.
        XCTAssertFalse(command.contains(" dscacheutil"), "use caminho absoluto")
    }

    /// Reativar com a mesma lista não reescreve o arquivo — logo, não pede senha de novo.
    func test_activateIdempotente_naoPedeNovaElevacao() async throws {
        let ds = [try BlockedDomain(raw: "instagram.com")]
        try await sut.activate(domains: ds)
        let afterFirst = runner.commands.count
        try await sut.activate(domains: ds)
        XCTAssertEqual(runner.commands.count, afterFirst)
    }
}
