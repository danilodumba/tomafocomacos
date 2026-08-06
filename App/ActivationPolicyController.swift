import AppKit

/// Alterna a política de ativação do app conforme existam janelas abertas.
///
/// O Tomafoco é `LSUIElement` (só barra de menus), e app `.accessory` **não exibe menu superior** —
/// sem ele, Tarefas/Relatórios/Configurações perderiam ⌘C/⌘V/⌘W nos campos de texto. Então:
/// janela de verdade na tela → `.regular` (ícone no Dock + menu); nenhuma → volta a `.accessory`.
@MainActor
final class ActivationPolicyController {

    private var observers: [NSObjectProtocol] = []

    /// Passa a observar abertura/fechamento de janelas. O controller precisa ser retido por
    /// alguém (o `AppContainer`) — sem referência forte os observers morrem junto.
    func start() {
        let center = NotificationCenter.default

        // `queue: .main` garante o main thread — daí o `assumeIsolated` (as propriedades de
        // `NSWindow` são isoladas ao main actor). Vale aqui, NUNCA em código chamado pelos ports.
        observers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow, Self.isRegularWindow(window) else { return }
                self?.setPolicy(.regular)
            }
        })

        observers.append(center.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // A janela que está fechando ainda aparece em `NSApp.windows` durante a notificação:
            // decidir agora contaria uma janela que já era.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard !NSApp.windows.contains(where: Self.isRegularWindow) else { return }
                    self?.setPolicy(.accessory)
                }
            }
        })
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
    }

    private func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // Sem reativar, a troca para `.regular` não desenha o menu superior.
        if policy == .regular { NSApp.activate(ignoringOtherApps: true) }
    }

    /// Janela "de verdade" = titulada e não-painel. Exclui o popover do `MenuBarExtra`, o aviso de
    /// app bloqueado (`NSPanel`) e as telas cheias de intervalo (`OverlayWindow`, borderless) —
    /// nenhum deles deveria colocar o app no Dock.
    private static func isRegularWindow(_ window: NSWindow) -> Bool {
        window.isVisible && window.styleMask.contains(.titled) && !(window is NSPanel)
    }
}
