# Tomafoco — Arquitetura (SOLID + Clean Architecture)

**Versão:** 1.0
**Data:** 2026-07-22
**Referências:** `especificacao.md` (requisitos), `tarefas.md` (backlog)

---

## 1. Princípios norteadores

A arquitetura segue **Clean Architecture** (dependências apontando sempre para dentro, em direção ao domínio) com os princípios **SOLID** aplicados explicitamente em cada fronteira. A regra de ouro:

> **Domain e Application não importam AppKit, SwiftUI, Foundation-de-sistema (Process, NSWorkspace) nem nada do macOS. Todo efeito colateral vive atrás de um protocolo.**

Isso atende diretamente o RNF-05 (testabilidade): a máquina de estados do Pomodoro e os casos de uso rodam em testes unitários puros, com relógio, bloqueadores e persistência falsos.

---

## 2. Camadas

```
┌──────────────────────────────────────────────────────────────┐
│  Presentation (SwiftUI)                                       │
│  Views, ViewModels (@Observable), MenuBar, DesignSystem       │
└───────────────▲──────────────────────────────────────────────┘
                │ depende de
┌───────────────┴──────────────────────────────────────────────┐
│  Application (casos de uso)                                   │
│  StartFocusSession, CompleteSession, CancelSession,           │
│  RecoverFromCrash, ManageBlockLists, TickSession              │
└───────────────▲──────────────────────────────────────────────┘
                │ depende de
┌───────────────┴──────────────────────────────────────────────┐
│  Domain (núcleo puro)                                         │
│  PomodoroSession, SessionPhase, BlockList, BlockedApp,        │
│  BlockedDomain, PomodoroConfiguration, DomainError            │
│  + Ports (protocolos): AppBlocking, WebsiteBlocking,          │
│    SessionClock, SessionRepository, SettingsRepository,       │
│    UserNotifying, PrivilegeEscalating                         │
└───────────────▲──────────────────────────────────────────────┘
                │ implementada por (inversão de dependência)
┌───────────────┴──────────────────────────────────────────────┐
│  Infrastructure (adapters do macOS)                           │
│  WorkspaceAppBlocker (NSWorkspace),                           │
│  HostsFileWebsiteBlocker (/etc/hosts),                        │
│  AppleScriptPrivilegeRunner (osascript admin) → v2: XPCHelper │
│  DispatchSessionClock (Timer), UserDefaultsSettingsStore,     │
│  FileSessionSnapshotStore, UNNotificationAdapter              │
└──────────────────────────────────────────────────────────────┘
```

Setas de dependência: **Presentation → Application → Domain ← Infrastructure**. A Infrastructure conhece o Domain (implementa seus ports); o Domain não conhece ninguém. A composição acontece em um único ponto (**Composition Root**, no `@main`).

---

## 3. Domain — núcleo puro

### 3.1 Entidades e value objects

```swift
// Domain/Model/SessionPhase.swift
enum SessionPhase: Equatable, Codable {
    case idle
    case focus
    case shortBreak
    case longBreak
}

// Domain/Model/PomodoroSession.swift
struct PomodoroSession: Equatable, Codable {
    let id: UUID
    let phase: SessionPhase
    let startedAt: Date
    let endsAt: Date          // horário absoluto — sobrevive a crash (RF-01.5)
    let cycleNumber: Int

    var remaining: (now: Date) -> TimeInterval { { max(0, endsAt.timeIntervalSince($0)) } }
    func isExpired(now: Date) -> Bool { now >= endsAt }
}

// Domain/Model/BlockedDomain.swift — value object com validação (Clean Code: fail fast)
struct BlockedDomain: Equatable, Codable, Hashable {
    let value: String   // sempre normalizado: lowercase, sem esquema, sem caminho

    init(raw: String) throws {
        let normalized = Self.normalize(raw)
        guard Self.isValid(normalized) else { throw DomainError.invalidDomain(raw) }
        self.value = normalized
    }
}

// Domain/Model/BlockedApp.swift
struct BlockedApp: Equatable, Codable, Hashable {
    let bundleID: String
    let displayName: String
    var isEnabled: Bool
}

// Domain/Model/BlockList.swift — agregado
struct BlockList: Equatable, Codable {
    var domains: [BlockedDomain]
    var apps: [BlockedApp]
    var activeDomains: [BlockedDomain] { domains }          // extensível p/ enable/disable
    var activeAppBundleIDs: Set<String> { Set(apps.filter(\.isEnabled).map(\.bundleID)) }
}

// Domain/Model/PomodoroConfiguration.swift
struct PomodoroConfiguration: Equatable, Codable {
    var focusDuration: TimeInterval = 25 * 60
    var shortBreakDuration: TimeInterval = 5 * 60
    var longBreakDuration: TimeInterval = 15 * 60
    var cyclesBeforeLongBreak: Int = 4
    var autoStartNextFocus: Bool = false
}
```

### 3.2 Ports (protocolos) — o coração do DIP

```swift
// Domain/Ports/AppBlocking.swift
protocol AppBlocking: AnyObject {
    func activate(blockedBundleIDs: Set<String>)
    func deactivate()
}

// Domain/Ports/WebsiteBlocking.swift
protocol WebsiteBlocking: AnyObject {
    func activate(domains: [BlockedDomain]) async throws
    func deactivate() async throws
    var isActive: Bool { get async }
}

// Domain/Ports/SessionClock.swift — nunca use Date()/Timer direto no domínio
protocol SessionClock: AnyObject {
    var now: Date { get }
    func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void) -> ClockSubscription
}
protocol ClockSubscription { func cancel() }

// Domain/Ports/SessionRepository.swift — failsafe (RF-02.5 / UC-04)
protocol SessionRepository: AnyObject {
    func saveActive(_ session: PomodoroSession) throws
    func loadActive() throws -> PomodoroSession?
    func clearActive() throws
    func appendToHistory(_ record: SessionRecord) throws
}

// Domain/Ports/SettingsRepository.swift
protocol SettingsRepository: AnyObject {
    func loadConfiguration() -> PomodoroConfiguration
    func save(_ configuration: PomodoroConfiguration)
    func loadBlockList() -> BlockList
    func save(_ blockList: BlockList)
}

// Domain/Ports/UserNotifying.swift
protocol UserNotifying: AnyObject {
    func notify(_ event: NotificationEvent)   // .focusEnded, .breakEnded, .appBlocked(name:)
}

// Domain/Ports/PrivilegeEscalating.swift — usado pelo adapter de hosts, não pelo domínio;
// definido aqui para permitir trocar osascript → XPC helper (OCP) sem tocar em mais nada
protocol PrivilegeEscalating {
    func runPrivileged(command: String) async throws
}
```

**ISP em ação:** note que não existe um "SystemService" gordo. Cada consumidor enxerga só o que usa: o caso de uso de iniciar sessão recebe `AppBlocking` + `WebsiteBlocking`; a view de configurações recebe só `SettingsRepository`.

---

## 4. Application — casos de uso

Um caso de uso = uma classe pequena com um único método público (`SRP` + Clean Code: funções fazem uma coisa). Nomes de caso de uso são verbos do UC correspondente na especificação.

```swift
// Application/UseCases/StartFocusSessionUseCase.swift  (UC-01)
final class StartFocusSessionUseCase {
    private let clock: SessionClock
    private let appBlocker: AppBlocking
    private let websiteBlocker: WebsiteBlocking
    private let sessions: SessionRepository
    private let settings: SettingsRepository

    init(clock: SessionClock, appBlocker: AppBlocking, websiteBlocker: WebsiteBlocking,
         sessions: SessionRepository, settings: SettingsRepository) { /* ... */ }

    struct Outcome { let session: PomodoroSession; let websiteBlockFailed: Bool }

    func execute(reason: String?, cycleNumber: Int) async -> Outcome {
        let config = settings.loadConfiguration()
        let blockList = settings.loadBlockList()
        let session = PomodoroSession(
            id: UUID(), phase: .focus,
            startedAt: clock.now,
            endsAt: clock.now.addingTimeInterval(config.focusDuration),
            reason: reason, cycleNumber: cycleNumber
        )

        appBlocker.activate(blockedBundleIDs: blockList.activeAppBundleIDs)

        var websiteBlockFailed = false
        do { try await websiteBlocker.activate(domains: blockList.activeDomains) }
        catch { websiteBlockFailed = true }     // UC-01 fluxo alternativo 4a — decisão sobe p/ UI

        try? sessions.saveActive(session)        // failsafe persistido ANTES do timer rodar
        return Outcome(session: session, websiteBlockFailed: websiteBlockFailed)
    }
}
```

Demais casos de uso, todos no mesmo formato (dependências por protocolo, um `execute`):

| Caso de uso | UC | Responsabilidade única |
|---|---|---|
| `StartFocusSessionUseCase` | UC-01 | Criar sessão, ativar bloqueios, persistir failsafe |
| `CompleteSessionUseCase` | UC-02 | Desativar bloqueios, gravar histórico, decidir próximo phase |
| `CancelSessionUseCase` | UC-03 | Desativar bloqueios, gravar cancelamento |
| `RecoverFromCrashUseCase` | UC-04 | Ler sessão ativa persistida e decidir: restaurar hosts ou oferecer retomada |
| `ManageBlockListUseCase` | UC-05 | Validar/normalizar domínio, CRUD das listas |
| `AdvancePhaseUseCase` | RF-01.3/4 | Transições foco→break→foco e contagem de ciclos |

**A máquina de estados** (`SessionStateMachine`, em Application) é pura: recebe `(estadoAtual, evento, config, now)` e devolve `(novoEstado, efeitos)`. Os efeitos (`.activateBlocking`, `.deactivateBlocking`, `.notify(...)`, `.persist(...)`) são interpretados por um `SessionCoordinator` — isso torna as transições 100% testáveis por tabela de casos.

---

## 5. Infrastructure — adapters do macOS

Cada adapter implementa exatamente um port. Nenhum adapter conhece outro adapter (comunicação só via Domain/Application).

| Adapter | Port | Tecnologia | Observações |
|---|---|---|---|
| `WorkspaceAppBlocker` | `AppBlocking` | `NSWorkspace` + `didLaunchApplicationNotification` | `terminate()` padrão; `forceTerminate()` opt-in (RF-03.2) |
| `HostsFileWebsiteBlocker` | `WebsiteBlocking` | Bloco delimitado em `/etc/hosts` + `dscacheutil -flushcache` | Idempotente (RNF-01); recebe `PrivilegeEscalating` injetado |
| `AppleScriptPrivilegeRunner` | `PrivilegeEscalating` | `NSAppleScript` `with administrator privileges` | MVP. **v2:** `XPCHelperPrivilegeRunner` (SMAppService.daemon) — troca por injeção, zero mudança nas outras camadas (OCP/LSP) |
| `DispatchSessionClock` | `SessionClock` | `Timer`/`DispatchSourceTimer` | Em testes: `FakeClock` com avanço manual |
| `FileSessionSnapshotStore` | `SessionRepository` | JSON em `Application Support` | Escrita atômica (`.atomic`) |
| `UserDefaultsSettingsStore` | `SettingsRepository` | `UserDefaults` + `Codable` | Migração p/ SwiftData se histórico crescer |
| `UNNotificationAdapter` | `UserNotifying` | `UNUserNotificationCenter` | Degradação graciosa se permissão negada (RF-08.2) |

Detalhe crítico do `HostsFileWebsiteBlocker` (RNF-01):

```
activate():
  1. lê /etc/hosts
  2. se bloco "# Tomafoco-START" já existe → remove antes de reescrever (idempotência)
  3. monta novoConteúdo = original + bloco delimitado
  4. runPrivileged("cp /etc/hosts /etc/hosts.tomafoco.bak && tee /etc/hosts <<< novoConteúdo")
  5. flush DNS
deactivate():
  1. lê /etc/hosts
  2. se não há bloco → no-op (idempotência)
  3. remove SOMENTE as linhas entre os marcadores
  4. escrita privilegiada + flush DNS
```

---

## 6. Presentation — SwiftUI

- **ViewModels** (`@Observable`, macOS 14+ / `ObservableObject` no 13) recebem casos de uso por injeção; nunca tocam em ports de infraestrutura diretamente.
- `TimerViewModel`, `SettingsViewModel`, `BlockListViewModel`, `MenuBarViewModel` — um por tela (SRP na UI).
- `MenuBarExtra` (SwiftUI) para o item da barra de menus (RF-04); janela principal com `WindowGroup`.
- Formatação de tempo, strings localizáveis (pt-BR primeiro, RNF-08) e acessibilidade (RNF-09) resolvidas nesta camada — nunca no domínio.

---

## 7. Composition Root

Único lugar onde tudo se conecta (e único lugar com `import AppKit` + construtores concretos):

```swift
@main
struct TomafocoApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        MenuBarExtra { MenuBarView(viewModel: container.menuBarViewModel) } label: { /* timer */ }
        WindowGroup { MainView(viewModel: container.timerViewModel) }
        Settings { SettingsView(viewModel: container.settingsViewModel) }
    }
}

enum AppContainer {
    static func live() -> Container {
        let privilege = AppleScriptPrivilegeRunner()
        let websiteBlocker = HostsFileWebsiteBlocker(privilege: privilege)
        let appBlocker = WorkspaceAppBlocker()
        let clock = DispatchSessionClock()
        let sessions = FileSessionSnapshotStore()
        let settings = UserDefaultsSettingsStore()
        // ... monta casos de uso e view models
    }
    static func test() -> Container { /* fakes para testes de UI/preview */ }
}
```

---

## 8. Mapeamento SOLID (resumo auditável)

| Princípio | Onde está aplicado |
|---|---|
| **S — Single Responsibility** | Um caso de uso por operação; um adapter por tecnologia; um ViewModel por tela; `SessionStateMachine` só transiciona estados — quem executa efeitos é o `SessionCoordinator`. |
| **O — Open/Closed** | Trocar `AppleScriptPrivilegeRunner` → `XPCHelperPrivilegeRunner` (v2) ou `HostsFileWebsiteBlocker` → `NetworkExtensionBlocker` (v3) não altera Domain/Application/Presentation — só o Composition Root. |
| **L — Liskov Substitution** | Todos os fakes de teste (`FakeClock`, `InMemorySessionRepository`, `SpyAppBlocker`) são substituíveis pelos adapters reais sem quebrar contratos; contratos documentados nos ports (pré/pós-condições de idempotência). |
| **I — Interface Segregation** | Ports pequenos e específicos (`AppBlocking` ≠ `WebsiteBlocking` ≠ `PrivilegeEscalating`); nenhum consumidor depende de método que não usa. |
| **D — Dependency Inversion** | Application depende de abstrações do Domain; Infrastructure implementa essas abstrações; injeção 100% no Composition Root — nenhum `singleton` global, nenhum `.shared` fora dos adapters. |

**Clean Code (convenções do projeto):** funções curtas com um nível de abstração; nomes revelam intenção (`isExpired(now:)`, não `check()`); sem números mágicos (durações vêm de `PomodoroConfiguration`); erros são tipos (`DomainError`) e nunca `fatalError` em fluxo de produção; comentários apenas para "porquês" (ex.: por que a escrita do hosts é idempotente); testes nomeados como comportamento (`test_cancel_desativaBloqueioEVoltaParaIdle`).

---

## 9. Estratégia de testes (RNF-05)

| Camada | Tipo | Ferramenta | Meta |
|---|---|---|---|
| Domain | Unit puro (value objects, validações, `PomodoroSession`) | Swift Testing / XCTest | ~100% |
| Application | Unit com fakes (tabela de transições da state machine, cada use case) | Swift Testing + fakes in-memory | ≥ 80% |
| Infrastructure | Integração isolada: `HostsFileWebsiteBlocker` testado contra **arquivo temporário** (path injetado — nunca o `/etc/hosts` real em CI) | XCTest | Cenários críticos de RNF-01 |
| Presentation | Snapshot/preview + smoke tests de ViewModel | XCTest | Fluxos principais |
| E2E manual | Roteiro de QA (UC-01..UC-05 + failsafe com kill -9) | Checklist em `tarefas.md` | Antes de cada release |

Ponto-chave: `HostsFileWebsiteBlocker` recebe o **caminho do arquivo hosts por injeção** (default `/etc/hosts`), permitindo testar toda a lógica de parsing/idempotência contra um arquivo temporário sem privilégios.

---

## 10. Estrutura de pastas (Xcode / SPM)

O núcleo vai em pacotes SPM locais para reforçar as fronteiras em tempo de compilação (Domain não consegue importar AppKit nem por acidente):

```
Tomafoco/
├── Tomafoco.xcodeproj
├── App/                            # target macOS (Composition Root + Presentation)
│   ├── TomafocoApp.swift
│   ├── AppContainer.swift
│   └── UI/
│       ├── Timer/    (MainView, TimerViewModel)
│       ├── MenuBar/  (MenuBarView, MenuBarViewModel)
│       ├── Settings/ (SettingsView, BlockListViews, ViewModels)
│       └── DesignSystem/
├── Packages/
│   ├── TomafocoDomain/              # sem dependências
│   │   └── Sources/ (Model/, Ports/, Errors/)
│   ├── TomafocoApplication/         # depende só de TomafocoDomain
│   │   └── Sources/ (UseCases/, StateMachine/, Coordinator/)
│   └── TomafocoInfrastructure/      # depende de TomafocoDomain (+ AppKit, UserNotifications)
│       └── Sources/ (Blocking/, Privilege/, Persistence/, Notifications/, Clock/)
├── Tests/  (espelha os pacotes + fakes compartilhados em TomafocoTestSupport)
└── docs/   (este documento, especificacao.md, tarefas.md)
```

---

## 11. Decisões de arquitetura (ADR resumido)

| # | Decisão | Alternativa rejeitada | Motivo |
|---|---|---|---|
| ADR-1 | Swift/SwiftUI nativo | .NET MAUI + shim, Flutter, Electron | Bloqueio exige APIs nativas; interop adicionaria complexidade sem benefício no macOS-only |
| ADR-2 | Distribuição fora da App Store | Mac App Store | Sandbox inviabiliza edição de hosts e término de apps |
| ADR-3 | `/etc/hosts` no MVP | NetworkExtension Content Filter | NE exige entitlement aprovado pela Apple + system extension; custo desproporcional para v1 |
| ADR-4 | `osascript` admin no MVP | Privileged helper (SMAppService) | Helper pede setup de assinatura complexo; o port `PrivilegeEscalating` garante a troca limpa na v2 |
| ADR-5 | Pacotes SPM por camada | Grupos de pastas num único target | Fronteiras verificadas pelo compilador, não por disciplina |
| ADR-6 | Estado com horário absoluto (`endsAt`) | Contador decremental em memória | Sobrevive a crash/sleep/reboot (RF-01.5, RNF-02) |
| ADR-9 | Atualização automática com Sparkle 2 | Update caseiro (checar JSON + baixar DMG), pedir download manual no site | Fora da App Store não há atualização do sistema (ADR-2). Sparkle é o padrão de fato do macOS: já resolve assinatura EdDSA do feed, verificação do Developer ID do pacote baixado, instalação com reinício e retomada de download. Um updater caseiro teria que reimplementar isso — e um erro na verificação vira execução de código arbitrário na máquina do usuário |

### ADR-9 — detalhes

- **Feed:** `https://tomafoco.dds.tec.br/downloads/appcast.xml` (`SUFeedURL` no `project.yml`).
- **Confiança:** o appcast é assinado com chave **EdDSA**; a pública vai no `SUPublicEDKey`, a
  privada fica no **chaveiro** do mantenedor. Servidor comprometido, DNS envenenado ou proxy
  hostil não bastam para entregar um update forjado. Além disso o Sparkle confere que o app
  baixado tem o mesmo Developer ID do app instalado.
- **Sem instalação silenciosa:** `SUAutomaticallyUpdate: false`. Checa 1×/dia em segundo plano e
  pergunta. Num app de foco, trocar a versão sozinho pode derrubar uma sessão em andamento.
- **Onde mora no código:** `App/UI/Updates/UpdaterController.swift` — fachada `@MainActor` sobre
  o `SPUStandardUpdaterController`. Fica no `App/`, não na Infrastructure, porque o Sparkle traz
  a própria UI; não há port no Domain porque não há regra de domínio envolvida.
- **Fonte da verdade do "checar automaticamente" é o Sparkle** (`UserDefaults` /
  `SUEnableAutomaticChecks`), não `PomodoroConfiguration`: quem faz a pergunta de primeira
  execução é o próprio Sparkle, então uma cópia nossa divergiria da resposta do usuário.
- **Assinatura de código:** com o Sparkle embutido, o app passa a ter bundles executáveis
  aninhados (`Sparkle.framework`, `Updater.app`, `Autoupdate`, XPC services). Cada um precisa
  de assinatura própria, **de dentro para fora** — `scripts/release.sh` faz isso com
  `find -depth` antes de assinar o `.app`. Sem isso a notarização rejeita.
