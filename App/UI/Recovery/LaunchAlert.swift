import AppKit

/// `NSAlert` modal dos avisos de lançamento (recuperação pós-crash, banco de dados). Único lugar
/// com a sequência estilo + ativação + `runModal`: o app é só barra de menus e nasce `.accessory`,
/// então sem `NSApp.activate` o alerta apareceria atrás de tudo.
///
/// Os alertas entram numa **fila** e aparecem um por vez, e só **depois** de o app terminar de
/// subir: o container é montado durante a inicialização das cenas, antes do
/// `applicationDidFinishLaunching`, e dois `runModal` disparados por `DispatchQueue.main.async`
/// se aninhariam (o segundo bloco roda dentro do run loop modal do primeiro — Enter fecharia o
/// alerta errado).
@MainActor
enum LaunchAlert {

    private struct Pending {
        let style: NSAlert.Style
        let title: String
        let text: String
        let buttons: [String]
        let completion: (Int) -> Void
    }

    private static var queue: [Pending] = []
    private static var isDraining = false

    /// Aviso sem resposta. Enfileirado; volta na hora.
    static func show(style: NSAlert.Style, title: String, text: String) {
        enqueue(Pending(style: style, title: title, text: text, buttons: ["OK"], completion: { _ in }))
    }

    /// Pergunta. Devolve o índice do botão clicado (0 = primeiro, que também responde ao Enter).
    static func ask(style: NSAlert.Style, title: String, text: String, buttons: [String]) async -> Int {
        await withCheckedContinuation { continuation in
            enqueue(Pending(style: style, title: title, text: text, buttons: buttons) { continuation.resume(returning: $0) })
        }
    }

    /// Último recurso (nem o banco em memória abriu): síncrono e imediato, porque quem chama vai
    /// encerrar o app em seguida — não há lançamento a esperar. Best-effort antes do `finishLaunching`.
    static func runNow(style: NSAlert.Style, title: String, text: String) {
        present(Pending(style: style, title: title, text: text, buttons: ["OK"], completion: { _ in }))
    }

    // MARK: - Fila

    private static func enqueue(_ pending: Pending) {
        queue.append(pending)
        guard !isDraining else { return } // o laço em andamento pega este também
        isDraining = true
        afterLaunch { drain() }
    }

    private static func drain() {
        while !queue.isEmpty {
            let next = queue.removeFirst()
            next.completion(present(next))
        }
        isDraining = false
    }

    @discardableResult
    private static func present(_ pending: Pending) -> Int {
        let alert = NSAlert()
        alert.alertStyle = pending.style
        alert.messageText = pending.title
        alert.informativeText = pending.text
        pending.buttons.forEach { alert.addButton(withTitle: $0) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    /// Roda `block` quando o app já terminou de subir (na próxima volta do run loop, para não
    /// modalizar no meio da montagem das cenas).
    private static func afterLaunch(_ block: @escaping @MainActor () -> Void) {
        if NSApp.isRunning {
            DispatchQueue.main.async { block() }
            return
        }
        // Só um observador por vez: `enqueue` só chega aqui quando não há drenagem em curso.
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                if let observer = launchObserver {
                    NotificationCenter.default.removeObserver(observer)
                    launchObserver = nil
                }
                block()
            }
        }
    }

    private static var launchObserver: NSObjectProtocol?
}
