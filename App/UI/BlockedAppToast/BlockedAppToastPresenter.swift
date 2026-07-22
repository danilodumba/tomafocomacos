import AppKit
import SwiftUI
import TomafocoDomain
import TomafocoApplication

/// Mostra o aviso "app bloqueado" flutuando sobre o que o usuário estiver fazendo.
///
/// Um banner de notificação some no Centro de Notificações e passa despercebido justamente
/// quando o usuário está concentrado em abrir o app proibido — daí a janela própria.
@MainActor
final class BlockedAppToastPresenter {

    /// Tempo que o aviso fica na tela. Curto: é um lembrete, não um diálogo.
    private let visibleDuration: TimeInterval = 3.5
    private let topMargin: CGFloat = 24

    private var window: NSWindow?
    private var hideTask: Task<Void, Never>?
    private var throttle = BlockedAppAlertThrottle()

    func show(appName: String, now: Date = Date()) {
        guard throttle.shouldPresent(app: appName, now: now) else { return }

        // Reaproveita a janela: dois apps bloqueados em sequência trocam o texto em vez de
        // empilhar avisos sobrepostos.
        let panel = window ?? makePanel()
        panel.contentView = NSHostingView(rootView: BlockedAppToastView(appName: appName))
        panel.layoutIfNeeded()
        position(panel)
        panel.orderFrontRegardless()
        window = panel

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.visibleDuration ?? 3.5) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Chamar ao encerrar a sessão: o próximo foco deve avisar de novo desde a primeira tentativa.
    func resetThrottle() {
        throttle.reset()
    }

    private func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                    // a sombra vem da própria View
        // Não rouba clique nem foco: o usuário continua trabalhando por baixo do aviso.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    /// Topo-centro da tela onde está o cursor — em setup multi-monitor, avisar na tela que o
    /// usuário não está olhando não serve para nada.
    private func position(_ panel: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = panel.contentView?.fittingSize ?? .zero
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - topMargin
        ))
    }
}

/// Decora o notificador acrescentando o aviso na tela para app bloqueado.
///
/// Fica no App (e não na Infrastructure) porque é apresentação: o Composition Root escolhe
/// exibir; a Application só emite o evento de domínio.
final class BlockedAppToastNotifier: UserNotifying, @unchecked Sendable {

    private let wrapped: UserNotifying
    private let presenter: BlockedAppToastPresenter

    init(wrapping wrapped: UserNotifying, presenter: BlockedAppToastPresenter) {
        self.wrapped = wrapped
        self.presenter = presenter
    }

    func notify(_ event: NotificationEvent) {
        switch event {
        case .appBlocked(let name):
            // O port não é `@MainActor`; a janela exige main.
            Task { @MainActor in presenter.show(appName: name) }

        case .focusEnded:
            // Fim do foco = fim do bloqueio. Zera a represa para que a próxima sessão
            // avise já na primeira tentativa, em vez de herdar a carência da anterior.
            Task { @MainActor in presenter.resetThrottle() }

        case .shortBreakEnded, .longBreakEnded, .websiteBlockingUnavailable:
            break
        }
        wrapped.notify(event)
    }
}
