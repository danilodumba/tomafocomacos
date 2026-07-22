import Foundation
import TomafocoDomain

/// Navegador controlável por Apple Events.
///
/// Safari e a família Chromium (Chrome, Edge, Brave, Opera, Vivaldi) compartilham o mesmo
/// vocabulário para `windows` / `tabs` / `URL`, então um único dialeto de script atende todos.
/// **Firefox ficou de fora de propósito:** não expõe abas por AppleScript — declarar suporte
/// e não bloquear nada seria pior que ser explícito.
public struct BrowserTarget: Equatable, Sendable {
    public let bundleID: String
    /// Nome usado no `tell application "…"`.
    public let applicationName: String

    public init(bundleID: String, applicationName: String) {
        self.bundleID = bundleID
        self.applicationName = applicationName
    }

    public static let safari = BrowserTarget(bundleID: "com.apple.Safari", applicationName: "Safari")
    public static let chrome = BrowserTarget(bundleID: "com.google.Chrome", applicationName: "Google Chrome")
    public static let edge = BrowserTarget(bundleID: "com.microsoft.edgemac", applicationName: "Microsoft Edge")
    public static let brave = BrowserTarget(bundleID: "com.brave.Browser", applicationName: "Brave Browser")
    public static let opera = BrowserTarget(bundleID: "com.operasoftware.Opera", applicationName: "Opera")
    public static let vivaldi = BrowserTarget(bundleID: "com.vivaldi.Vivaldi", applicationName: "Vivaldi")

    public static let all: [BrowserTarget] = [.safari, .chrome, .edge, .brave, .opera, .vivaldi]
}

/// Execução de AppleScript. Port para permitir teste sem disparar Apple Events de verdade.
public protocol AppleScriptRunning: Sendable {
    /// Executa e devolve o texto do resultado.
    /// - Parameter application: alvo do `tell application`, usado só para reportar qual app
    ///   negou a permissão — sem isso o erro não diria ao usuário o que autorizar.
    func run(_ source: String, targeting application: String) throws -> String
}

/// Quais apps estão rodando agora. Existe para **não lançar** navegador fechado:
/// um `tell application "Safari"` abre o Safari, e abrir navegador sozinho durante o foco
/// seria o oposto do que o produto promete.
public protocol RunningApplicationsProviding: Sendable {
    func runningBundleIDs() -> Set<String>
}

/// Uma aba encontrada na varredura.
public struct BrowserTab: Equatable, Sendable {
    public let windowIndex: Int
    public let tabIndex: Int
    public let url: String

    public init(windowIndex: Int, tabIndex: Int, url: String) {
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.url = url
    }
}

/// Geração e leitura dos scripts. Pura — testada sem tocar em AppleScript.
public enum BrowserScript {

    /// Separador improvável numa URL, usado para serializar o resultado.
    static let fieldSeparator = "\u{1F}"

    /// Script que lista `janela|aba|URL` de todas as abas abertas.
    public static func listTabs(in browser: BrowserTarget) -> String {
        """
        tell application "\(browser.applicationName)"
            set output to ""
            set windowCount to count of windows
            repeat with w from 1 to windowCount
                set tabCount to count of tabs of window w
                repeat with t from 1 to tabCount
                    set output to output & w & "\(fieldSeparator)" & t & "\(fieldSeparator)" & \
        (URL of tab t of window w) & linefeed
                end repeat
            end repeat
            return output
        end tell
        """
    }

    /// Script que redireciona uma aba específica para a página de bloqueio.
    public static func redirect(tab: BrowserTab, in browser: BrowserTarget, to url: String) -> String {
        """
        tell application "\(browser.applicationName)"
            set URL of tab \(tab.tabIndex) of window \(tab.windowIndex) to "\(escape(url))"
        end tell
        """
    }

    /// Interpreta a saída de `listTabs`. Linhas malformadas são ignoradas em silêncio —
    /// uma aba ilegível não pode derrubar a varredura das demais.
    public static func parseTabs(_ output: String) -> [BrowserTab] {
        output.components(separatedBy: .newlines).compactMap { line in
            let fields = line.components(separatedBy: fieldSeparator)
            guard fields.count >= 3,
                  let window = Int(fields[0].trimmingCharacters(in: .whitespaces)),
                  let tab = Int(fields[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            // A URL pode conter o separador? Não — mas juntar o resto é mais seguro que assumir.
            let url = fields.dropFirst(2).joined(separator: fieldSeparator)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            return BrowserTab(windowIndex: window, tabIndex: tab, url: url)
        }
    }

    /// Escapa aspas e barras para interpolar com segurança dentro do literal do AppleScript.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
