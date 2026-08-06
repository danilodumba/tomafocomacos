import AppKit

/// Diálogo de recuperação pós-crash (UC-04).
///
/// É `NSAlert` e não `.sheet`: sem janela principal, o único lugar SwiftUI seria o popover do
/// `MenuBarExtra` — que não apresenta sheets e só existe enquanto o usuário o mantém aberto.
/// O alerta aparece no lançamento, independente de o usuário clicar no ícone da barra.
@MainActor
enum RecoveryAlert {

    enum Choice {
        case resume
        case discard
    }

    static func present(description: String) -> Choice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Sessão recuperada"
        alert.informativeText = """
            Havia uma sessão em andamento quando o app foi encerrado.
            \(description)
            """
        alert.addButton(withTitle: "Retomar")            // .alertFirstButtonReturn (padrão, Enter)
        alert.addButton(withTitle: "Encerrar e liberar")

        // App `.accessory` não vem à frente sozinho: sem isso o alerta nasceria atrás de tudo.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? .resume : .discard
    }
}
