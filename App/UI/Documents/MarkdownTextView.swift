import AppKit
import SwiftUI
import TomafocoMarkdown

/// Ponte entre a janela do documento e o `NSTextView` (FEAT-007): a barra de formatação e o
/// clique no checklist mexem no texto POR ELE, então tudo entra no desfazer (⌘Z) nativo.
@MainActor
final class MarkdownEditorController {
    /// Só existe com o editor na tela (modos Editar e Lado a lado).
    weak var textView: NSTextView?

    /// Editor de fato na tela: o `NSTextView` pode sobreviver um pouco à troca de modo (undo,
    /// autorelease) — escrever nele não chegaria ao binding e a mudança se perderia.
    private var liveTextView: NSTextView? {
        guard let textView, textView.window != nil, textView.delegate != nil else { return nil }
        return textView
    }

    func apply(_ format: MarkdownFormat) {
        guard let textView = liveTextView, textView.isEditable else { return }
        let edit = MarkdownFormatting.apply(format, to: textView.string, selection: textView.selectedRange())
        Self.replace(in: textView, with: edit.text)
        textView.setSelectedRange(edit.selection)
        textView.window?.makeFirstResponder(textView)
    }

    /// Troca o texto inteiro pelo `NSTextView` (registra desfazer). `false` = editor fora da tela.
    @discardableResult
    func replaceText(with newText: String) -> Bool {
        guard let textView = liveTextView else { return false }
        let selection = textView.selectedRange()
        Self.replace(in: textView, with: newText)
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        return true
    }

    /// Substitui só o trecho que mudou (prefixo/sufixo comuns preservados): o desfazer volta
    /// exatamente a mudança e o cursor não pula para o fim. Nunca corta um par surrogate ao meio.
    static func replace(in textView: NSTextView, with newText: String) {
        let old = textView.string as NSString
        let new = newText as NSString
        let shortest = min(old.length, new.length)
        var prefix = 0
        while prefix < shortest, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        if prefix > 0, CFStringIsSurrogateHighCharacter(old.character(at: prefix - 1)) { prefix -= 1 }
        var suffix = 0
        while suffix < shortest - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) {
            suffix += 1
        }
        if suffix > 0, CFStringIsSurrogateLowCharacter(new.character(at: new.length - suffix)) { suffix -= 1 }
        let range = NSRange(location: prefix, length: old.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        guard range.length > 0 || !replacement.isEmpty else { return }
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        // Com atributos explícitos: num texto vazio, `String` puro entraria sem fonte nem cor
        // (Helvetica preta — invisível no escuro) e a digitação seguinte herdaria isso.
        textView.textStorage?.replaceCharacters(
            in: range, with: NSAttributedString(string: replacement, attributes: MarkdownTextView.textAttributes))
        textView.didChangeText()
    }
}

/// Editor de markdown em texto puro. `NSTextView` e não `TextEditor`: no macOS 14 o `TextEditor`
/// não expõe a seleção (só no 15+), e a barra de formatação precisa dela; de quebra vêm a barra de
/// busca (⌘F) e o desfazer nativos.
struct MarkdownTextView: NSViewRepresentable {
    /// Fonte e cor de todo o texto (texto puro — não há estilo por trecho).
    static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor.labelColor
    ]

    @Binding var text: String
    let controller: MarkdownEditorController
    var isEditable = true

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        // Substituições automáticas quebrariam a sintaxe: aspas curvas, "--" virando travessão,
        // "1/2" virando fração, link detectado no meio do markdown.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.typingAttributes = Self.textAttributes
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.string = text
        textView.isEditable = isEditable
        textView.delegate = context.coordinator
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        controller.textView = textView
        // Mudança vinda de fora (clique no checklist com o editor fora do foco etc.). Digitação
        // já chegou aqui igual — o delegate atualizou o binding antes.
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        (scrollView.documentView as? NSTextView)?.delegate = nil
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
