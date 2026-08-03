import AppKit
import Combine
import SwiftUI

/// Mostra e esconde a janela de tela cheia do intervalo conforme o `TimerViewModel`.
///
/// Vive fora do SwiftUI porque a cena precisa cobrir **todos os monitores** e ficar acima das
/// janelas dos outros apps — coisas que só o `NSWindow` resolve.
@MainActor
final class BreakOverlayPresenter {

    private let viewModel: TimerViewModel
    private var windows: [NSWindow] = []
    /// As janelas sobrevivem escondidas entre um intervalo e outro, então "tem janela" não
    /// responde mais "está na tela".
    private var isVisible = false
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
        rebuildWindowsIfScreensChanged()
        windows.forEach {
            $0.ignoresMouseEvents = false
            $0.orderFrontRegardless()
        }
        // O Esc chega via `cancelOperation` da KEY window — `orderFrontRegardless` não torna
        // key, então sem isto o atalho cairia na janela principal e a tela nunca fecharia.
        // Key na tela onde está o cursor: é onde o usuário vai apertar Esc.
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let keyWindow = windows.first { $0.screen == mouseScreen } ?? windows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }

    /// Tira a tela cheia de cena **sem destruir a janela dentro do evento que pediu o fechamento**.
    ///
    /// O "Fechar" e o Esc chegam por aqui pela cadeia de eventos do AppKit: o `sink` do
    /// `showsBreakOverlay` roda **dentro** do tratamento do clique, enquanto o `NSHostingView`
    /// ainda rastreia o mouse. Sumir com a janela nesse ponto deixa o mouse-down sem destino —
    /// o mouse-up nunca é entregue, o sistema segue achando que há um arrasto em curso e os
    /// cliques param de funcionar em tudo até o mouse ser reconectado.
    ///
    /// Daí a ordem: a janela para de aceitar mouse, a chave volta para outra janela do app e o
    /// `orderOut` só acontece na volta do run loop. As janelas são **reaproveitadas** entre um
    /// intervalo e outro em vez de liberadas — janela liberada no meio de um rastreamento é
    /// exatamente o que causa o problema.
    private func dismiss() {
        guard isVisible else { return }
        isVisible = false
        let hiding = windows

        hiding.forEach { $0.ignoresMouseEvents = true }
        // Devolve o foco antes de sumir: sem janela chave o Esc e os atalhos ficam sem destino.
        // Só entre as já visíveis — trazer de volta uma janela que o usuário fechou (Tarefas,
        // Relatórios) seria pior que ficar sem chave.
        if let key = NSApp.keyWindow, hiding.contains(key) {
            NSApp.windows
                .first { $0.canBecomeKey && $0.isVisible && !hiding.contains($0) }?
                .makeKeyAndOrderFront(nil)
        }

        DispatchQueue.main.async {
            hiding.forEach { $0.orderOut(nil) }
        }
    }

    /// Cria uma janela por monitor — cobrir só o principal deixaria o usuário escapar para o
    /// outro. Só reconstrói quando o arranjo de telas muda (monitor plugado/removido, resolução):
    /// no caso comum as mesmas janelas voltam à cena a cada intervalo.
    private func rebuildWindowsIfScreensChanged() {
        let frames = NSScreen.screens.map(\.frame)
        guard windows.map(\.frame) != frames else { return }

        windows.forEach { $0.orderOut(nil) }
        windows = frames.map { frame in
            let window = OverlayWindow(
                contentRect: frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: BreakOverlayView(viewModel: viewModel))
            window.setFrame(frame, display: true)
            // `.floating`: fica acima das janelas comuns, mas ainda dá para trocar de app com
            // ⌘Tab. Nível de screen saver sequestraria a máquina — o app é de autodisciplina,
            // não de controle parental (ver "o que o produto NÃO é" na especificação).
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.onEscape = { [weak self] in self?.viewModel.dismissBreakOverlay() }
            return window
        }
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
