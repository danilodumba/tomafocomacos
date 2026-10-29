import AppKit

/// Diálogo de recuperação pós-crash (UC-04).
///
/// É `NSAlert` e não `.sheet`: sem janela principal, o único lugar SwiftUI seria o popover do
/// `MenuBarExtra` — que não apresenta sheets e só existe enquanto o usuário o mantém aberto.
/// O alerta aparece no lançamento, independente de o usuário clicar no ícone da barra — na fila
/// do `LaunchAlert`, depois dos avisos do banco, se houver.
@MainActor
enum RecoveryAlert {

    enum Choice {
        case resume
        case discard
    }

    static func present(description: String) async -> Choice {
        let clicked = await LaunchAlert.ask(
            style: .warning,
            title: "Sessão recuperada",
            text: """
                Havia uma sessão em andamento quando o app foi encerrado.
                \(description)
                """,
            buttons: ["Retomar", "Encerrar e liberar"]) // o primeiro responde ao Enter
        return clicked == 0 ? .resume : .discard
    }
}
