import AppKit
import SwiftUI
import TomafocoDomain

/// Janela de senha (FEAT-002): desbloqueia app bloqueado e confirma ações protegidas nas
/// Configurações (desligar bloqueio contínuo, trocar/remover a senha).
///
/// Um pedido por vez: se dois apps bloqueados forem abertos juntos, o segundo prompt espera o
/// primeiro fechar em vez de empilhar janelas que disputam o foco do teclado.
@MainActor
final class AppUnlockPromptPresenter: AppUnlockPrompting {

    private var tail: Task<Void, Never>?
    private var window: PromptWindow?

    func requestPassword(appName: String, verify: @escaping (String) -> Bool) async -> Bool {
        await request(
            title: "\(appName) está bloqueado",
            message: "Digite a senha do Tomafoco para abrir. O app fica liberado até ser fechado.",
            confirmTitle: "Abrir",
            verify: verify)
    }

    /// Pedido genérico — fica aberto até acertar a senha (`true`) ou cancelar (`false`).
    func request(title: String, message: String, confirmTitle: String,
                 verify: @escaping (String) -> Bool) async -> Bool {
        let previous = tail
        let task = Task { @MainActor [weak self] () -> Bool in
            await previous?.value
            guard let self else { return false }
            return await self.show(title: title, message: message, confirmTitle: confirmTitle, verify: verify)
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    private func show(title: String, message: String, confirmTitle: String,
                      verify: @escaping (String) -> Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            var finished = false
            let finish: (Bool) -> Void = { [weak self] result in
                guard !finished else { return }
                finished = true
                self?.window?.orderOut(nil)
                self?.window = nil
                continuation.resume(returning: result)
            }

            let panel = PromptWindow(
                contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.onEscape = { finish(false) }
            panel.contentView = NSHostingView(rootView: AppUnlockPromptView(
                title: title, message: message, confirmTitle: confirmTitle,
                verify: verify,
                onUnlock: { finish(true) },
                onCancel: { finish(false) }))
            position(panel)
            window = panel

            // App de barra de menus: sem ativar, a janela aparece mas o teclado vai para outro app.
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Centro da tela onde está o cursor (mesma regra do toast de app bloqueado).
    private func position(_ panel: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.contentView?.fittingSize ?? .zero
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.midY - size.height / 2 + visible.height * 0.1))
    }
}

/// Janela `borderless` não aceita teclado por padrão — sem isso o `SecureField` não recebe foco.
private final class PromptWindow: NSWindow {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
