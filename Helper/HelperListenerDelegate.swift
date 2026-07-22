import Foundation
import TomafocoInfrastructure
import Security

/// Porteiro do serviço privilegiado: só aceita conexões de um binário que satisfaça o requisito
/// de assinatura de código do Tomafoco (bundle ID + team ID + âncora Apple).
///
/// Sem esta checagem, qualquer processo local poderia falar com o helper e mexer no `/etc/hosts`.
/// A verificação usa o PID do cliente — há uma janela teórica de reuso de PID; o dano fica contido
/// porque a API do helper não executa comandos arbitrários, só aplica/remove o bloco de domínios.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard isClientTrusted(pid: connection.processIdentifier) else {
            NSLog("[tomafoco-helper] conexão recusada: assinatura do cliente não confere")
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        connection.exportedObject = HostsHelperService()
        connection.resume()
        return true
    }

    private func isClientTrusted(pid: pid_t) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            HostsHelperInfo.clientCodeRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }

        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
