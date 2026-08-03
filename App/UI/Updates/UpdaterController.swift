import Combine
import Foundation
import Sparkle

/// Fachada fina sobre o Sparkle (ADR-9) — atualização automática fora da Mac App Store.
///
/// Fica em `App/` porque atualizar é apresentação: o `SPUStandardUpdaterController` traz a
/// própria UI (diálogo de versão nova, notas de release, barra de progresso, reinício). Não há
/// port no Domain justamente porque não há nada de domínio aqui — e envolver o Sparkle num
/// protocolo só produziria uma indireção que ninguém troca.
@MainActor
final class UpdaterController: ObservableObject {

    /// Espelha `SPUUpdater.automaticallyChecksForUpdates` para o toggle das Configurações.
    ///
    /// A fonte da verdade é o Sparkle (grava em `UserDefaults` na chave `SUEnableAutomaticChecks`),
    /// **não** `PomodoroConfiguration`: quem faz a pergunta de primeira execução ("posso checar
    /// atualizações automaticamente?") é o próprio Sparkle, então uma cópia nossa divergiria
    /// silenciosamente da resposta que o usuário deu ao diálogo.
    @Published var automaticallyChecks: Bool {
        didSet {
            guard updater.automaticallyChecksForUpdates != automaticallyChecks else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }

    /// Falso enquanto uma checagem já está em andamento — desabilita o botão/menu.
    @Published private(set) var canCheckForUpdates = true

    /// Última checagem bem-sucedida, para o rodapé das Configurações. `nil` = nunca checou.
    @Published private(set) var lastCheckDate: Date?

    private let controller: SPUStandardUpdaterController

    private var updater: SPUUpdater { controller.updater }

    init() {
        // `startingUpdater: true` — o Sparkle sobe junto com o app, lê `SUFeedURL`/`SUPublicEDKey`
        // do Info.plist e agenda a checagem periódica (`SUScheduledCheckInterval`).
        // Sem delegates: o comportamento padrão já é o desejado — checa em segundo plano e
        // PERGUNTA antes de baixar/instalar, nunca troca a versão sem o usuário mandar.
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Atribuição dentro do `init` não dispara `didSet` — não há eco de volta para o Sparkle.
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        lastCheckDate = controller.updater.lastUpdateCheckDate

        // `canCheckForUpdates` é KVO no Sparkle; sem observar, o botão ficaria clicável
        // durante uma checagem e abriria uma segunda janela por cima da primeira.
        // `assign(to:)` em vez de `sink`: a assinatura fica presa ao próprio `@Published`
        // (morre com o objeto, sem `Set<AnyCancellable>`) e não captura `self` num closure
        // não-isolado, o que geraria erro de concorrência no Swift 6.
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Checagem pedida pelo usuário (menu "•••" ou Configurações): sempre mostra resultado,
    /// inclusive "você já está na versão mais recente".
    func checkForUpdates() {
        controller.checkForUpdates(nil)
        lastCheckDate = updater.lastUpdateCheckDate
    }

    /// Relê o estado do Sparkle. Necessário porque o diálogo de primeira execução e o próprio
    /// fluxo de instalação mexem em `automaticallyChecksForUpdates` pelas nossas costas.
    func refresh() {
        let current = updater.automaticallyChecksForUpdates
        if automaticallyChecks != current { automaticallyChecks = current }
        lastCheckDate = updater.lastUpdateCheckDate
    }
}
