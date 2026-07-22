import AppKit
import Combine
import SwiftUI

/// Cria e destrói a janela de tela cheia do intervalo conforme o `TimerViewModel`.
///
/// Vive fora do SwiftUI porque a cena precisa cobrir **todos os monitores** e ficar acima das
/// janelas dos outros apps — coisas que só o `NSWindow` resolve.
@MainActor
final class BreakOverlayPresenter {

    private let viewModel: TimerViewModel
    private var windows: [NSWindow] = []
    private var cancellable: AnyCancellable?

    init(viewModel: TimerViewModel) {
        self.viewModel = viewModel
        cancellable = viewModel.$showsBreakOverlay
            .removeDuplicates()
            .sink { [weak self] shouldShow in
                shouldShow ? self?.present() : self?.dismiss()
            }
    }

    // MARK: - Janelas

    private func present() {
        guard windows.isEmpty else { return }

        // Uma janela por monitor: cobrir só o principal deixaria o usuário escapar para o outro.
        windows = NSScreen.screens.map { screen in
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: BreakOverlayView(viewModel: viewModel))
            window.setFrame(screen.frame, display: true)
            // `.floating`: fica acima das janelas comuns, mas ainda dá para trocar de app com
            // ⌘Tab. Nível de screen saver sequestraria a máquina — o app é de autodisciplina,
            // não de controle parental (ver "o que o produto NÃO é" na especificação).
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.onEscape = { [weak self] in self?.viewModel.dismissBreakOverlay() }
            return window
        }

        windows.forEach { $0.orderFrontRegardless() }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismiss() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

/// Janela sem barra de título que aceita foco de teclado — `borderless` não aceita por padrão,
/// e sem isso o Esc e os atalhos dos botões não funcionariam.
private final class OverlayWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
