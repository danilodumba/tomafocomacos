# FocusPomodoro — App de Pomodoro com Bloqueio de Sites e Apps para macOS

Documento de arquitetura e plano de implementação, baseado nas decisões:

- **Stack:** Swift/SwiftUI nativo
- **Distribuição:** fora da Mac App Store (sideload, assinado e notarizado)
- **Bloqueio de URLs:** edição do `/etc/hosts` (MVP)
- **Bloqueio de apps:** encerrar e impedir reabertura durante o foco

---

## 1. Visão geral

O app é um cronômetro Pomodoro (menu bar + janela principal) que, ao entrar em modo **Foco**, aplica duas restrições no macOS:

1. Redireciona domínios de uma lista de bloqueio para `127.0.0.1` (site inacessível).
2. Encerra imediatamente qualquer app da lista de bloqueio que esteja aberto ou seja aberto durante a sessão.

Ao final da sessão de foco (ou de um "break"), as restrições são revertidas automaticamente.

Ficando fora da App Store, você evita o sandbox obrigatório — é o que torna viável editar `/etc/hosts` e encerrar outros processos sem entitlements especiais da Apple.

---

## 2. Arquitetura geral

```
┌─────────────────────────────────────────────────────────┐
│                     FocusPomodoro.app                   │
│                                                           │
│  ┌───────────────┐   ┌────────────────────┐             │
│  │  SwiftUI UI    │   │  MenuBar (NSStatus │             │
│  │  (janela       │◄─►│  Item) - controle  │             │
│  │  principal)    │   │  rápido            │             │
│  └───────┬────────┘   └─────────┬──────────┘             │
│          │                      │                        │
│          ▼                      ▼                        │
│  ┌─────────────────────────────────────────┐             │
│  │        FocusSessionManager (core)        │             │
│  │  - Máquina de estados do Pomodoro        │             │
│  │  - Orquestra bloqueio/desbloqueio        │             │
│  └───────┬───────────────────────┬─────────┘             │
│          ▼                       ▼                       │
│  ┌───────────────────┐  ┌────────────────────┐           │
│  │  AppBlocker        │  │  HostsBlocker      │           │
│  │  (NSWorkspace)      │  │  (edita /etc/hosts)│           │
│  └───────────────────┘  └─────────┬──────────┘           │
│                                     │ shell privilegiado  │
│                                     ▼                     │
│                          ┌────────────────────┐           │
│                          │  osascript admin    │           │
│                          │  privileges (MVP)   │           │
│                          │  ou Privileged      │           │
│                          │  Helper (v2)        │           │
│                          └────────────────────┘           │
│                                                           │
│  ┌────────────────────────────────────────────┐          │
│  │  PersistenceStore (UserDefaults/SwiftData)   │          │
│  │  - Listas de bloqueio, configs, histórico    │          │
│  └────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────┘
```

---

## 3. Componentes principais

### 3.1 `FocusSessionManager`

Máquina de estados central. Estados: `idle`, `focus`, `shortBreak`, `longBreak`, `paused`.

```swift
enum SessionState: Equatable {
    case idle
    case focus(remaining: TimeInterval)
    case shortBreak(remaining: TimeInterval)
    case longBreak(remaining: TimeInterval)
    case paused(previous: SessionState)
}

@MainActor
final class FocusSessionManager: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var completedFocusCycles = 0

    private var timer: Timer?
    private let appBlocker: AppBlocker
    private let hostsBlocker: HostsBlocker
    private let settings: PomodoroSettings

    init(appBlocker: AppBlocker, hostsBlocker: HostsBlocker, settings: PomodoroSettings) {
        self.appBlocker = appBlocker
        self.hostsBlocker = hostsBlocker
        self.settings = settings
    }

    func startFocus() {
        state = .focus(remaining: settings.focusDuration)
        enterBlockedMode()
        startTicking()
    }

    private func enterBlockedMode() {
        appBlocker.activate(blockedBundleIDs: settings.blockedApps)
        Task { try? await hostsBlocker.activate(blockedDomains: settings.blockedDomains) }
    }

    private func exitBlockedMode() {
        appBlocker.deactivate()
        Task { try? await hostsBlocker.deactivate() }
    }

    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        switch state {
        case .focus(let remaining) where remaining > 1:
            state = .focus(remaining: remaining - 1)
        case .focus:
            completedFocusCycles += 1
            exitBlockedMode()
            state = isLongBreakDue ? .longBreak(remaining: settings.longBreakDuration)
                                   : .shortBreak(remaining: settings.shortBreakDuration)
        // ... casos de break omitidos por brevidade
        default: break
        }
    }

    private var isLongBreakDue: Bool {
        completedFocusCycles % settings.cyclesBeforeLongBreak == 0
    }
}
```

Pontos importantes:

- **Persistir o horário de término** (`Date`) da sessão em disco a cada tick (ou pelo menos ao iniciar/pausar), não só o `remaining` em memória. Assim, se o app crashar ou o Mac reiniciar durante o foco, ao reabrir o app você recalcula `remaining = endDate.timeIntervalSinceNow` e decide se reaplica o bloqueio ou libera.
- Trate o caso "sessão deveria ter terminado enquanto o app estava fechado" — sempre restaure o `/etc/hosts` original nesse cenário (ver seção 3.3, "failsafe").

### 3.2 `AppBlocker` — bloqueio de aplicativos

Usa `NSWorkspace` para: (a) encerrar apps já rodando da lista de bloqueio, (b) observar novos lançamentos e encerrá-los imediatamente.

```swift
final class AppBlocker {
    private var observer: NSObjectProtocol?
    private var blockedBundleIDs: Set<String> = []

    func activate(blockedBundleIDs: Set<String>) {
        self.blockedBundleIDs = blockedBundleIDs

        // 1. Encerra instâncias já abertas
        for app in NSWorkspace.shared.runningApplications {
            if let bundleID = app.bundleIdentifier, blockedBundleIDs.contains(bundleID) {
                app.terminate()
            }
        }

        // 2. Observa novos lançamentos durante a sessão
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  self.blockedBundleIDs.contains(bundleID) else { return }
            app.terminate()
            self.notifyUserAppBlocked(bundleID: bundleID)
        }
    }

    func deactivate() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        blockedBundleIDs = []
    }

    private func notifyUserAppBlocked(bundleID: String) {
        // UNUserNotificationCenter: "App bloqueado durante o foco"
    }
}
```

Observações:

- `terminate()` é um "quit" normal (o app pode pedir para salvar arquivos). Para forçar sem chance de cancelamento, existe `forceTerminate()` — use com cautela, pois pode causar perda de dados em apps de terceiros.
- Isso **não exige permissão de Accessibility** — `NSWorkspace` + `terminate()` funcionam sem entitlements especiais para apps de terceiros regulares. Você só precisaria de Accessibility se quisesse interceptar cliques/teclado, o que não é o caso aqui.
- Usuário pode tentar burlar renomeando o app ou usando outro bundle ID — é uma limitação aceitável para uma ferramenta de autodisciplina (não é um MDM corporativo).

### 3.3 `HostsBlocker` — bloqueio de sites via `/etc/hosts`

Estratégia:

1. Ao ativar: backup do `/etc/hosts` atual → escreve uma versão com as entradas bloqueadas anexadas (marcadas com um delimitador único, ex. `# FocusPomodoro-START` / `# FocusPomodoro-END`) → *flush* do cache de DNS.
2. Ao desativar: remove apenas o bloco delimitado, restaurando o hosts original.
3. **Failsafe de crash:** guarda um flag em `UserDefaults`/arquivo indicando "bloqueio ativo desde X, deveria terminar em Y". No próximo `applicationDidFinishLaunching`, se o horário já passou, remove o bloco do hosts mesmo que a sessão "oficialmente" nunca tenha sido encerrada pela UI.

Editar `/etc/hosts` exige privilégio de root. Duas abordagens:

**MVP (mais simples, recomendado para começar):**

```swift
import Foundation

enum HostsBlockerError: Error { case scriptFailed(String) }

final class HostsBlocker {
    private let markerStart = "# FocusPomodoro-START"
    private let markerEnd = "# FocusPomodoro-END"
    private let hostsPath = "/etc/hosts"

    func activate(blockedDomains: [String]) async throws {
        let entries = blockedDomains
            .flatMap { ["127.0.0.1 \($0)", "127.0.0.1 www.\($0)"] }
            .joined(separator: "\n")
        let block = "\(markerStart)\n\(entries)\n\(markerEnd)\n"

        // Anexa o bloco ao final do hosts, via osascript pedindo senha de admin
        let script = """
        do shell script "printf '%s' \(escapedForAppleScript(block)) >> \(hostsPath)" with administrator privileges
        """
        try runAppleScript(script)
        flushDNSCache()
    }

    func deactivate() async throws {
        // Lê o hosts, remove o bloco delimitado, escreve de volta com privilégio admin
        let script = """
        do shell script "sed -i '' '/\(markerStart)/,/\(markerEnd)/d' \(hostsPath)" with administrator privileges
        """
        try runAppleScript(script)
        flushDNSCache()
    }

    private func flushDNSCache() {
        // Idealmente também via admin privileges; em muitos casos dscacheutil não exige sudo
        let task = Process()
        task.launchPath = "/usr/bin/dscacheutil"
        task.arguments = ["-flushcache"]
        try? task.run()
    }

    private func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&error)
        if let error {
            throw HostsBlockerError.scriptFailed("\(error)")
        }
    }

    private func escapedForAppleScript(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
```

Prós/contras do MVP:

- ✅ Simples, sem precisar assinar/instalar um daemon privilegiado separado.
- ⚠️ O macOS vai pedir a senha do usuário (prompt nativo de admin) toda vez que uma sessão de foco começa e termina — aceitável para uso pessoal, mas repetitivo.
- ⚠️ Só bloqueia por domínio (não por caminho de URL específico), e é burlável por quem editar o hosts manualmente ou usar um DNS/VPN customizado — suficiente para autodisciplina, não para controle parental robusto.

**V2 (mais elegante, opcional depois):** um *privileged helper* instalado uma única vez via `SMAppService.daemon` (macOS 13+, substitui o antigo `SMJobBless`), comunicando com o app principal por XPC. Você pede a senha **uma vez** na instalação do helper, e depois ele pode editar o hosts sem novos prompts. É bem mais trabalho de setup (assinatura de código, `launchd.plist`, entitlements do helper), então recomendo deixar para uma segunda iteração depois que o MVP estiver validado.

### 3.4 Menu bar (`NSStatusItem`)

Para controle rápido sem precisar abrir a janela principal — iniciar/pausar foco, ver tempo restante, acessar configurações. Padrão comum: `NSStatusItem` com um `NSMenu` ou um `NSPopover` contendo uma view SwiftUI.

### 3.5 Persistência

- `UserDefaults` (ou `SwiftData`/`Core Data` se quiser histórico de sessões) para: duração do foco/break, lista de apps bloqueados (bundle IDs), lista de domínios bloqueados, ciclos até o "long break".
- Para descobrir bundle IDs de apps instalados, liste `/Applications` e leia o `Info.plist` de cada `.app`, ou deixe o usuário arrastar o app para a lista de bloqueio e capture via `NSWorkspace.shared.urlForApplication`.

---

## 4. Permissões necessárias

| Recurso | Permissão do macOS |
|---|---|
| Encerrar outros apps (`terminate()`) | Nenhuma entitlement especial (fora da sandbox) |
| Editar `/etc/hosts` | Prompt de senha de admin via `osascript`/AppleScript (MVP) |
| Notificações locais | `UNUserNotificationCenter` — autorização padrão do usuário |
| Rodar fora da App Store | Developer ID + assinatura de código + **notarização** (Gatekeeper vai bloquear um app não notarizado) |

Não é necessário Accessibility nem Full Disk Access para o escopo descrito.

---

## 5. Modo "hardcore" (proposto aqui — NÃO ADOTADO)

> **Status (2026-08-03):** chegou a ser implementado e foi **removido** do produto. O Tomafoco é
> de autodisciplina, não de coerção: a trava atrapalhava interrupções legítimas e era contornável
> de qualquer forma. Seção mantida como registro do estudo original.

Ferramentas como Cold Turkey/Freedom têm sucesso porque dificultam desistir no meio da sessão. Sugestões incrementais:

- Desabilitar o botão "Cancelar sessão" nos primeiros N minutos, ou exigir confirmação dupla.
- Impedir que o próprio app seja encerrado durante o foco escondendo/desabilitando "Quit" no menu (não dá para impedir `Force Quit` do Activity Monitor sem privilégios de root — é uma limitação aceita).
- Modo "trava total": ao tentar sair, mostrar um lembrete do motivo da sessão (o usuário digitou ao iniciar) antes de permitir cancelar.

---

## 6. Estrutura de projeto sugerida (Xcode)

```
FocusPomodoro/
├── FocusPomodoroApp.swift          # @main, ciclo de vida do app
├── Core/
│   ├── FocusSessionManager.swift
│   ├── SessionState.swift
│   └── PomodoroSettings.swift
├── Blocking/
│   ├── AppBlocker.swift
│   ├── HostsBlocker.swift
│   └── HostsBackupStore.swift      # failsafe de crash
├── UI/
│   ├── MainWindowView.swift
│   ├── MenuBarView.swift
│   ├── BlockedAppsListView.swift
│   └── BlockedSitesListView.swift
├── Persistence/
│   └── SettingsStore.swift
└── Resources/
    └── Assets.xcassets
```

---

## 7. Roadmap de implementação

**Fase 1 — MVP funcional (uso pessoal)**
1. UI do Pomodoro (timer, iniciar/pausar/pular) + menu bar.
2. `AppBlocker` completo (encerrar + observar lançamentos).
3. `HostsBlocker` via `osascript` com privilégio admin.
4. Persistência de configurações e listas de bloqueio.
5. Failsafe de crash (restaurar hosts ao reabrir se sessão expirou).
6. Assinatura de código (Developer ID) + notarização para rodar sem avisos do Gatekeeper.

**Fase 2 — Robustez**
7. Privileged helper via `SMAppService` para eliminar prompts repetidos de senha.
8. Histórico de sessões (estatísticas de foco por dia/semana).
9. ~~Modo "hardcore" com confirmações.~~ (implementado e removido em 2026-08-03 — ver §5)
10. Sincronização de config via iCloud (se quiser usar em mais de um Mac).

**Fase 3 — Bloqueio avançado (opcional)**
11. Migrar de `/etc/hosts` para `NetworkExtension` (Content Filter) se precisar bloquear por URL/caminho específico e não só por domínio — requer entitlement especial da Apple (`com.apple.developer.networking.networkextension`) que precisa ser solicitado e aprovado.

---

## 8. Limitações conhecidas (para deixar claro desde já)

- `/etc/hosts` bloqueia por domínio, não por URL — não dá pra bloquear só `reddit.com/r/x` mantendo o resto do site liberado.
- Um usuário técnico (você mesmo, em um momento de fraqueza) consegue burlar editando o hosts manualmente, trocando de DNS, ou usando VPN — é uma ferramenta de fricção/autodisciplina, não uma trava de segurança real.
- Sem estar na App Store, a distribuição é manual: você precisa de uma conta Apple Developer (US$ 99/ano) para Developer ID + notarização, ou vai bater em avisos do Gatekeeper.

---

## 9. Próximos passos sugeridos

Posso, na sequência:
1. Gerar o projeto Xcode inicial completo (todos os arquivos `.swift` acima, prontos para abrir e compilar).
2. Detalhar o fluxo de assinatura/notarização passo a passo.
3. Escrever o `HostsBackupStore` (failsafe de crash) em detalhe.

É só avisar qual desses você quer que eu faça primeiro.
