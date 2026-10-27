import AppKit
import SwiftUI

extension View {
    /// Garante que a janela que hospeda esta view entre em tela cheia própria (botão verde e
    /// ⌃⌘F) em vez de só maximizar. Necessário porque o app é `LSUIElement`: a janela nasce com
    /// o app ainda `.accessory` e pode vir sem `.fullScreenPrimary`.
    func allowsFullScreen() -> some View {
        background(FullScreenCapableView())
    }
}

/// Pega a `NSWindow` hospedeira e liga `.fullScreenPrimary`. A janela só existe depois que a
/// view entra na hierarquia, por isso o ajuste também roda em `viewDidMoveToWindow`.
private struct FullScreenCapableView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowObserverView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowObserverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
            window.styleMask.insert(.resizable)
        }
    }
}
