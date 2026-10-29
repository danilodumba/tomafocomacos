# CLAUDE.md — Memória do projeto Tomafoco

App de Pomodoro para macOS que bloqueia sites e apps distrativos durante o foco.
Este arquivo registra o contexto e **onde o trabalho parou** para retomar em sessões futuras.

## Contexto do projeto

- **Local no disco:** `/Volumes/danilo_ssd/Projetos/tomafoco/APP` (pasta renomeada de `ds.focus` para `APP` em 2026-08-06, alinhando com `DOCS - Tomafoco/APP/` e `../site/`)
- **Documentação de produto/arquitetura:** controlada em `../DOCS - Tomafoco/APP/` (Obsidian vault), **não** mais em `docs/` deste repositório. Ver "Documentação" logo abaixo.
- **Plataforma/stack:** macOS 14+ (desde a FEAT-006, 2026-10-29 — SwiftData), Swift 5.9 / SwiftUI, universal binary
- **Distribuição:** FORA da Mac App Store (Developer ID, assinado + notarizado). Sandbox desligado.
- **Decisões-chave (ADRs em `../DOCS - Tomafoco/APP/arquitetura.md`):**
  - Bloqueio de sites: edição idempotente do `/etc/hosts` (MVP). NetworkExtension fica para v3.
  - Privilégio: `AppleScriptPrivilegeRunner` (prompt admin) no MVP; XPC helper (`SMAppService`) na v2 — trocável só no Composition Root.
  - Bloqueio de apps: `NSWorkspace` encerra + observa relançamentos.
  - Estado com término absoluto (`endsAt`) para sobreviver a crash/sleep/reboot.

## Documentação

Toda documentação de produto/arquitetura (especificação, arquitetura, backlog, release,
briefing pro site) é controlada em **`../DOCS - Tomafoco/APP/`** (vault Obsidian), não neste
repositório. O `docs/` local só guarda **assets operacionais** que o código/scripts consomem
diretamente: `docs/screenshots/` (fonte pro site) e `docs/release-notes/*.html` (lido pelo
`release.sh`/`generate_appcast`).

- Para editar especificação, arquitetura ou backlog → editar em `../DOCS - Tomafoco/APP/`.
- Este `CLAUDE.md` **fica no repositório** (é o log de sessão de trabalho, acoplado ao código) —
  só ele e o `README.md` (visão geral rápida) permanecem aqui.
- `../DOCS - Tomafoco/Índice.md` é o ponto de entrada do vault (link pra `APP/` e `Site/`).

## Arquitetura (Clean Architecture + SOLID, pacotes SPM por camada)

```
App/ (SwiftUI + Composition Root) → TomafocoApplication → TomafocoDomain ← TomafocoInfrastructure
```

- `TomafocoDomain` — núcleo puro, sem AppKit (modelo, ports, validações).
- `TomafocoApplication` — `SessionStateMachine` pura + `SessionCoordinator` + use cases.
- `TomafocoInfrastructure` — adapters macOS (hosts, NSWorkspace, AppleScript, clock, persistência, notificações). Adapters de AppKit sob `#if canImport(AppKit)`.
- `TomafocoTestSupport` — fakes/spies dos ports.
- `App/` — `AppContainer` (única raiz de injeção) + telas.

## Estado atual — ONDE PAROU (2026-07-22)

**Concluído: documentação + T-01/T-02 (scaffold completo com núcleo SOLID implementado e testado).**

Já existe e está no disco:
- ✅ Documentação em `docs/`: `especificacao.md`, `arquitetura.md`, `tarefas.md`, `pomodoro-focus-blocker-design.md`
- ✅ Domain completo: `PomodoroSession`, `BlockedDomain` (validação/normalização), `BlockList`, `PomodoroConfiguration`, ports, erros + testes
- ✅ Application: `SessionStateMachine` pura, `SessionCoordinator`, ~~`HardcoreCancelPolicy`~~ (removido em 2026-08-03), `RecoverFromCrashUseCase`, `ManageBlockListUseCase` + testes de tabela
- ✅ Infrastructure: `HostsFileEditor` (lógica idempotente RNF-01, testada), `HostsFileWebsiteBlocker`, `WorkspaceAppBlocker`, `AppleScriptPrivilegeRunner`, `DispatchSessionClock`, `FileSessionSnapshotStore`, `UserDefaultsSettingsStore`, `UNNotificationAdapter`
- ✅ App: `TomafocoApp`, `AppContainer`, `TimerViewModel`/`MainView`, `MenuBarView`, `SettingsView`/`SettingsViewModel`, `BlockListViewModel`
- ✅ Tooling: `project.yml` (XcodeGen), `App/Resources/Tomafoco.entitlements`, `.swiftlint.yml`, `Makefile`, `.gitignore`, `README.md`
- 52 arquivos Swift; chaves/parênteses balanceados.

**✅ Build/testes validados no Mac (2026-07-22, Swift 6.3.2):**
- `make test` → 51/51 testes verdes (Domain 19, Application 21, Infrastructure 11)
- `xcodegen generate` + `xcodebuild -scheme Tomafoco` → **BUILD SUCCEEDED**, zero warnings de código
- Correções aplicadas nessa validação:
  - `HardcoreCancelPolicyTests` (arquivo já removido): `Result<Void, DomainError>` não é `Equatable` → asserts trocados por helpers `assertSuccess`/`assertFailure`
  - `PomodoroSession`: passou a conformar `Identifiable` (exigido por `.sheet(item:)` em `MainView`)

**✅ T-20 concluído (2026-07-22)** — seleção de apps por bundle ID:
- Novo port `ApplicationPicking` + `ApplicationPickResult` (`Ports/ApplicationPicking.swift`) — Domain segue sem AppKit
- Adapter `NSOpenPanelApplicationPicker` (`Infrastructure/Picker/`): `NSOpenPanel` ancorado em `/Applications`, seleção múltipla; conversão URL→`BlockedApp` isolada no `static makeResult(from:)` (testada com bundles `.app` sintéticos em temp)
- `ManageBlockListUseCase.addApps(_:) -> AddAppsResult` — lote, não lança, deduplica dentro do lote e contra a lista, devolve `addedNames`/`duplicateNames`
- `BlockListViewModel.addAppsFromPicker()` (botão "Adicionar…") e `addApps(fromDroppedURLs:)` (`.dropDestination(for: URL.self)` na lista)
- `StubApplicationPicker` no TestSupport
- Suíte na época: 64 verdes (hoje **100**: Domain 19, Application 38, Infrastructure 43)
- ⚠️ Só falta validar à mão: abrir Preferências → aba Apps → "Adicionar…" e o arraste (o painel em si não é testável automatizado)

**✅ Rebrand Tomafoco + novo layout (2026-07-22):**
- Renomeação completa `DSFocus*`/`ds.focus` → `Tomafoco*`: módulos SPM, pastas, `TomafocoApp.swift`, entitlements, bundle ID `com.dsdumba.tomafoco`, marcador do `/etc/hosts` (`# Tomafoco-START/END`), pasta em Application Support, docs. ~~A pasta do projeto no disco continua `ds.focus`~~ — **renomeada pra `APP` em 2026-08-06** (ver "Contexto do projeto" no topo).
- Design system em `App/UI/DesignSystem/`:
  - `Brand.swift` — paleta DDS.TEC extraída dos SVGs oficiais (cyan `#17B9EB`, navy `#08143E`, cyan claro `#94DCF2`, cyan escuro `#0D6985`) + tokens adaptativos claro/escuro via `NSColor` dinâmico (`Color.adaptive`), então nenhuma View lê `colorScheme`.
  - `Components.swift` — `ProgressRing`, `PrimaryCircleButton`, `GhostControl`, `BrandCard`.
- `MainView` refeita: cabeçalho com fase + menu "•••", anel de progresso com tempo ao centro, rodapé RESET / play-pause / SKIP. Janela 340×480, `.hiddenTitleBar`. `MenuBarView` no mesmo idioma visual.
- **Novo evento `skipBreak` na máquina pura** (RF-04.2): pula intervalo (running ou pausado), grava `SessionRecord.Outcome.skipped` com `endedAt = now`; no-op durante foco/idle/awaiting. Fim de intervalo natural e pulado compartilham o helper `endBreak`. 8 testes novos.
- `TimerViewModel` ganhou `progress`, `phase`, `canSkip`, `skip()`.
- App icon gerado em `App/Resources/Assets.xcassets/AppIcon.appiconset` (squircle navy + símbolo DDS branco + anel cyan). Script de geração: `scratchpad/makeicon.swift` (não versionado — regerar se quiser ajustar). **Símbolo trocado em 2026-08-03 — ver abaixo.**
- Suíte na época: 72 verdes.

**✅ Helper privilegiado XPC (ADR-4 v2) — 2026-07-22:** acaba com o prompt de senha a cada bloqueio.
- `Helper/` (novo target `TomafocoHelper`, tipo `tool`): daemon root registrado via `SMAppService.daemon`. O protocolo XPC vive na Infrastructure e é compartilhado por app e helper via dependência de pacote.
- **Superfície XPC estreita de propósito:** aceita só uma lista de domínios (`applyBlock`/`removeBlock`), nunca comando shell. Revalida cada domínio com `BlockedDomain` e monta o bloco no próprio helper. `HelperListenerDelegate` recusa clientes que não satisfaçam o requisito de assinatura (bundle ID + Team + âncora Apple).
- `XPCWebsiteBlocker` (Infrastructure) implementa `WebsiteBlocking` e cai no `HostsFileWebsiteBlocker` (AppleScript) quando o helper não está instalado ou falha — usuário nunca fica sem bloqueio.
- UI de instalação: cartão na aba Sites (`HelperInstallerViewModel` + `SMAppServiceControl`), com estados notInstalled/awaitingApproval/installed/unsupported.
- **Team ID correto é `CJQ7T4KV7H`** (o `R47TBYQ2QK` do nome do certificado NÃO é o team). Usado em `project.yml` e no requisito de código do helper — se divergir, o helper recusa o app.
- ⚠️ Certificado Apple Development **vence em 2026-08-10**. E distribuir exige Developer ID + notarização (T-25) — com Apple Development só funciona local.
- `copyFiles` do XcodeGen é ignorado silenciosamente; o plist do LaunchDaemon é copiado por `postBuildScripts` (roda antes da assinatura).

**♻️ Helper movido para a Infrastructure + testado (2026-07-22):** `App/` não tem target de teste — foi por isso que o crash abaixo passou. Agora:
- `TomafocoInfrastructure/Privilege/`: `HostsHelperProtocol` (era `Shared/`, pasta extinta), `HostsHelperClient` (port) + `XPCHostsHelperClient` (transporte), `PrivilegedHelperInstaller` + `HelperServiceControlling` + `SMAppServiceControl`, `HelperReadiness`.
- `TomafocoInfrastructure/Blocking/XPCWebsiteBlocker.swift` — agora recebe o `client` por injeção, então testa sem XPC real.
- No `App/` sobrou só `HelperInstallerViewModel` (ObservableObject fino). Infrastructure ficou sem SwiftUI/Combine.
- Testes novos: `XPCWebsiteBlockerTests` (9), `PrivilegedHelperInstallerTests` (11), `HelperReadinessTests` (3). Infra: 20 → **43 testes**.
- Um teste é regressão explícita do crash: verifica que `isHelperReady` é chamado FORA da main thread.

**🔀 PIVÔ — bloqueio de sites agora é por automação do navegador (ADR-8, 2026-07-22). ✅ VALIDADO À MÃO pelo usuário: aba bloqueada vira `blocked.html`.** Substituiu o `/etc/hosts` como mecanismo principal. **Este é o estado atual do produto.**

Por que trocou (depuração longa, não repetir):
1. `dscacheutil -flushcache` **não** faz o `mDNSResponder` reler o `/etc/hosts` — só limpa cache.
2. `killall -HUP mDNSResponder` funciona com `sudo` no Terminal, mas **não** a partir de `do shell script` (daemon protegido pelo SIP; o PID nunca mudava).
3. O rótulo do launchd no macOS 26 é `com.apple.mDNSResponder.reloaded`, não `com.apple.mDNSResponder` — `kickstart` falhava com "service not found", escondido por um `|| true`.
4. Máquina do usuário tem **FortiClient VPN + Check Point** com DNS corporativo; hosts é frágil nesse cenário de qualquer forma.
5. Inspeção do **Cisdem AppCrypt** (que funciona nessa máquina): zero referências a hosts/pf/NEFilter; usa entitlement `apple-events` + `set URL of the_tab` — ou seja, pilota o navegador.

Como ficou:
- `TomafocoInfrastructure/Blocking/AppleScriptBrowserBlocker.swift` — implementa o mesmo port `WebsiteBlocking`; `DispatchSourceTimer` de 1s varre abas e redireciona as bloqueadas para `App/Resources/blocked.html`.
- `BrowserAutomation.swift` — `BrowserTarget` (Safari, Chrome, Edge, Brave, Opera, Vivaldi), ports `AppleScriptRunning`/`RunningApplicationsProviding` (+ impls reais), `BrowserScript` (geração/parse dos scripts).
- `TomafocoDomain/Model/URLBlockingPolicy.swift` — casamento puro de URL: só http(s), só por host, subdomínio casa, sufixo parecido NÃO (`naoglobo.com`).
- **Firefox não é suportado** — não expõe abas por AppleScript. Há teste garantindo que a lista não mente.
- **Nunca fala com navegador fechado** (`tell application` abriria o browser) — filtra por `NSWorkspace.runningApplications`.
- Entitlement `com.apple.security.automation.apple-events` + `NSAppleEventsUsageDescription`. Usuário autoriza cada navegador uma vez (TCC).
- **Daemon root não é mais embarcado**: target `TomafocoHelper` saiu do `project.yml`.

🧹 **Código do hosts/helper XPC REMOVIDO (2026-07-22, commit após o inicial).** Saíram: `Helper/` inteiro, `HostsFileEditor`, `HostsFileWebsiteBlocker`, `XPCWebsiteBlocker`, `AppleScriptPrivilegeRunner`, `HostsHelperProtocol/Client`, `PrivilegedHelperInstaller`, `HelperReadiness` e o port `PrivilegeEscalating`. `PrivilegeError` virou `AutomationError` (`permissionDenied(application:)` mapeia o erro -1743 do AppleScript, `executionFailed`). Está tudo no histórico do git se precisar voltar.

**🐛 Crash corrigido no mesmo dia:** `MainActor.assumeIsolated` dentro do closure `isHelperReady` derrubava o app (SIGTRAP) ao clicar "Iniciar foco" — `WebsiteBlocking.activate` é `nonisolated async` e roda no pool cooperativo. Trocado por `HelperReadiness` (snapshot com `NSLock`). **Regra: nunca usar `assumeIsolated` em código chamado pelos ports** — eles não têm garantia de main actor.

**🔔 Avanço manual de etapas + alerta sonoro (2026-07-22):**
- **Bug corrigido:** com "iniciar próximo foco automaticamente" desligado, o intervalo emendava sozinho ao fim do foco. O código seguia o RF-01.3 antigo (intervalo sempre automático), mas contrariava a expectativa do usuário. **A spec foi alterada**: o ajuste agora vale para as DUAS transições.
- `PomodoroConfiguration.autoStartNextFocus` → `autoAdvancePhases`. **A chave persistida continua `autoStartNextFocus`** via `CodingKeys`: o `UserDefaultsSettingsStore` cai no padrão quando a decodificação falha, então renomear a chave apagaria as configurações do usuário em silêncio.
- Estado `awaitingNextFocus(nextCycle:)` → `awaitingNext(phase:cycle:)`; evento `beginNextFocus` → `beginNextPhase`. Confirmar um intervalo não emite `activateBlocking`.
- **Invariante:** ao fim do foco o bloqueio cai SEMPRE, mesmo aguardando confirmação — ninguém pode ficar bloqueado esperando clicar.
- `PhaseAlertNotifier` (decorador de `UserNotifying`): som + ícone do Dock pulando no fim de cada etapa. É decorador para o som tocar mesmo se a permissão de notificação tiver sido negada. Só fim de etapa alerta — `appBlocked` dispara repetido e viraria ruído.
- `UNNotificationAdapter` ganhou delegate `ForegroundPresenter`: sem ele o macOS **esconde** a notificação com o app em primeiro plano, que é justamente o caso comum aqui.

**🖥️ Tela cheia de intervalo (2026-07-22):**
- `BreakOverlayPolicy` (Application, pura e testada — 10 testes): devolve uma **chave** por intervalo, não um `Bool`, para que dispensar a tela de um intervalo não esconda a do próximo. Mostra em intervalo rodando/pausado e enquanto aguarda confirmação de intervalo; nunca durante o foco.
- `App/UI/BreakOverlay/`: `BreakOverlayPresenter` (uma `NSWindow` **por monitor** — cobrir só o principal deixaria escapar para o outro) + `BreakOverlayView`.
- Nível `.floating`, não `.screenSaver`: ⌘Tab continua funcionando. O produto é de autodisciplina, não de controle parental (ver "o que o produto NÃO é" na especificação).
- Esc fecha; `OverlayWindow` sobrescreve `canBecomeKey` porque janela `borderless` não aceita foco de teclado por padrão.
- `AppContainer` retém o presenter — sem referência forte a assinatura Combine morre e a tela nunca aparece.

**🚫 Aviso na tela ao tentar abrir app bloqueado (2026-07-22):**
- `BlockedAppAlertThrottle` (Application, pura — 6 testes): represa **por app**, 5s. Sem ela, clicar 3× no ícone geraria 3 avisos, e apps que relançam sozinhos (Slack/Teams) inundariam a tela. A carência conta da última exibição — tentativas represadas não a renovam, senão um app em loop nunca mais avisaria.
- `App/UI/BlockedAppToast/`: `BlockedAppToastPresenter` (NSPanel `.statusBar`, `ignoresMouseEvents` — não rouba clique nem foco) + `BlockedAppToastView` (material translúcido).
- Aparece no topo-centro da tela **onde está o cursor** (multi-monitor: avisar na tela que o usuário não olha é inútil). Some em 3,5s; janela é reaproveitada em vez de empilhar.
- `BlockedAppToastNotifier` decora o notificador. Fica no App porque é apresentação — a Application só emite `NotificationEvent.appBlocked`. Reseta a represa em `.focusEnded`.

**🔍 Code review completo + 9 correções (2026-07-22):** revisão de todas as camadas; 1 bug e 8 riscos corrigidos, suíte verde (agora ~108 testes) e `xcodebuild` limpo.
- 🔴 **Menu bar congelada**: o label do `MenuBarExtra` lia `container.timerViewModel.menuBarLabel`, mas `AppContainer` nunca publica — o body do App não reavaliava e o countdown jamais aparecia. Fix: `MenuBarLabel` (View privada em `TomafocoApp.swift`) com `@ObservedObject`. **Regra: nested ObservableObject não propaga; todo binding de VM precisa de uma View que o observe diretamente.**
- `AppleScriptBrowserBlocker`: (a) só `AutomationError.permissionDenied` entra em `deniedBundleIDs` — erro transiente (navegador ocupado) volta a tentar no próximo tick; (b) timer criado dentro do lock (duas ativações concorrentes criavam 2 timers, 1 vazava); (c) `deniedBundleIDs` agora faz `formUnion` em vez de sobrescrever; (d) `pollInterval` padrão 1s → **2s** (NSAppleScript roda na main; 1s = jank contínuo); (e) locking centralizado em `withLock` — `NSLock.lock()` direto em função async gera warning (erro no Swift 6).
- `SessionStateMachine`: `% max(1, cyclesBeforeLongBreak)` — config decodificada com 0 crashava com módulo por zero.
- `WorkspaceAppBlocker.activate` chama `deactivate()` primeiro — reativar sobrescrevia o observer e vazava o anterior (terminate/aviso em dobro).
- `BreakOverlayPresenter`: `makeKeyAndOrderFront` na janela do monitor com o cursor — sem key window o Esc (`cancelOperation`) caía na janela principal e nunca fechava a tela. ⚠️ Validar Esc à mão.
- `SessionCoordinator`: falhas de persistência/desativação logadas via `os.Logger` (subsystem `com.dsdumba.tomafoco`) em vez de `try?` mudo.
- `FileSessionSnapshotStore.appendToHistory`: histórico corrompido vira `history.json.bak` (preservado para diagnóstico) em vez de ser apagado em silêncio. Ganhou `FileSessionSnapshotStoreTests` (não tinha nenhum).
- Riscos apontados e NÃO corrigidos (aceitos por ora): tick continua 1/s em `paused`/`awaitingNext`; skip de foco toca som de "Foco concluído"; throttle do toast chaveada por nome e não bundle ID; domínio IDN unicode não casa com host punycode do navegador; `TimerViewModel`/`SettingsViewModel` seguem sem testes (mover para pacote `TomafocoPresentation` é o fix estrutural).

**✅ Tarefas + importação do Lembretes + relatórios (RF-09/RF-10, 2026-07-22):** suíte 168 verdes (Domain 32, Application 98, Infra 38), `xcodebuild` limpo.
- **Decisões do usuário (não rediscutir):** importação vem do **Lembretes** (EventKit; Notas descartado), UI em **janela separada** ("Tarefas & Relatórios", `Window(id: "tasks")`), tempo contado é **de parede** (`endedAt − startedAt`, pausas incluídas — não há rastreio de pausa).
- Domain: `FocusTask` (nome evita colisão com `Swift.Task`; `reminderID` = chave de dedup), ports `TaskRepository` + `TaskImporting`, `taskID: UUID?` em `PomodoroSession`/`SessionRecord` (opcional → JSON antigo decodifica `nil`, vira "Sem tarefa" no relatório; testes em `TaskLinkCodingTests`). `SessionRepository` ganhou `loadHistory()`.
- Máquina: `startFocus(reason:taskID:)`; o `taskID` atravessa o ciclo inteiro (foco → registro → intervalo → `awaitingNext(phase:cycle:taskID:)` → próximo foco).
- Application: `ManageTasksUseCase` (CRUD + import com dedup por `reminderID`; concluída reimportada não ressuscita; `now` injetado SEM default — regra "sem Date() na Application") e `ReportBuilder` puro (horas por tarefa/dia, intervalos por dia, resumo com streak — streak usa histórico completo, ignora o filtro de período; sessão que cruza meia-noite conta no dia de início; tarefa apagada vira "Tarefa removida").
- Infra: `FileTaskStore` (`tasks.json` + `.bak` se corromper), `EventKitReminderImporter` (`requestFullAccessToReminders` no macOS 14+, fallback 13). `project.yml`: `NSReminders(FullAccess)UsageDescription`.
- App: seletor de tarefa no rodapé ocioso da `MainView`; `TasksView`/`ReportsView` (Swift Charts) na janela nova; menu "•••" abre via `openWindow`. `TasksViewModel.onTasksChanged` → `timerViewModel.reloadAvailableTasks()` (seleção morta é limpa).
- ⚠️ Validar à mão: prompt TCC do Lembretes, importar 2×(não duplica), foco com tarefa → `history.json` com `taskID`, janela de relatórios.
- **Versão visível + iniciar com o macOS (2026-07-22):** `AppInfo` (App/) lê `CFBundleShortVersionString`/`CFBundleVersion` → aparece no menu "•••" e no rodapé da aba Pomodoro. Port `LoginItemManaging` (Domain) + `SMAppServiceLoginItem` (Infra, `SMAppService.mainApp`); toggle em Configurações › Comportamento. Estado NÃO vai para `PomodoroConfiguration` — fonte da verdade é o sistema (usuário muda por fora em Itens de Início); `refreshLaunchAtLogin()` no `onAppear` e flag `isSyncingLoginItem` evita loop de didSet na reversão pós-falha.
- **Filtro de importação por LISTA do Lembretes (2026-07-22):** "Importar…" abre sheet com as listas (`fetchReminderLists`; multi-seleção; seleção lembrada em `UserDefaults` `reminderImportListIDs`, lista nova entra marcada; todas marcadas ≡ sem filtro). **Tags do Lembretes NÃO existem no EventKit** — não prometer esse filtro; lista é o único recorte da API. `fetchIncompleteReminders(fromLists:)` curto-circuita filtro que não casa com calendário nenhum (senão o EventKit devolveria TUDO). Título da tarefa corrente também aparece no anel do timer (`currentTaskTitle`, cache por sessão). Suíte: 176 casos.

**🔁 Trocar a tarefa com o foco pausado (RF-09.1, 2026-07-23):** usuário pode finalizar/mudar de tarefa no meio do foco. Só vale **pausado** (decisão de design: trocar durante o foco rodando seria mexer no que está sendo cronometrado sem parar).
- Domain: `PomodoroSession.with(taskID:)` — struct é toda `let`, reconstrói.
- Máquina pura: novo evento `SessionEvent.changeTask(taskID: UUID?)`. Só `reducePaused` age: reconstrói a sessão pausada com a nova tarefa, **preserva `remaining`/`endsAt`** (não mexe no tempo) e re-emite `.persistActive` quando a fase bloqueia (failsafe pós-crash reflete a nova tarefa). No-op em idle/running/awaiting. 5 testes novos em `SessionStateMachineTests` (Application 124, 0 falhas).
- `SessionCoordinator.changeTask(_:)` → dispatch.
- `TimerViewModel`: `currentSessionTaskID` (espelha `state.currentSession?.taskID`), `changeCurrentTask(_:)`; `pause()` chama `reloadAvailableTasks()` UMA vez ao pausar (pausado ainda dá render 1/s — não recarregar a cada tick).
- `MainView`: `taskPicker` virou função `(selection:accessibility:)`; segundo picker aparece quando `isPaused`, com `Binding` que despacha `changeCurrentTask` no set. `xcodebuild` limpo.
- ⚠️ Validar à mão: iniciar foco → pausar → trocar tarefa no picker → retomar → tarefa nova aparece no anel e vai pro `history.json`.

**↩️ Revertido o modo "só barra de menus" (2026-07-30):** o app voltou a ter **ícone no Dock** (`LSUIElement: false`) e o `MenuBarExtra` voltou a mostrar o **formulário compacto** `MenuBarView` (250pt) em vez de mostrar/esconder a janela principal de 340×480. Saíram: o `AppDelegate` com `setActivationPolicy(.accessory)` + `NSStatusItem` manual, e o `AppContainer.shared` (só existia para o delegate). `TomafocoApp` voltou a `WindowGroup` + `.task { recoverFromCrashIfNeeded() }` + `MenuBarExtra(.window)` com `MenuBarLabel` (a View que observa o VM direto — sem ela o countdown congela). Janelas separadas de **Tarefas** e **Relatórios** foram mantidas.

**💾 Ordenação das tarefas persistida (2026-07-30):** `TasksViewModel.sortOrder` grava/lê `UserDefaults` chave `tasksSortOrder` (`didSet` salva; `storedSortOrder(in:)` lê no init, `rawValue` desconhecido → `.createdAt`). O `defaults` já era injetado no VM e estava sem uso. **Busca/filtros (`searchText`, `tagFilter`, `priorityFilter`) NÃO são persistidos de propósito** — recorte é da sessão; ordenação é preferência.

**✏️ Edição completa da tarefa (RF-09.6, 2026-07-30):** formulário único para título, prioridade, tags, observação e data+hora de vencimento.
- `ManageTasksUseCase.editTask(id:title:tags:notes:dueDate:priority:)` — grava tudo numa transação. Valida título vazio (`emptyTaskTitle`) e duplicata entre ATIVAS **excluindo a própria tarefa** (senão salvar sem mexer no título acusaria duplicata). Notas em branco → `nil`; `dueDate: nil` limpa o vencimento; tags entram no catálogo (sobrevivem ao apagar a tarefa). **Não** escreve de volta no Lembretes — o write-back segue sendo só de conclusão, então tarefa editada diverge do lembrete de origem de propósito. +7 testes (Application 138).
- `TasksViewModel`: rascunho (`editTitle`/`editTags`/`editNotes`/`editHasDueDate`/`editDueDate`/`editPriority`) só é gravado no `saveEdit()`; `editFeedback` é separado de `feedback` porque o sheet cobre a lista. Vencimento ligado numa tarefa sem data sugere a próxima hora cheia.
- `TasksView`: `.sheet(item: $viewModel.editingTask)` (FocusTask é `Identifiable`). Abre pelo lápis na linha, duplo clique ou menu de contexto. **O popover de tags saiu** — tags agora se editam no formulário; `tagSuggestionsMenu` virou função com `Binding` para servir criação e edição. Menu de prioridade inline continua (acesso rápido).

**⬆️ Atualização automática com Sparkle 2 (ADR-9, 2026-07-30):** app fora da App Store não recebe update do sistema — agora se atualiza sozinho.
- Sparkle **2.9.4** via SPM, declarado só no `project.yml` (target do app). Domain/Application/Infrastructure seguem sem a dependência.
- Feed: `https://tomafoco.dds.tec.br/downloads/appcast.xml` (`SUFeedURL`). Checa 1×/dia (`SUScheduledCheckInterval: 86400`) e **pergunta antes de instalar** (`SUAutomaticallyUpdate: false`) — decisão de produto: num app de foco, trocar de versão sozinho cai no meio de uma sessão.
- `App/UI/Updates/UpdaterController.swift` — fachada `@MainActor` sobre `SPUStandardUpdaterController`. Fica no `App/` porque o Sparkle traz a própria UI; **sem port no Domain** (não há regra de domínio). Observa `canCheckForUpdates` por KVO (`publisher(for:)`) para desabilitar o botão durante uma checagem.
- **Fonte da verdade do "checar automaticamente" é o Sparkle** (`UserDefaults`/`SUEnableAutomaticChecks`), NÃO `PomodoroConfiguration`: quem faz o diálogo de primeira execução é o Sparkle, e uma cópia nossa divergiria da resposta do usuário. Daí o `refresh()` no `onAppear` das Configurações.
- UI: item "Buscar atualizações…" no menu "•••" (`OverflowMenu`, agora recebe `updater`) e no menu do app via `CommandGroup(after: .appInfo)` → `CheckForUpdatesMenuItem`. Seção "Atualizações" nas Configurações (toggle + botão + data da última checagem). **Ambas as Views observam o `UpdaterController` direto** — mesma regra do `MenuBarLabel`: nested ObservableObject não propaga.
- **Chave EdDSA gerada em 2026-07-30:** pública `u+xEBQBnQjhtr5BjpWwuRmlXdpxSGyCNxZJTUtXOtTA=` (já no `project.yml`); privada no chaveiro do login (serviço `https://sparkle-project.org`, conta `ed25519`). ⚠️ **Ainda SEM backup offline** — perder é irreversível: quem já instalou nunca mais atualiza. Exportar com `.spm-cache/artifacts/sparkle/Sparkle/bin/generate_keys -x arquivo.txt` e guardar em cofre. `release.sh` barra release se a chave sumir do chaveiro ou se `SUPublicEDKey` voltar a ser placeholder.
- **`release.sh` mudou:** (a) assina os bundles aninhados do Sparkle **de dentro para fora** com `find -depth` (sem isso a notarização REJEITA) e sem passar o entitlements do app (menor privilégio); (b) `codesign --verify --deep` antes de notarizar; (c) `generate_appcast` produz `build/appcast/appcast.xml` **depois** do staple (grampear depois mudaria o DMG e invalidaria a assinatura); (d) notas opcionais em `docs/release-notes/<versão>.html`; (e) publicação por `UPDATE_UPLOAD_DEST` (rsync) — **DMG antes do appcast**, senão o feed anuncia versão cujo download dá 404.
- Pacotes SPM clonados em `.spm-cache/` (`-clonedSourcePackagesDirPath`) porque o `release.sh` faz `rm -rf build` e o XCFramework do Sparkle seria rebaixado a cada release.
- **Subir versão é obrigatório:** o Sparkle compara `CFBundleVersion` — release com `CURRENT_PROJECT_VERSION` igual não é oferecida.
- **Validado em 2026-07-30:** `xcodebuild` limpo (zero warnings do nosso código), `make release-dry` completo — assinou os 5 bundles aninhados na ordem certa, `--verify --deep` passou, DMG 2,5 MB, `generate_appcast` escreveu `build/appcast/appcast.xml` com `sparkle:edSignature` e link das notas. `make test`: **217 verdes** (Domain 36, Application 138, Infra 43). Falta validar à mão o fluxo de update de ponta a ponta (exige publicar no servidor).
- ⚠️ **Achado: o build sai arm64-only** (não há `ARCHS` no `project.yml`/`release.sh`), então o appcast leva `<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>` e **Mac Intel não recebe atualização** — apesar de a doc dizer "universal binary". Vale desde antes do Sparkle; só ficou visível agora. Fix: `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO` no `xcodebuild` do `release.sh`.
- ⚠️ O primeiro `xcodebuild` com o Sparkle **trava** num diálogo do chaveiro (SwiftPM consulta o item `github.com` do login.keychain antes de baixar o artefato). Se parecer travado sem log, procure o diálogo na tela ou `killall SecurityAgent` — o artefato é público, o download funciona sem autenticação.

**🖱️ Clique morto depois do intervalo + conclusão que não chegava ao Lembretes (2026-07-31):**
- **Mouse:** sintoma relatado = cursor mexe, clique não funciona em nada, só volta reconectando o mouse. Causa: `BreakOverlayPresenter.dismiss()` fazia `orderOut` + soltava a janela **dentro do evento** que pediu o fechamento (o `sink` de `showsBreakOverlay` roda na cadeia do clique/Esc). Janela e `NSHostingView` sumindo no meio do rastreamento deixam o mouse-down sem destino — o sistema segue achando que há arrasto em curso. Agora: `ignoresMouseEvents = true` primeiro, chave devolvida a outra janela **visível** do app (só se a chave for do overlay — trazer de volta Tarefas/Relatórios fechados seria pior), `orderOut` no `DispatchQueue.main.async`, e as janelas são **reaproveitadas** entre intervalos (`rebuildWindowsIfScreensChanged` só recria quando os frames das telas mudam). Flag `isVisible` porque "tem janela" não significa mais "está na tela".
- **`with timeout of 5 seconds` nos scripts do navegador** (`BrowserScript`): o padrão do Apple Event é **2 minutos** — navegador ocupado congelava a main thread (é lá que o `NSAppleScript` roda) por esse tempo todo.
- **Medição (não repetir a tentativa):** trocar `URL of tab t of window w` por `URL of every tab of window w` parecia melhor (1 Apple Event por janela em vez de 1 por aba), mas com 40 abas no Safari mediu **26 ms contra 18 ms** por varredura — o coletivo paga a serialização da lista. Ficou como estava; comentário no código registra o número.
- **Lembretes:** `EventKitReminderImporter.setReminderCompleted` nunca chamava `requestAccess()`. Sem pedir acesso **naquele processo**, o EventKit responde como se o banco estivesse vazio e `calendarItem(withIdentifier:)` devolvia `nil` — ou seja, concluir tarefa numa sessão em que nada foi importado nunca chegava ao Lembretes. Agora pede acesso (já autorizado, volta na hora e sem prompt) e tem plano B varrendo `predicateForReminders(in: nil)` (inclui concluídos, necessário para reabrir).
- Falha de espelhamento deixou de ser silenciosa: `completeTask`/`reopenTask` devolvem `ReminderSyncOutcome` (`notApplicable`/`synced`/`failed`) e o `TasksViewModel` avisa na tela quando dá `failed`.
- `make test`: **232 verdes**; `xcodebuild` limpo. ⚠️ Validar à mão: (a) deixar acabar um intervalo curto e conferir que o clique continua vivo; (b) concluir tarefa importada logo após abrir o app, sem importar nada antes → aparece riscada no Lembretes.

**♻️ Lembrete recorrente pode ser reimportado (2026-07-31):** no picker, a dedup por `reminderID` passou a olhar só as tarefas **ativas** — com a cópia local concluída, o mesmo lembrete volta a ser clicável e entra como tarefa NOVA (`id` próprio; a concluída fica no histórico). Motivo: lembrete recorrente — concluir a ocorrência de hoje não podia barrar a de amanhã. **O lote (`importFromReminders`) continua deduplicando contra TODAS as tarefas**, inclusive concluídas: sem escolha item a item, um lote traria de volta tudo que já foi concluído por aqui. Na UI, `importedReminderIDs` agora só tem as ativas (marcadas/desabilitadas) e `reimportableReminderIDs` marca as concluídas com ícone de repetir (`arrow.clockwise.circle`). +3 testes (Application 141).
- **2026-08-05:** a legenda "já concluída aqui · importar de novo" foi **removida** — só o ícone diferencia. A reimportação leva os **dados atuais** do lembrete (`makeFocusTask` monta a tarefa nova a partir do `ImportedReminder` recém-buscado: título, notas, vencimento, prioridade e URL), porque num recorrente a data sempre muda; a tarefa concluída anterior fica intacta no histórico. Regressão: `test_importReminder_reimportacaoUsaOsDadosAtuaisDoLembrete`.

**🍅 App icon: tomate branco no lugar do símbolo DDS (2026-08-03):** estrutura original preservada — squircle navy com gradiente vertical, trilha branca a 10% e arco cyan continuam **bit a bit** os do ícone anterior. Tomate (não maçã) porque o app é Pomodoro.
- Gerador versionado em `scripts/make_icon.py` (Pillow). Ele **não redesenha o fundo**: abre cada `icon_<N>.png`, repinta só o miolo do anel (raio < 309/1024 − ¾ da espessura) com o gradiente amostrado do próprio arquivo na coluna x = 160/1024 (o gradiente é puramente vertical — medido) e compõe o tomate por cima. Por isso é **idempotente**: rodar de novo dá o mesmo MD5.
- Corpo: superelipse (`BODY_EXPONENT = 2.15`, `BODY_FLATTEN = 0.84`) — expoente > 2 dá o ombro do tomate; elipse pura vira bola e 2.5 vira caixa. Coroa: cabinho + 4 sépalas (`sepal()` paramétrica). **A coroa é desenhada quase toda ACIMA da silhueta do corpo** — corpo e coroa são da mesma cor, então o recorte contra o navy é o que a torna legível. Tentativa anterior de sobrepor as sépalas ao corpo e cavar um sulco de fundo com `polygon(outline=…)` serrilhou a borda e virou bigode; não repetir.
- Acabamento **branco com brilho**: gradiente `#FFFFFF → #AFBDD2` (cinza levemente azulado embaixo, para dar volume), brilho especular difuso no ombro esquerdo + glint menor por cima. `RIM_ALPHA = 0` — o contorno existe no script para corpo escuro, mas corpo claro já se separa do navy e o contorno só sujaria a borda.
- Geometria do ícone original medida e registrada no script: corpo com inset 100/1024 e canto arredondado r≈185, anel r=309 stroke 25, arco de −92° a +77°.
- ✅ Ícones do site atualizados em 2026-08-03: `site/assets/gen-og.py` já lia `icon_1024.png` do AppIcon, bastou rodar de novo (`python3 site/assets/gen-og.py`). Regenerou `icon-512/192`, `favicon-16/32`, `favicon.ico`, `apple-touch-icon.png` e `og-cover.jpg` com o tomate.

**🍅 Ícone da barra de menus = o mesmo tomate (2026-08-03):** o `MenuBarExtra` mostrava o emoji `🍅`/`☕️`/`⏸`/`▶️` + tempo; agora mostra o tomate do app dentro de um anel metade cyan, metade tinta.
- `App/UI/DesignSystem/TomatoMark.swift`: `TomatoMark` (`Shape`) reimplementa em Swift a MESMA geometria de `scripts/make_icon.py` (superelipse `2.15`/`0.84` + cabinho + 4 sépalas). **Se um lado mudar, o outro precisa acompanhar** — não há fonte única entre o PNG do AppIcon e o vetor da UI.
- **Todos os subpaths são normalizados para a mesma orientação** (`oriented(_:)`, área assinada): as sépalas espelhadas nascem com winding invertido e, com `nonzero`, virariam buraco no lugar de somar ao corpo.
- 🔴 **O rótulo do `MenuBarExtra` só renderiza `Text` e `Image`.** A primeira versão era um `ZStack` de `Circle().trim` + `Shape` e o item saiu **completamente vazio** na barra — nem ícone, nem texto. `MenuBarIcon` virou um `enum` que rasteriza um `NSImage` (`NSImage(size:flipped:true)` + `CGContext`) e o rótulo usa `Image(nsImage:).renderingMode(.original)` (sem `.original` o SwiftUI trataria como template e a metade cyan sumiria). **Não trocar por View desenhada.**
- 🔴 **`NSImage` cacheia a rasterização** — `NSColor` dinâmica lida dentro do `drawingHandler` congela no tema vigente no primeiro desenho e não acompanha a troca claro/escuro. Por isso são **duas imagens prontas** (`onLightBar` navy / `onDarkBar` branca) e o rótulo escolhe por `@Environment(\.colorScheme)`. Bug pego no dump PNG, não no build.
- Anel: `CGContext.addArc` num contexto com y para baixo — ângulo cresce no sentido horário, 0 é 3h. A **cyan vai de −π/2 (topo) a π/2 (base)**, ou seja, a metade da direita: mesmo ponto de partida e mesmo sentido do arco de progresso do ícone do app, para a identidade bater. Traço centrado no caminho, daí o inset de meia espessura.
- `TimerViewModel`: `menuBarLabel` deixou de carregar emoji e passou a ser só o tempo (vazio quando ocioso); estado pausado/aguardando virou `menuBarSymbol` (SF Symbol `pause.fill`/`play.fill`). `iconEmoji(for:)` foi removido.
- **Como conferir o desenho sem screenshot** (este ambiente não tem permissão de Gravação de Tela): compilar `TomatoMark.swift` com um `main.swift` que stuba `Brand` e escreve o `NSImage` em PNG — `swiftc App/UI/DesignSystem/TomatoMark.swift main.swift -o icondump`. Foi assim que o bug do cache apareceu.
- ⚠️ **Validar à mão**: se o item aparece na barra e se o cyan sobrevive na sua versão do macOS.

**🗑️ Modo hardcore REMOVIDO (2026-08-03)** — app, site, ícones e docs. Suíte: **228 verdes** (Domain 50, Application 134, Infra 44), `xcodebuild` limpo.
- **Por quê:** o produto é de autodisciplina, não de coerção (mesmo princípio que já justificava o overlay ser `.floating` e não `.screenSaver`). A trava atrapalhava interrupção legítima e era contornável de qualquer jeito (Force Quit não é bloqueável sem root).
- Saíram do Domain: `HardcoreOptions`, `PomodoroConfiguration.hardcore`, `DomainError.cancellationBlockedByHardcore` e `.reasonRequired`.
- **`PomodoroSession.reason` também saiu** — só existia para o `requireReason` do hardcore, então virava campo que nada mais conseguia preencher. Removido também de `SessionStateMachine`/`SessionEvent.startFocus` (agora `startFocus(taskIDs:)`).
- Saíram da Application: `HardcoreCancelPolicy` + seus testes. **`SessionCoordinator.startFocus`/`cancel`/`skipPhase` deixaram de ser `throws`** — não sobrou erro para lançar; callers perderam o `try`/`do-catch`.
- Saíram do App: seção "Modo hardcore" das Configurações, `hardcoreEnabled`/`GraceMinutes`/`RequireReason` no `SettingsViewModel`, `TimerViewModel.reason`/`requiresReason` e o `TextField` "Motivo do foco" da `MainView`.
- ⚠️ **A chave `hardcore` continua gravada no `UserDefaults` de quem já usava o app.** Não é problema: o `init(from:)` do `PomodoroConfiguration` ignora chave desconhecida. Isso é crítico — se lançasse, o store cairia no padrão e apagaria TODAS as preferências do usuário em silêncio (mesma armadilha do rename `autoStartNextFocus`). Há teste de regressão: `test_configComChaveHardcoreObsoleta_ignoraSemPerderOResto`.
- Site: `index.html` (featureList + card, que virou só "Tela cheia de intervalo") e a legenda do print de configurações em `assets/js/app.js`.
- Docs: RF-06 e T-22 marcados como removidos (não apagados — o histórico da decisão importa); UC-01/UC-03 renumerados, e o "fluxo 4a" do UC-01 virou **"fluxo 3a"** em `especificacao.md` e `tarefas.md`.

**🚀 Release 1.7 publicada (2026-08-03)** — `MARKETING_VERSION 1.7` / `CURRENT_PROJECT_VERSION 8`. Conteúdo: ícone tomate (app + barra de menus) e remoção do modo hardcore.
- `make release` completo: notarização **Accepted** nas duas etapas (app e DMG), staple ok, `spctl --assess` → `source=Notarized Developer ID`. DMG 3,67 MB.
- ✅ **O achado do build arm64-only já estava corrigido**: `release.sh` passa `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO`. Confirmado com `lipo -archs` → `x86_64 arm64`, e o appcast saiu **sem** `<sparkle:hardwareRequirements>` — Mac Intel recebe atualização.
- **Publicação = commit + push no repo do site** (`danilodumba/tomafoco-site`, branch `main`) → GitHub Actions → Azure Static Web Apps. NÃO existe `UPDATE_UPLOAD_DEST`/rsync configurado; o `release.sh` só deixa os arquivos em `build/appcast/` e avisa. O passo manual é copiar DMG + `.html` + `appcast.xml` para `site/downloads/`.
- ⚠️ **Bump de versão no site é em 5 arquivos, não 1.** Além do `index.html` (9 ocorrências: JSON-LD, hero, 2 links de download, tabela de fatos, rodapé, cache-buster do CSS e do JS), tem `assets/js/app.js` (`CONFIG.downloadHref` — o link que o modal de cadastro usa de verdade), `404.html` e `privacidade.html` (rodapé + cache-buster). Esquecer o `app.js` deixa o botão do modal baixando a versão anterior.
- **Repo do app (`danilodumba/tomafocomacos`) tinha o remoto com um commit raiz INDEPENDENTE** contendo só o `LICENSE` (MIT) — sem ancestral comum com o histórico local, que nunca tinha sido enviado. Resolvido com `git merge origin/main --allow-unrelated-histories` (nada de force push). Tag `v1.7` publicada.

**🚀 Release 1.8 publicada (2026-08-06)** — `MARKETING_VERSION 1.8` / `CURRENT_PROJECT_VERSION 9`. Conteúdo: app só barra de menus (popover = `MainView` inteira, `MenuBarView` apagada, `ActivationPolicyController`, `RecoveryAlert` via `NSAlert`).
- `make release` completo: notarização **Accepted** nas duas etapas, staple ok, `spctl --assess` → `source=Notarized Developer ID`. DMG 3,62 MB.
- Appcast gerado por `generate_appcast` só lista o item mais recente (não acumula histórico de versões) — publicado assim mesmo, é o comportamento padrão da ferramenta.
- Bump nos 5 arquivos do site (ver nota da 1.7 acima) + copiar `Tomafoco-1.8.dmg`/`.html`/`appcast.xml` pra `site/downloads/` — DMG publicado antes do appcast. `git push` nos dois repos + tag `v1.8`.
- Verificado ao vivo: `/`, `/downloads/Tomafoco-1.7.dmg`, `appcast.xml` e as notas todos 200; o DMG servido tem o **mesmo SHA-256** do local.

**🪟 O popover da barra virou o form principal — app só barra de menus (2026-08-05).** Substitui a reversão de 2026-07-30: a `WindowGroup` foi removida e o `MenuBarExtra(.window)` passou a renderizar a **`MainView` inteira** (340×480, anel + seletor de tarefas). `MenuBarView.swift` (form compacto de 250pt) foi **apagada** — duplicava a mesma UI pela metade.
- 🔴 **O `MenuBarExtra` tem que ser a PRIMEIRA cena do `body`.** O SwiftUI abre a cena inicial no lançamento: com `Window("Tarefas")` na frente, a janela de Tarefas subia sozinha ao abrir o app. `defaultLaunchBehavior(.suppressed)` resolveria, mas é macOS 15+ e o `SceneBuilder` **não aceita `if #available`** (não tem `buildEither`) — com deployment target 13 a ordem das cenas é a única saída. Verificado com `CGWindowListCopyWindowInfo` (owner PID): instância nova sobe com zero janelas.
- **Ícone de tarefas no cabeçalho** (topo-esquerda, `checklist`), espelhando a engrenagem (`OverflowMenu`) à direita: abre a janela Tarefas. `OverflowMenu` perdeu `showsOpenMainWindow` (apontava para `openWindow(id: "main")`, id que nunca existiu).
- **`LSUIElement: true` + `ActivationPolicyController` (App/).** App `.accessory` **não exibe menu superior**, e sem ele Tarefas/Relatórios/Configurações perderiam ⌘C/⌘V/⌘W nos campos de texto. O controller observa `NSWindow.didBecomeKey`/`willClose`: janela "de verdade" (`isVisible && styleMask.contains(.titled) && !(is NSPanel)`) → `.regular` + `NSApp.activate` (sem o activate o menu não desenha); última fechando → volta a `.accessory` (decisão no `DispatchQueue.main.async`, senão a janela que está fechando ainda conta). O predicado exclui de propósito o popover, o toast (`NSPanel`) e as telas de intervalo (`OverlayWindow`, borderless). Retido pelo `AppContainer` — sem referência forte os observers morrem.
- **Recuperação pós-crash virou `NSAlert`** (`App/UI/Recovery/RecoveryAlert.swift`): `MenuBarExtra` não apresenta `.sheet`, e o popover pode nunca ser aberto. Disparada por `Task { await container.recoverFromCrashIfNeeded() }` dentro de `AppContainer.live()` — não há mais `.task` de janela para isso. `RecoverySheet` foi removida da `MainView`; `pendingRecovery`/`resumeRecoveredSession`/`discardRecoveredSession`/`recoveryDescription` do VM seguem iguais.
- `CommandGroup(after: .appInfo)` ("Buscar atualizações…") migrou para a cena `Window("Tarefas")` — o menu do app só existe com alguma janela aberta.
- **Efeito colateral aceito:** `DockAttentionRequester` (Dock pulando no fim da etapa) é no-op enquanto o app está `.accessory`; som + notificação continuam.
- `make test` 228 verdes, `xcodebuild` limpo. ⚠️ Validar à mão: popover com anel/seletor de tarefa (Menu dentro de `MenuBarExtra`), espaço aciona play/pause, ícone de tarefas abre a janela e traz Dock+menu, fechar as janelas tira o app do Dock, e o `NSAlert` de sessão recuperada após matar o app com foco ativo.

**🚀 Release 1.9 publicada (2026-08-10)** — `MARKETING_VERSION 1.9` / `CURRENT_PROJECT_VERSION 10`. Conteúdo: checkbox "Mostrar concluídas" (entrada abaixo).
- `make release` completo: notarização **Accepted** nas duas etapas, staple ok, `spctl` → `source=Notarized Developer ID`. DMG 3,63 MB, universal (`lipo -archs` → `x86_64 arm64`).
- Publicação: DMG + notas + `appcast.xml` copiados pra `site/downloads/`, bump nos 5 arquivos do site (ver nota da 1.7), commit + push nos 2 repos, tag `v1.9`. Verificado ao vivo: `/`, DMG e appcast **200**; DMG servido com o **mesmo SHA-256** do local. Notas `.html` respondem **301** → URL sem extensão → 200 (comportamento padrão do Azure SWA, igual na 1.8 — Sparkle segue redirect).
- Commits de migração dos docs pro vault (pendências antigas no working tree dos 2 repos) entraram **separados** dos commits de release.

**☑️ Checkbox "Mostrar concluídas" na lista de tarefas (2026-08-10):** só UI — `TasksViewModel` + `TasksView`; Domain/Application intocados (a edição RF-09.6 já funcionava para qualquer tarefa, faltava renderizar as concluídas).
- `TasksViewModel.showsCompleted` persistida em `UserDefaults` chave `tasksShowsCompleted` (mesmo padrão do `sortOrder`; ausente → `false` = comportamento antigo). É preferência de exibição, não recorte de sessão — comentário das linhas 46–47 atualizado.
- `displayedTasks`: ativas filtradas+ordenadas e, com o toggle, concluídas em bloco no FIM na ordem `completedAt` desc do `reload()` — não intercalar no `sortComparator` (vencimento/prioridade/atraso não dizem nada de tarefa finalizada; padrão do Apple Lembretes). Busca/tag/prioridade valem para os dois blocos (`applyFilters` extraído).
- `TasksView`: `Toggle(.checkbox)` no `controlBar` antes do `Spacer`; título concluído riscado + `Brand.textFaint`; `emptyMessage` considera concluídas com o toggle ligado. Linha concluída reusa tudo: círculo reabre (`reopenTask` + write-back), lápis/duplo clique/menu editam, lixeira apaga.
- **Edge case aceito:** `editTask` só checa duplicata entre ATIVAS — renomear concluída para título de ativa passa; simétrico ao `addTask` (unicidade é deliberadamente só entre ativas).
- `make test` verde, build limpo. Ambiente: certificado *Apple Development* venceu em 2026-08-10 ("Mac Development" não encontrado) — **renovado no mesmo dia** pelo Xcode (Settings › Accounts › Manage Certificates), build assinado voltou a passar; assinatura nova pode re-pedir TCC (Automação/Lembretes) na primeira execução. Developer ID (release) intacto até 2027-02-01. E o `.spm-cache/workspace-state.json` ainda apontava `…/tomafoco/ds.focus` (pré-rename) — corrigido com sed para `…/APP`.
- ⚠️ Validar à mão: ligar checkbox → concluídas riscadas no fim; busca as filtra; círculo reabre; lápis edita; estado sobrevive a reiniciar o app.

**🕘 Histórico nas tarefas (FEAT-001 / RF-09.7 + RF-10.3, 2026-09-09):** cada tarefa passa a ter N
entradas datadas (data de inclusão + descrição), e elas aparecem nos relatórios. Suíte **244 verdes**
(Domain 52, Application 148, Infra 44), `xcodebuild` limpo.
- Domain: `TaskHistoryEntry` (`id`/`createdAt`/`text`, tudo `let` — é log) embutido em
  `FocusTask.history`. **Decode com `decodeIfPresent ?? []`**, igual a `tags`: `tasks.json` gravado
  antes da feature tem que abrir sem migração — decode que lança viraria `tasks.json.bak` e o
  usuário abriria o app sem tarefa nenhuma. Regressão em `TaskLinkCodingTests`. Novo
  `DomainError.emptyHistoryEntry`.
- Application: `ManageTasksUseCase.addHistoryEntry(taskID:text:)` / `deleteHistoryEntry(taskID:entryID:)`
  em cima do `update(id:)` que já existia, com `now`/`makeID` injetados (nada de `Date()`/`UUID()`
  inline). **`editTask` não muda** — ele muta só os campos que lista, então o histórico sobrevive
  a salvar o formulário; há teste de regressão explícito para isso.
- **Decisão de produto:** entrada é **só manual** (nada de log automático de sessão/conclusão — não
  toca `SessionCoordinator` nem a máquina) e é **append + delete, sem edição**.
- **Decisão técnica:** a entrada **grava na hora**, fora do rascunho transacional do `editSheet`.
  "Cancelar" desfaz título/tags/vencimento, mas NÃO desfaz entrada já adicionada. Coerente com log
  e evita mais um parâmetro em `editTask`; a UI avisa com a legenda "· gravado na hora".
- App: seção "Histórico" dentro do formulário de edição (`TasksView.historySection`) — `ScrollView`
  + `VStack`, **não `List`**, porque `List` dentro de `Form` tem altura imprevisível. Badge
  `clock.arrow.circlepath` + contagem na linha da tarefa. VM: `editingHistory` (ordenado desc) +
  `newHistoryText`; erros vão para `editFeedback`, não `feedback` (o sheet cobre a lista).
- Relatórios: `FocusReport.HistoryItem` (`Identifiable` pelo id da entrada — `ForEach` precisa de
  identidade estável) montado de `tasks.flatMap(\.history)` filtrado pelo `interval`. **Sem fallback
  "Tarefa removida"**: a entrada mora dentro da tarefa e some com ela, diferente de `taskTotals`.
  `ReportCSVExporter.taskHistoryCSV` (`Tarefa,Data,Descrição`) em CSV separado — a granularidade é
  outra (1 tarefa → N entradas) e concatenar numa célula estragaria a planilha. `exportCSV()` da
  `ReportsView` virou `save(csv:defaultName:)`, usado pelos dois botões.
- **Bug corrigido (2026-09-29):** Return no campo "Nova entrada" disparava "Salvar" (`.defaultAction`
  é key equivalent da janela e roda ANTES do `onSubmit`) → sheet fechava sem gravar a entrada. Agora
  `FocusHost` (dono do `@FocusState`, dentro do sheet) tira o `.defaultAction` do "Salvar" enquanto o
  campo de histórico está focado; e `saveEdit()` grava texto pendente no campo como entrada.
  E o campo nem focava: dentro do `Form(.grouped)`, linha com `Button` vira alvo de clique inteira
  (clique ia pro "Adicionar", desabilitado com texto vazio). `historySection` saiu do `Form` — fica
  entre o `Form` e a barra Cancelar/Salvar. Também corrige a nota antiga acima sobre "seção dentro do formulário".
- **Campo "Observação" removido do formulário (2026-09-29)** — obsoleto com o histórico.
  `editTask` perdeu o parâmetro `notes` e não toca mais em `FocusTask.notes`. O campo `notes`
  **continua no modelo**: vem da importação do Lembretes e ainda aparece (só leitura) na linha da
  tarefa; apagar do modelo perderia dado já gravado. Teste `test_editTask_preservaNotasImportadas`.
- ⚠️ Validar à mão: adicionar/apagar entrada no formulário; "Cancelar" não desfaz; salvar edição não
  zera o histórico; reabrir o app persiste; seção e CSV de histórico nos Relatórios (acentos com BOM).

**📊 Relatórios: período "Hoje" + relatório por tarefa (RF-10.5 / RF-10.6 / T-51, 2026-10-27):**
- `ReportsViewModel.Period.today` ("Hoje" = início do dia → agora), primeiro no segmented.
- **Mudança de comportamento:** a lista/CSV de **tarefas concluídas passou a respeitar o período**
  (`completedAll` filtrado por `completedAt` no `interval`). Antes ignorava — com "Hoje" mostraria
  tudo, o que anularia o filtro. Quem quer ver todas escolhe "Tudo".
- Application: `TaskReport` (+ `Session` com `subtaskTitle`) e `ReportBuilder.taskReport(...)` no
  mesmo arquivo do `ReportBuilder` (reusa `duration`/`dailyTotals`/`historyEntries` privados).
  Sessão da filha entra no pai UMA vez; foco direto no pai vence (`subtaskTitle = nil`). Tarefa
  apagada → `nil` (só vive como "Tarefa removida" nas `taskTotals`). Conclusões via
  `CompletedTaskOccurrence` recortadas pelo período. `ReportCSVExporter.taskSessionsCSV` +
  `outcomeLabel` **público** (a View usa no rótulo do desfecho).
- VM guarda `loadedRecords`/`loadedTasks` para recalcular ao trocar `selectedTaskID` sem reler
  disco; `taskOptions` = `taskTotals` com `taskID` que ainda existe (ordem por tempo desc).
  Seleção fora da lista nova é limpa no `reload()`.
- View: `taskReportSection` entre "Horas por tarefa" e "Tarefas concluídas"; itens do menu são
  `Toggle` (checkmark nativo, mesma regra do seletor do timer). Gráfico em **minutos** (tarefa
  raramente passa de 1h/dia) e só com >1 dia. `statTile` extraído do resumo.
- `make test` **442 verdes** (Domain 138, Application 247, Infra 57); `xcodebuild` limpo.
- ⚠️ Validar à mão: "Hoje" após um foco; escolher tarefa → sessões/duração/desfecho; filha com ↳ no
  relatório do pai; trocar período limpa seleção se a tarefa sai; CSV abre no Numbers/Excel com acentos.

**🚀 Release 1.13 publicada (2026-10-27)** — `MARKETING_VERSION 1.13` / `CURRENT_PROJECT_VERSION 14`.
Conteúdo: Kanban (FEAT-005), subtarefas (FEAT-003), nota/link/urgente (T-48), escopo por tag no foco
(T-50), período "Hoje" + relatório por tarefa (T-51) e as correções do code review.
- `make release`: notarização **Accepted** (app e DMG), staple ok, `spctl` → `Notarized Developer ID`,
  universal (`x86_64 arm64`), DMG 5,1 MB. Appcast `sparkle:version 14`, sem `hardwareRequirements`.
- Trabalho pendente foi commitado em **dois commits**: `feat:` com todas as features e `release:` com o
  bump + notas. Site: bump nos 4 arquivos (sed `1\.12`), DMG + notas + appcast no mesmo commit, push
  em `tomafoco-site` (deploy via GitHub Actions). Tag `v1.13` no repo do app.

**🫳 Arrastar tarefa para virar subtarefa + chip visível (FEAT-003 cont., 2026-10-27, pós-1.13):**
- Lista: badge `0/1` saiu da linha de metadados → **chip** ao lado do título (`checklist 2/5
  subtarefas ▸`, cápsula; cyan cheio com tudo feito). `subtaskBadge` só mudou de lugar e visual.
- `ManageTasksUseCase.makeSubtask(id:parentID:) -> FocusTask?`: topo → filha e filha trocando de
  pai. Recusa: **`DomainError.taskHasSubtasks`** (novo — a arrastada já é pai),
  `subtaskNestingNotAllowed` (alvo é subtarefa ou ela mesma), `duplicateEntry` (irmãs ativas do
  novo pai; concluída não disputa), `parentTaskNotFound`; tarefa inexistente → `nil`. Mesmo pai →
  no-op sem gravar. **Raia mantida** (≠ `addSubtask`). Pai concluído reabre na mesma gravação.
- `TasksView`: `.draggable(uuid)` + `.dropDestination(for: String.self)` em **toda** linha,
  `targetedTaskID` (@State) → borda cyan. `TasksViewModel.handleDrop(_:onto:)` (mesmo padrão do
  Kanban: recusa durante `isMutatingTask` e drop sobre si mesma) → `makeSubtask(_:of:)` devolve
  `Bool` — `false` faz o arraste voltar e o motivo vai pro `feedback`. Pai alvo entra em
  `expandedTaskIDs`. Menu de contexto "Tornar subtarefa de ▸" (`possibleParents(for:)`: topo ativas
  menos ela e o pai atual; vazio se já é pai) como alternativa acessível.
- `make test` **450 verdes** (Domain 138, Application 255, Infra 57); `xcodebuild` limpo.
- ✅ Validado à mão pelo usuário em 2026-10-27 (release 1.14): arrastar topo → filha, pai com filhas
  volta + aviso, soltar sobre filha avisa, filha troca de pai, menu de contexto.

**🏷️ Seletor do foco: tags nos itens e filha sem "Pai › Filha" (2026-10-27, pós-1.13):** reverte
parte do T-50. `TimerViewModel.displayTitle(of:)`/`menuTitle(of:)` **removidos**; botão do seletor e
anel (`resolveTaskTitle`) usam só `task.title` — a filha segue com ícone ↳ no menu. `TaskTree.displayTitle`
continua existindo para os Relatórios. `MainView.menuItemText(_:)`: `Text(título) + Text("  tag1 · tag2")`
esmaecido (`NSMenu` não renderiza chip). `xcodebuild` limpo; nenhum teste afetado (só App/).
✅ Validado à mão pelo usuário em 2026-10-27 (release 1.14).

**↩️ Editor da subtarefa → pai (2026-10-27, pós-1.13):** "↳ Pai" no header do `TaskEditorSheet`
é botão (cyan + chevron) → `TaskEditorViewModel.openParent()` → `onOpenTask(parent)` (lista e Kanban
já passavam o closure → `beginEditing`). VM guarda `parent: FocusTask?`; `parentTitle` computado.
Rascunho não gravado ao trocar (igual pai → filha). Só App/, `xcodebuild` limpo. ✅ Validado à mão
pelo usuário em 2026-10-27 (release 1.14).

**🚀 Release 1.14 publicada (2026-10-27)** — `MARKETING_VERSION 1.14` / `CURRENT_PROJECT_VERSION 15`.
Conteúdo: arrastar tarefa para virar subtarefa (+ menu "Tornar subtarefa de ▸"), chip de subtarefas
visível, tags no seletor do foco e filha sem "Pai › Filha", "↳ Pai" do editor abre o pai.
- `make release`: notarização **Accepted** (app e DMG), staple ok, `spctl` → `Notarized Developer ID`,
  universal (`x86_64 arm64`), DMG 5,2 MB. Appcast `sparkle:version 15`, sem `hardwareRequirements`.
- Dois commits (`feat:` + `release:`), tag `v1.14`. Site: bump nos 4 arquivos (sed `1\.13`), DMG + notas +
  appcast no mesmo commit, push em `tomafoco-site`. Verificado ao vivo após ~60s: `/`, DMG, `app.js` **200**,
  appcast com versão 15, SHA-256 do DMG servido = local; notas `.html` **301** (normal).

**🚀 Release 1.15 publicada (2026-10-27)** — `MARKETING_VERSION 1.15` / `CURRENT_PROJECT_VERSION 16`.
Conteúdo: diária fecha e clona para amanhã (revisão da FEAT-004), datas de cadastro/encerramento só
leitura no formulário, botão "Tarefas" no Kanban.
- `make release`: notarização **Accepted** (app e DMG), staple ok, `spctl` → `Notarized Developer ID`,
  universal (`x86_64 arm64`), DMG 5,2 MB. Appcast `sparkle:version 16`, sem `hardwareRequirements`.
- Dois commits (`feat:` + `release:`), tag `v1.15`. Site: bump nos 4 arquivos (sed `1\.14`), DMG + notas +
  appcast no mesmo commit, push em `tomafoco-site`. Verificado ao vivo após ~75s: `/`, DMG, `app.js`,
  appcast **200** (versão 16), SHA-256 do DMG servido = local; notas `.html` **301** (normal).
- ⚠️ Validação manual da 1.15 ainda pendente (itens listados nas três entradas acima).

**🚀 Release 1.16 publicada (2026-10-27)** — `MARKETING_VERSION 1.16` / `CURRENT_PROJECT_VERSION 17`.
Conteúdo: metadados do cartão do Kanban um por linha (pai/subtarefas, vencimento, link, e "Diária" +
histórico juntos na última) e remoção do aviso "nova cópia criada na primeira raia" ao concluir diária
pelo quadro (o clone já é visível). Só `App/`, sem mudança de testes.
- `make release`: notarização **Accepted** (app e DMG), staple ok, `spctl` → `Notarized Developer ID`,
  universal (`x86_64 arm64`), DMG 5,2 MB. Appcast `sparkle:version 17`, sem `hardwareRequirements`.
- Commits `feat:` + `fix:` + `release:`, tag `v1.16`. Site: bump nos 4 arquivos (sed `1\.15`), DMG + notas +
  appcast no mesmo commit, push em `tomafoco-site`.
- ⚠️ Validação manual da 1.15 e da 1.16 ainda pendente (cartão com tudo preenchido → 4 linhas na ordem;
  diária na Done sem aviso).

**🗂️ FEAT-006 — Projetos + banco SwiftData + bugs de data (2026-10-29, branch `feat/feat-006-projetos`, NÃO commitado):**
Plano, decisões e desvios em `../DOCS - Tomafoco/APP/Features/FEAT-006 Criar o conceito de projetos..md`.
- **Datas:** "Hoje" inclui abertas atrasadas de dias anteriores; `TaskFilter.matchesCard` avalia
  vencimento só da própria tarefa (bug confirmado: pai atrasado levava a filha para "Atrasadas");
  `ReminderDueDate` (lembrete dia inteiro → 23:59); `MinuteClock` + `isOverdue(now:)` (destaque e
  filtro com o mesmo `now`, avança por minuto com a janela aberta). Atrasada continua **por hora**
  (decisão do usuário).
- **macOS 14 mínimo** (`project.yml` + 4 `Package.swift`); fallbacks de 13 removidos.
- **SwiftData (ADR-11):** `Persistence/SwiftData/` — `TomafocoSchemaV1` (payload Codable do Domain +
  colunas de busca), `TomafocoDatabase` (`mainContext`, sem autosave, `perform` = transação, implementa
  `UnitOfWork`; store que não abre vira `.bak-<data>`), stores de tarefa (espelho em memória + diff),
  projeto, sessão (histórico só insert), quadro, tags. **Ports de persistência e use cases que os usam
  são `@MainActor`** — testes dessas classes também. `JSONToSwiftDataImporter` roda no `AppContainer.live()`
  antes de tudo; idempotente (`StoreMeta`), JSON → `*.json.migrated` só após o `save()`.
- **Regra nova: mudar um `@Model` exige `TomafocoSchemaV2` + estágio no `TomafocoMigrationPlan`.**
  Campo novo no Domain NÃO exige (vai no payload).
- **Projetos:** `Project`/`ProjectColor`/`ProjectFilter` (Domain), `ManageProjectsUseCase`, `FocusTask.projectID`
  (subtarefa herda/propaga; clone da diária leva), `TaskEdit.projectID` (**a forma curta de `editTask`
  preserva o projeto**). App: `App/UI/Projects/` (sheet, estilo, chip, faixa, seletor, filtro); urgente
  perdeu a faixa vermelha (faixa agora é do projeto).
- Validado com **cópia** dos dados reais (95 tarefas, 302 sessões, 16 tags): migração idêntica.
- Code review: 7 correções (importador com banco em memória, profundidade da transação no `save()`
  falho, `perform` aninhado, `onSubmit` do título, retry + aviso ao recriar banco, catálogo de tags
  antigo preservado, `ProjectCatalog`/`ProjectsHosting`). Lista no FEAT-006.
- 2º review (xhigh): 13 correções — destaques: filha **sem** vencimento herda o do pai no
  `matchesCard` (com vencimento, só o dela); task store codifica antes de tocar o contexto;
  `ProjectCatalog` mantém o anterior em erro; lote avisa `projectNotFound`; sheet de projeto sem
  `.defaultAction`; `ProjectRepository.project(id:)`. Lista completa no FEAT-006.
- 3º review (high): 10 correções — destaques: restauração dos `.migrated` decidida pelo disco
  (`StoreMeta` ausente), não por `wasReset`; "Próximos 7 dias" ⊇ "Hoje"; subtarefa herda só a
  **data** do pai; `LaunchAlert` = fila sequencial pós-lançamento (`RecoveryAlert` virou `async`);
  `saveTasks` renumera `position` se reordenar; `MinuteClockHosting`. `projects:` obrigatório com
  `EphemeralProjectRepository` padrão.
- `make test` **527 verdes** (Domain 154, Application 282, Infra 91); `xcodebuild` limpo.
- ⚠️ **Antes de rodar o app:** copiar `~/Library/Application Support/Tomafoco/` — o 1º lançamento migra
  de verdade. Site ainda diz macOS 13 de propósito (muda na release).

**📊 Relatório de projetos (RF-10.7, 2026-10-29, mesma branch):** `ReportBuilder.projectReport` (só
tarefas pai; total conta cada sessão uma vez), janela "Relatórios — Projetos" (`project-reports`), menu
**Relatórios ▸ Tarefas… / Projetos…**, PDF A4 paginado (`ProjectReportPDF`, `ImageRenderer` → `CGContext`
PDF; cores de papel fixas via `ProjectColor.printColor`; datas pt-BR fixas) com pré-visualização PDFKit,
salvar e imprimir. **Para conferir o PDF sem rodar o app:** pacote SPM executável no scratchpad
dependendo de Domain/Application + cópia de `ProjectReportPDF`/`ProjectReportsViewModel`/
`ReportsViewModel`/`ReportPeriod`/`ProjectStyle`/`Brand`, renderiza e exporta PNG pelo `PDFPage.thumbnail`.

**🚀 Release 1.17 publicada (2026-10-29)** — `MARKETING_VERSION 1.17` / `CURRENT_PROJECT_VERSION 18`.
Conteúdo: FEAT-006 inteira (projetos, relatório de projetos em PDF, banco SwiftData, correções de data).
- **Primeira versão que exige macOS 14** — appcast com `minimumSystemVersion 14.0` (Ventura não recebe).
  **Primeiro lançamento migra os dados** do usuário (JSON → `Tomafoco.store`); voltar de versão não é suportado.
- `make release`: notarização **Accepted**, staple ok, `spctl` → `Notarized Developer ID`, universal
  (`x86_64 arm64`), DMG 6,0 MB. Appcast `sparkle:version 18`, sem `hardwareRequirements`.
- Commits `feat:` + `release:` na branch `feat/feat-006-projetos`, merge fast-forward na `main`, tag `v1.17`.
  Site: bump nos 4 arquivos (sed `1\.16`), macOS 13 → 14 (3 lugares), card "Projetos com relatório em
  PDF", DMG + notas + appcast no mesmo commit, push em `tomafoco-site`.
- ⚠️ Validação manual da FEAT-006 **não** foi feita antes da release (pedido do usuário) — fazer na 1ª abertura.

## Como retomar

```bash
cd /Volumes/danilo_ssd/Projetos/tomafoco/APP
make test     # roda testes dos pacotes SPM (Domain/Application/Infra)
make open     # gera Tomafoco.xcodeproj via XcodeGen e abre no Xcode
```

Pré-requisitos: `brew install xcodegen` (e opcional `brew install swiftlint`). O `.xcodeproj` não é versionado — `project.yml` é a fonte da verdade.

## Próximas tarefas (backlog em `../DOCS - Tomafoco/APP/tarefas.md`)

1. ~~Validar build/testes reais no Mac~~ ✅ feito em 2026-07-22.
2. ~~T-20 — UI de adicionar apps via `NSOpenPanel`~~ ✅ feito em 2026-07-22 (falta smoke test manual).
3. ~~Validar T-20 e ADR-8 à mão~~ ✅ feito em 2026-07-22 — bloqueio de sites confirmado funcionando.
4. ~~T-21 — fluxo de "retomar" pós-crash~~ ✅ feito em 2026-07-22: evento puro `adoptRecovered` (só a partir de ocioso, preserva `endsAt`, não bloqueia se a fase for intervalo) + `SessionCoordinator.adoptRecoveredSession` + diálogo com "Retomar"/"Encerrar e liberar" mostrando fase/ciclo/restante.
5. **T-12** — validação manual do bloqueio de apps (app fecha < 2s). T-13 (hosts) está suspenso pelo ADR-8.
6. ~~T-25 — assinatura, notarização e DMG~~ ✅ feito em 2026-07-22. `make release` gera `build/Tomafoco-1.0.dmg` assinado, notarizado (`Accepted`) e grampeado. Certificado *Developer ID Application: Danilo Dumba (CJQ7T4KV7H)*, válido até 2027-02-01. Credencial de notarização: perfil `tomafoco` no chaveiro, via chave de API do App Store Connect (Apple ID + senha de app dava 401).
7. ~~`git init`~~ ✅ feito em 2026-07-22 (branch `main`, commit inicial `d374955`).
8. ~~Decidir o destino do código parado~~ ✅ removido em 2026-07-22.

**↪️ Site de redirecionamento configurável (2026-07-22):** `PomodoroConfiguration.blockedRedirectURL: String?` (chave `blockedRedirectURL`; JSON antigo sem ela → `nil`, teste em `PomodoroConfigurationCodingTests`). Vazio → `blocked.html` padrão. `AppleScriptBrowserBlocker` ganhou `redirectURLProvider: @Sendable () -> String?` — lido **a cada varredura** (mudar nas Configurações vale na próxima passada, sem religar). `normalizedRedirect` adiciona `https://` quando falta esquema; `redirectTarget(domains:)` cai na página padrão se o destino configurado estiver ele mesmo bloqueado (evita laço). AppContainer injeta `{ settings.loadConfiguration().blockedRedirectURL }`. UI: campo na aba **Sites** das Configurações. +6 testes no blocker, +2 no config.

**🏷️ Tags nas tarefas (2026-07-22):** `FocusTask.tags: [String]` (grafia de entrada preservada; `normalizeTags` trima, descarta vazias, deduplica por caixa). **Decode manual em `FocusTask`** só por causa de `tags`: JSON antigo sem a chave decodifica com `[]` (`decodeIfPresent ?? []`) — `encode` segue sintetizado; teste de regressão em `TaskLinkCodingTests`. `ManageTasksUseCase.addTask(title:tags:)`, `setTags(id:tags:)`, `allTags()`. UI: campo "tags (vírgula)" no cabeçalho + chips cyan por tarefa + popover 🏷️ de edição; `TasksViewModel.parseTags` só divide por vírgula (normalização final é do Domain). **Tags são internas do app — não vêm do Lembretes** (EventKit não expõe tags, ver `ReminderList`). Relatórios ainda NÃO agrupam por tag. Suíte: Domain 35, Application 108; `xcodebuild` limpo.

**🔎 Importação do Lembretes agora é por picker pesquisável (2026-07-23):** substituiu o import em lote por lista (toggle de listas foi removido do fluxo). "Importar do Lembretes…" abre sheet com **busca por título** + lista de lembretes individuais; **clicar num importa só ele na hora**; já-importado fica cinza/desabilitado (`importedReminderIDs` = `reminderID`s das tarefas). `ManageTasksUseCase` ganhou `loadImportableReminders(fromLists:)` e `importReminder(_:)` (dedup por `reminderID` contra TODAS as tarefas; título vazio ignorado; helper `makeFocusTask(from:title:)` compartilhado com o lote). `importFromReminders(fromLists:)` continua existindo (reusa o helper). **Campos ricos importados:** `FocusTask` ganhou `notes`, `dueDate`, `priority` (0 do EventKit → `nil`), `sourceURL` — todos opcionais, decode manual `decodeIfPresent` (JSON antigo → `nil`, regressão em `TaskLinkCodingTests`). `ImportedReminder` carrega os mesmos campos; `EventKitReminderImporter` lê `notes`/`dueDateComponents?.date`/`priority`/`url?.absoluteString`. **`sourceURL` NÃO é deep-link pro app Lembretes** (EventKit não expõe) — é a URL que o usuário anexou ao lembrete; exibida como `Link` na linha da tarefa junto com data de vencimento e notas (2 linhas). `make test` verde, `xcodebuild` limpo. ⚠️ Validar à mão: buscar por título, clicar importa 1, reimportar não duplica, campos gravados em `tasks.json`.

**✅ Sincronização de conclusão de volta no Lembretes (2026-07-23):** concluir/reabrir uma tarefa importada espelha o estado no app Lembretes (write-back), **duas vias**, com **toggle nas Configurações › Comportamento** ("Sincronizar conclusão com o Lembretes", padrão **ligado**). Port `TaskImporting.setReminderCompleted(reminderID:completed:) async -> Bool` (best-effort: `false` = lembrete apagado/falha, não desfaz a conclusão local). `EventKitReminderImporter`: `store.calendarItem(withIdentifier:)` + `reminder.isCompleted = …` + `store.save(_:commit:true)` (o `requestFullAccessToReminders` já dá escrita). `ManageTasksUseCase.completeTask`/`reopenTask` viraram **async** (única caller é `TasksViewModel.setCompleted`, que passou a rodar em `Task {}`); só escrevem se `source == .reminders` E o toggle (lido por closure `shouldSyncReminderCompletion` injetada, default `false` nos testes) estiver ligado. `update(id:_:)` agora `@discardableResult` retorna a `FocusTask` mutada. `PomodoroConfiguration.syncReminderCompletion: Bool = true` — ganhou **`init(from:)` manual com `decodeIfPresent` em TODOS os campos** (não só o novo): sem isso, JSON antigo sem a chave lançaria e o store resetaria TODA a config para o padrão (mesma armadilha do rename `autoStartNextFocus`). +6 testes no use case, +2 no config coding. `make test` verde (Application 126), `xcodebuild` limpo. ⚠️ Validar à mão: concluir tarefa importada → aparece riscada no Lembretes; reabrir → volta; desligar o toggle → não mexe.

**🔒 FEAT-002 — bloqueio contínuo + senha de desbloqueio de apps (2026-09-29, T-43, ADR-10):**
- Flags `blockAppsWhileRunning`/`blockSitesWhileRunning` (`PomodoroConfiguration`, `decodeIfPresent`) — toggles nas abas Apps/Sites.
- `TomafocoApplication/Blocking/PersistentBlocking.swift`: decoradores `PersistentAppBlocker`/`PersistentWebsiteBlocker` envolvem os blockers reais; Coordinator/Recover recebem os decorados. **Invariante mudou:** fim do foco derruba o bloqueio **salvo flag ligada**. `PersistentBlockingController.refresh()` roda no lançamento (depois da recuperação) e a cada mudança de flag/lista (closures injetadas em `SettingsViewModel`/`BlockListViewModel`). No foco, `refresh` é no-op.
- Senha: `AppLaunchGate` (Domain, puro — Infra não depende da Application) chaveado por **PID**. `WorkspaceAppBlocker` **esconde** o app durante o prompt (loop de 200ms re-esconde e devolve o foco ao Tomafoco), senha certa → `unhide` + `activate` da mesma instância; cancelou → `terminateReliably` (reenvia `terminate()` em 0,5/1/2s). Liberação pendente só se o app fechou durante o prompt. Observer de término vive o tempo todo.
- 🐛 **Bug corrigido (2026-09-29):** a 1ª versão encerrava no `didLaunch` e relançava após a senha — o app recém-lançado ignora `terminate()` enquanto carrega, então fechava tarde (ou não fechava) e nunca reabria. Reproduzido com harness SPM (Calculadora + prompt stub) no scratchpad. **Regra: nunca confiar num único `terminate()` no `didLaunch`.**
- `KeychainAppUnlockPasswordStore` (PBKDF2-SHA256, salt 16B, 100k iter, comparação constante) atrás de `SecretStorage` — testes usam storage em memória, nunca o Keychain real.
- UI: `App/UI/AppUnlock/` — `AppUnlockPromptPresenter` (fila de prompts; `NSApp.activate` + `canBecomeKey`, senão o teclado não chega), `ProtectedActionAuthorizer` (desligar flag/trocar/remover senha pedem senha), `UnlockPasswordViewModel`.
- **Sites casam pelo host completo** (revisão do mesmo dia): `BlockedDomain` não remove mais `www.`; ganhou `host` + `includesSubdomains` (`value` = forma exibida, `*.globo.com` para curinga). `www.globo.com` ≠ `ge.globo.com` ≠ `globo.com`. Codable manual: grava `pattern` (+ `value` = host, para versão anterior ainda ler); JSON antigo só com `value` → **curinga** (antes `globo.com` casava subdomínios — migrar como exato tiraria bloqueio do usuário). Testes do `AppleScriptBrowserBlocker` usam `*.globo.com`.
- Suíte 287 verdes (Domain 74, Application 159, Infra 54); `xcodebuild` limpo. ⚠️ Validar à mão: prompt de senha, relançamento, bloqueio fora do foco, desligar flag com senha.

**🚀 Release 1.10 publicada (2026-09-29)** — `MARKETING_VERSION 1.10` / `CURRENT_PROJECT_VERSION 11`. Conteúdo: FEAT-002 (bloqueio contínuo, senha de desbloqueio de apps, sites por host completo com curinga `*.`) + FEAT-001 (histórico nas tarefas, que estava commitado localmente sem release).
- Notarização `Accepted`, staple ok, `spctl` → `Notarized Developer ID`. DMG 3,9 MB.
- Publicação: DMG + notas + `appcast.xml` em `site/downloads/`, bump nos 5 arquivos do site (regex pegou `1.9` mas não `Tomafoco-1.9.dmg` — conferir com `grep 1\.9` depois do bump), commit + push nos 2 repos, tag `v1.10`. Deploy no ar em ~60s. Verificado ao vivo: `/`, DMG, appcast, `app.js` **200**; DMG servido com o **mesmo SHA-256** do local; notas `.html` **301** (normal no Azure SWA).

## Convenções / gotchas

- Nunca usar `Date()`/`Timer` no Domain/Application — tudo via `SessionClock` (testabilidade).
- Efeitos colaterais saem da máquina como `SessionEffect`; quem executa é o `SessionCoordinator`.
- `HostsFileEditor` recebe o caminho por injeção → testado contra arquivo temporário, sem root.
- Emergência (bloqueio órfão no hosts, de antes do ADR-8): `sudo sed -i '' '/# Tomafoco-START/,/# Tomafoco-END/d' /etc/hosts`
- Bloqueio de sites NÃO usa mais rede: se um site não bloquear, o problema é permissão de Automação do navegador (Ajustes do Sistema › Privacidade › Automação), navegador não suportado (Firefox) ou navegador fechado.
- `xcodegen` instalado via Homebrew (2026-07-22). `swiftlint` ainda NÃO instalado — `make lint` falha.


**🚀 Release 1.11 publicada (2026-09-29)** — `MARKETING_VERSION 1.11` / `CURRENT_PROJECT_VERSION 12`. Conteúdo: bloqueio de sites por caminho.
- `BlockedDomain` ganhou `path: String?` (`www.youtube.com/shorts`); `URLBlockingPolicy` casa por **segmento inteiro** (`/shorts` pega `/shorts` e `/shorts/abc`, nunca `/shortsxyz`, `/feed/shorts` nem o resto do host). Caminho comparado sem distinção de maiúsculas; query/fragmento/porta/barra final descartados. Combina com curinga (`*.youtube.com/shorts`).
- ⚠️ Mudança de comportamento: colar URL completa agora vira bloqueio de caminho (antes `https://reddit.com/r/swift` → `reddit.com`). Listas salvas não mudam. Downgrade: versão anterior lê só `value` (= host) → bloqueia o site inteiro como curinga.
- `make release`: notarização **Accepted** nas duas etapas, `spctl` → `source=Notarized Developer ID`. DMG 3,9 MB.
- Site: bump `1.10`→`1.11` em `index.html`, `404.html`, `privacidade.html`, `assets/js/app.js`; removido "Bloqueio por URL específica" da seção de limitações; card de sites cita `www.youtube.com/shorts`. GitHub deu **500 no push** dos dois repos — retry passou. Verificado ao vivo: `/`, DMG, appcast, `app.js` **200**; SHA-256 do DMG servido = local; notas `.html` **301** (normal).
**📋 Criação de tarefas em lote (RF-09.8 / T-45, 2026-10-01):** colar texto (1 linha = 1 tarefa) →
**Próximo** → grid editável (título, prioridade, tags, vencimento) → **Criar N tarefas**.
- Application: `UseCases/BulkTaskText.swift` — `NewTaskDraft` + `BulkTaskText.parseTitles` (LF/CRLF/CR,
  trima, descarta vazias e marcadores `- `/`* `/`• `/`[ ] `/`[x] `/`1. `/`1) `; "-5 kg" e "3.5 horas" ficam).
  `ManageTasksUseCase.validateNewTasks(_:) -> [Int: DomainError]` (vazio; duplicata contra ATIVA ou linha
  anterior do lote — a 1ª ocorrência é válida) e `addTasks(_:)` **atômico** (um inválido → nada grava;
  um `saveTasks` só; tags vão ao catálogo). +15 testes (`ManageTasksBulkAddTests`, `BulkTaskTextTests`).
- App: `BulkAddTasksViewModel` (sheet via `.sheet(item: $viewModel.bulkAdd)`, observado direto pela
  `BulkAddTasksView`) — revalida a cada mudança de `rows`; Voltar refaz o texto com os títulos do grid e
  Próximo **preserva** prioridade/tags/data das linhas de mesmo título. "Próximo" sem `.defaultAction`
  (Return no `TextEditor` precisa quebrar linha). Grid = `ScrollView` + `LazyVStack` com colunas fixas —
  `Table(Binding)` é macOS 14+.
- Refactor: `priorityName/Color/Glyph` viraram `TaskPriority.displayName/displayColor/glyph` +
  `displayOrder` (`TaskPriorityStyle.swift`); `tagSuggestionsMenu` virou `TagSuggestionsMenu` (View).
  `TasksViewModel.defaultDueDate()` deixou de ser `private`.
- `make test`: **309 verdes** (Domain 81, Application 174, Infra 54); `xcodebuild` limpo.
- ⚠️ Validar à mão: colar lista com vazias e "- " → grid limpo; duplicar título → linha vermelha e
  "Criar" desabilitado; lixeira remove linha; Voltar/Próximo mantém ajustes; Criar → tarefas com campos
  certos, picker do timer atualiza; largura do sheet (800pt) dentro da janela Tarefas (mín. 520).

**⏳ Loading + trava em concluir/apagar tarefa (2026-10-01):** cliques repetidos concluíam/apagavam
tarefas sem querer — a linha some e a de baixo sobe para debaixo do cursor. `TasksViewModel.runRowAction`
centraliza `setCompleted`/`delete`: `busyTaskIDs` (linha troca círculo/lixeira por `ProgressView`) +
trava **global** `isMutatingTask` (todos os botões de concluir/apagar e o "Apagar" do menu de contexto
ficam desabilitados) que dura a ação + `actionCooldown` de 400 ms. Clique durante a trava é ignorado.
Só UI; `xcodebuild` limpo. ⚠️ Validar à mão: clicar várias vezes rápido no círculo/lixeira → só 1 tarefa afetada.

**🚀 Release 1.12 publicada (2026-10-01)** — `MARKETING_VERSION 1.12` / `CURRENT_PROJECT_VERSION 13`.
Conteúdo: criação de tarefas em lote (RF-09.8) + loading/trava em concluir/apagar.
- ⚠️ Primeira tentativa falhou: `notarytool` **403 "A required agreement is missing or has expired"** —
  o Apple Developer Program License Agreement tinha versão nova. Aceite em developer.apple.com e
  levou **~10 min** para o 403 sumir. Sintoma aparece no pré-check do `release.sh` como "credencial
  inválida", mas a credencial está ok — rodar `xcrun notarytool history --keychain-profile tomafoco`
  para ver o erro real.
- Notarização **Accepted** (app e DMG), `spctl` → `Notarized Developer ID`, universal (`x86_64 arm64`), DMG 4,1 MB.
- Site: bump `1.11`→`1.12` nos 4 arquivos (sed `1\.11`), DMG + notas + appcast no mesmo commit. Tag `v1.12`.
  Verificado ao vivo: `/`, DMG, appcast (`sparkle:version 13`), `app.js` **200**; SHA-256 do DMG servido = local.

**🔁 Tarefas diárias (FEAT-004 / RF-09.9 + RF-10.4 / T-46, 2026-10-27):** toggle "Repetir diariamente".
Concluir uma diária **não fecha a tarefa**: ela continua ativa, o vencimento pula para **amanhã** e a
conclusão de hoje é registrada no histórico ("Concluída em dd/MM/yyyy") e no `completionLog`.
- **Decisões do usuário (não rediscutir):** mesma tarefa (mesmo `id`, foco acumula), todo dia (sem dias da
  semana), vale também para tarefa do Lembretes, e **volta na mesma hora** com vencimento no dia seguinte
  (1ª versão reabria na virada do dia com `DailyTaskScheduler` — descartada no mesmo dia, não há mais
  observer de meia-noite).
- Domain: `FocusTask.repeatsDaily` + `completionLog: [Date]` (decode `decodeIfPresent ?? false/[]`,
  regressão em `TaskLinkCodingTests`); pura `nextDailyDueDate(now:calendar:)` = amanhã no horário do
  vencimento atual, ou 23:59 sem vencimento (não fica atrasada antes do dia acabar).
- Application: `ManageTasksUseCase` ganhou `calendar` (default `.current`; container passa
  `.autoupdatingCurrent`). `completeTask` de diária: log + entrada de histórico + vencimento, e devolve
  `.notApplicable` — **não espelha no Lembretes** (localmente segue aberta, o lembrete também).
  `CompletedTaskOccurrence` (log ∪ `completedAt`) → relatório e CSV com 1 linha por conclusão; id composto
  porque `ForEach` quebraria com a mesma tarefa repetida.
- App: toggle no `editSheet` (dentro do `Form`) e no menu de contexto, badge `repeat` "Diária"; concluir
  diária mostra feedback "concluída hoje — volta com vencimento amanhã" (senão o clique parece não fazer nada).
- **Sem desfazer:** clicar de novo no mesmo dia registra outra conclusão; apagar a entrada do histórico não
  mexe no log nem no vencimento.
- `make test` **325 verdes** (Domain 86, Application 185, Infra 54); `xcodebuild` limpo.
- ⚠️ Validar à mão: concluir diária → continua na lista, vencimento amanhã, entrada no histórico, aviso na
  tela; relatórios/CSV com uma linha por dia.
- **Formulário de edição maior (2026-10-27):** sheet 420pt → **560×680**; `Form` com
  `.fixedSize(vertical)` (altura do conteúdo) e o histórico ocupa a sobra numa `ScrollView` com borda
  (`minHeight 120`, `maxHeight .infinity`) — antes era `maxHeight: 140` e só aparecia com entradas.
  ⚠️ Validar à mão: campos do `Form` sem corte e histórico longo rolando sem empurrar Cancelar/Salvar.

**🔁 Diária revisada: concluir FECHA e CLONA (2026-10-27, pós-1.14).** Pedido do usuário: "ao finalizar,
gerar um clone da tarefa com a data do dia seguinte e não reabrir a tarefa". **Substitui** a decisão
"mesma tarefa, mesmo `id`" acima — não voltar a ela.
- Domain: `FocusTask.nextDailyOccurrence(id:now:calendar:)` (puro, testado): tarefa nova com
  título/tags/nota/link/prioridade/urgência/`parentID`/`source`+`reminderID`; `createdAt = now`;
  **sem** histórico, `completionLog` e raia; vencimento = `nextDailyDueDate`. (Chegou a copiar
  `createdAt` + histórico por pedido do usuário no mesmo dia — **cancelado por ele em seguida**;
  não voltar a copiar.) `completionLog` virou
  **legado** (ninguém grava; `CompletedTaskOccurrence` ainda lê para não perder conclusões antigas).
- Application: `applyCompletionCascade` fecha a tarefa (e filhas abertas) e **acrescenta o clone na
  mesma lista** → 1 gravação, tanto em `completeTask` quanto em `ManageKanbanUseCase.moveTask`.
  `applyCompletion(to:)` e o `dailyCompletionFormatter` foram removidos. **Filha diária fechada
  pela cascata do pai NÃO clona** (clone ativo sem pai ativo violaria a invariante da FEAT-003).
  `syncCompletion` passou a espelhar a diária no Lembretes (ela fecha de verdade); o clone leva o
  `reminderID`, então o picker segue mostrando o lembrete como importado.
- Kanban: a concluída **mantém o `laneID`** como qualquer outra (saiu o `laneID = nil` da diária);
  o clone nasce sem raia → 1ª raia.
- App: feedbacks "concluída — nova cópia criada com vencimento amanhã" (lista) e "…na primeira raia,
  com vencimento amanhã" (Kanban); tooltip do badge "Diária" sem contagem do log.
- Edge aceito: reabrir a diária concluída à mão deixa duas ativas com o mesmo título (reopen não
  checa duplicata) — o usuário pediu "não reabrir", a reabertura manual continua sendo escolha dele.
- `make test` **456 verdes** (Domain 141, Application 258, Infra 57); `xcodebuild` limpo.
- ⚠️ Validar à mão: concluir diária na lista → some das ativas + cópia com vencimento amanhã (mesma
  hora) + aviso; Kanban → cartão na Done e cópia na 1ª raia; diária do Lembretes → riscada lá; pai
  diário com filhas → filhas fecham, cópia sem filhas; relatório "Hoje" lista a concluída.

**📅 Datas só leitura no formulário da tarefa (2026-10-27, pós-1.14):** `TaskEditorSheet.draftForm`
ganhou "Data de cadastro" (`createdAt`) e "Data de encerramento" (`completedAt`, "—" quando aberta)
como `LabeledContent` no fim do `Form`. `TaskEditorViewModel.createdAtText`/`completedAtText` lêem
da `task` como foi aberta — concluir/reabrir acontece fora do sheet, então não há o que atualizar.
Fora do rascunho (não entram no `save()`). Só App/, `xcodebuild` limpo. ⚠️ Validar à mão: tarefa
aberta mostra "—"; concluída mostra data/hora; texto selecionável.

**🔁 Botão "Tarefas" na janela Kanban (2026-10-27, pós-1.14):** espelho do botão "Kanban" da janela
Tarefas — `KanbanBoardView` ganhou `@Environment(\.openWindow)` e botão `Label("Tarefas",
systemImage: "checklist")` antes de "Configurar quadro…" na barra (`openWindow(id: "tasks")` +
`NSApp.activate`). Só App/, `xcodebuild` limpo. ⚠️ Validar à mão: abre/traz a janela Tarefas à
frente, inclusive com o Kanban em tela cheia.

**🗂️ Kanban (FEAT-005 / RF-09.10–12 / T-47, 2026-10-27):** janela própria `Window("kanban")` (tela cheia
via `.allowsFullScreen()` — liga `.fullScreenPrimary` na `NSWindow`, necessário em app `LSUIElement`),
aberta por ⌥⌘K (menu Janela), engrenagem do popover e botão na janela Tarefas. Plano completo e desvios
em `../DOCS - Tomafoco/APP/Features/FEAT-005 Criar um Kanban.md`.
- Domain: `KanbanBoard` (raias + `doneRetentionDays` 1–90 + `taskScope`; invariantes reparadas no init/
  decode: 1 Done no fim, ≥1 aberta), `KanbanLane`, `KanbanTaskScope` (`all`/`tags([])` explícito — tags
  vazias = quadro vazio, nunca "todas"), `TaskDueFilter`, `FocusTask.laneID` (`decodeIfPresent`).
  **Raia é derivada** (`lane(for:)`): concluída → Done, senão `laneID` válido, senão 1ª raia.
- Application: `ManageKanbanUseCase.moveTask` reusa `completeTask`/`reopenTask` (sync Lembretes, diária)
  + histórico "Movida: A → B"; concluída mantém `laneID` (reabrir pela lista volta à raia). Diária na Done
  volta à 1ª raia. `ManageTasksUseCase.update` virou `internal`; `renameTag`/`deleteTag` reescrevem o
  escopo via `kanbanBoards` opcional (best-effort, `os.Logger`). `TaskFilter` puro (lista + quadro).
- Infra: `FileKanbanStore` (`kanban.json` + `.bak`).
- App: `KanbanViewModel`/`KanbanBoardView` (drag `.draggable(uuidString)` + `.dropDestination`, "Mover
  para ▸" acessível, colunas 260–360pt); aba **Kanban** nas Configurações (`KanbanSettingsViewModel`/
  `KanbanSettingsTab`; `SettingsTab` em `@AppStorage("settingsTab")` — "Configurar quadro…" abre já na aba
  via `SettingsLink` + `simultaneousGesture`). Editor extraído para `TaskEditorViewModel`/`TaskEditorSheet`
  (lista e quadro); `TaskSortOrder`, `TagChip`, `TaskRowActionRunning` (trava de cliques) compartilhados.
- **Sincronia entre janelas — regra:** `reload()` = relê + avisa; `refresh()` = só relê. `TaskChangeRelay`
  chama `refresh()` nos outros, e **só se a tela está visível** (`isPresented`, via `didAppear`/
  `didDisappear`) — VM de janela fechada não lê disco; relê sozinho ao aparecer. Chamar `reload()` a
  partir do relay criaria laço entre janelas.
- **Code review + 9 correções (mesmo dia):** `deleteLane` atômico e contando por `lane(for:)` (tarefas
  sem `laneID` na 1ª raia); `moveTask` em 1 leitura/1 gravação (`applyCompletion`/`applyReopen`/
  `syncCompletion` internos no `ManageTasksUseCase`); `handleDrop` recusa durante trava; criar pelo quadro
  exige tag do escopo; decode tolera raia malformada (`LenientLane`); `makeID` injetado no reparo;
  `OpenSettingsControl(tab:)` compartilhado (popover + quadro). Lista completa no FEAT-005 ("Correções do
  code review").

**📝 Nota, link e urgente na tarefa (RF-09.13 / T-48, 2026-10-27):**
- **Reaproveita `FocusTask.notes` e `sourceURL`** (antes só leitura, vindos do Lembretes) — agora editáveis
  no formulário; sem migração, dado importado continua aparecendo. Reverte a decisão de 2026-09-29 que tirou
  "Observação" do formulário: o usuário pediu nota de volta, junto com link. **Não** escreve de volta no
  lembrete (write-back segue só de conclusão).
- `FocusTask.isUrgent` (`decodeIfPresent ?? false`); `normalizeNotes` (trim, vazio → `nil`) e
  `normalizeLink` (trim, vazio → `nil`, sem `://` ganha `https://`, sem host lança
  `DomainError.invalidLink`). Esquema custom (`notion://`) passa.
- `ManageTasksUseCase`: novo `TaskEdit` + `editTask(id:_:)` (transação completa). **A forma curta
  `editTask(id:title:tags:dueDate:priority:repeatsDaily:)` continua e virou edição PARCIAL** (carrega a
  tarefa e preserva nota/link/urgente) — os ~13 testes que a usam seguem válidos. `setUrgent(id:_:)`.
- App: `TaskEditorViewModel` (`notes`/`link`/`isUrgent`, `linkURL` para o botão "Abrir"; `invalidLink` vira
  feedback no sheet, que cresceu para 560×760); `TaskEditorSheet` com Toggle Urgente, campo Link + abrir e
  `TextField(axis: .vertical)` para a nota. `UrgentBadge` (em `TagChip.swift`), `FocusTask.showsUrgent`
  (só aberta) e `linkURL` em `TaskSortOrder.swift`. **`TaskSortOrder.areInIncreasingOrder` põe urgente
  no topo em qualquer critério** (lista e raias abertas; Done ordena por conclusão). Linha: barra vermelha
  à esquerda + fundo `danger 8%` + selo; cartão: borda 2pt + fundo `danger 10%` + selo + nota (3 linhas).
  Menus de contexto (lista e cartão): Toggle Urgente + "Abrir link".
- Gotcha: `.textContentType(.URL)` é macOS 14+ — não usar (deployment 13).
- `make test` **393 verdes** (Domain 123, Application 213, Infra 57); `xcodebuild` limpo.
- ⚠️ Validar à mão: editar nota multilinha (Return quebra linha, não salva); link `globo.com` → chip
  "globo.com" abre o site; link inválido → erro e sheet aberto; Urgente → selo/fundo na lista e no
  cartão, sobe ao topo, some ao concluir; tarefa importada com notas/URL mostra os valores no formulário.
- `make test` **384 verdes** (Domain 119, Application 208, Infra 57); `xcodebuild` limpo.
- ⚠️ Validar à mão: arrastar entre raias (histórico), Done conclui/espelha Lembretes e reabre ao tirar;
  diária na Done; tela cheia + Split View com Tarefas; fechar o Kanban em tela cheia volta ao modo
  só-barra; app não abre o Kanban sozinho; dias no Done = 1; escopo por tag + nova tarefa no quadro;
  renomear/apagar tag com escopo; apagar raia com tarefas (confirmação); lista: refactor do formulário de
  edição sem mudança de comportamento (Return no histórico, Cancelar/Salvar).

**🌳 Subtarefas (FEAT-003 / RF-09.14 / T-49, 2026-10-27):** subtarefa **é uma `FocusTask` com
`parentID`**, um nível só. Plano, decisões e histórico em
`../DOCS - Tomafoco/APP/Features/FEAT-003 Possibilitar a criação de subtarefas.md`.
- **Decisões do usuário (não rediscutir):** subtarefa é tarefa completa (tags, prioridade, data, foco,
  histórico…) com pai; autorrelacionamento de **um nível** (filha de filha é recusada); lista
  **aninhada** (linha completa indentada); entra no **timer** e nos **relatórios com soma no pai**;
  **cartão próprio** no Kanban (chip "↳ Pai", move sozinha, herda escopo por tag do pai); **cascata**:
  concluir pai fecha filhas abertas, reabrir não reabre, fechar todas não fecha o pai, apagar pai
  apaga filhas (lista confirma).
- ⚠️ **A 1ª versão do dia (checklist embutido `FocusTask.subtasks: [Subtask]`) foi removida inteira**
  antes de commitar — não procurar `Subtask`, `emptySubtaskTitle`, `renameSubtask`, `moveSubtask`.
- Domain: `FocusTask.parentID` (`decodeIfPresent`) + `isSubtask`; **`TaskTree`** (puro):
  `topLevel`/`children`/`parent`/`progress`/`displayTitle` ("Pai › Filha")/`grouped`;
  `DomainError.parentTaskNotFound`/`subtaskNestingNotAllowed`; `KanbanBoard.columns` deixa a filha
  herdar o escopo do pai.
- Application: `addSubtask(parentID:title:tags:)` (herda `laneID` do pai; tags no catálogo).
  **Unicidade de título é por irmãs ativas** (`hasActiveSibling`: topo×topo, filhas do mesmo pai) —
  `addTask`, `validateNewTasks` e `editTask` mudaram para isso. **`applyCompletionCascade(id:in:)`**
  (sem I/O) usado por `completeTask` e por `ManageKanbanUseCase.moveTask` (que agora carrega
  `allTasks` e grava com `replaceAll` — segue 1 leitura/1 gravação, teste `gravaTarefasUmaVezSo`).
  `deleteTask` em cascata. `TaskFilter.matchesTree`/`matchesCard`. `ReportBuilder.taskTotals` soma a
  filha no pai (cria a linha do pai mesmo sem foco direto).
- App: `TaskEditorViewModel` lê `allTasks()` no init para `subtasks`/`parentTitle`; `toggleSubtask`
  é async (`completeTask`/`reopenTask`, `busySubtaskIDs`); `openSubtask` → `onOpenTask` (a janela
  troca o `editor` — `.sheet(item:)` fecha um e abre o outro). `TaskEditorField` = `history`/`newSubtask`;
  Salvar perde `.defaultAction` com qualquer um focado. Lista: `displayedTasks` só de topo
  (`matchesTree`), `children(of:)`, `isExpanded` abre sozinho quando filtro casa filha, `row(_:depth:)`,
  `pendingDeletion` + `confirmationDialog`. Kanban: `matchesCard`, chip/badge, menu "Adicionar
  subtarefa…" só no pai (abre o formulário do pai — a criação é lá). Timer: `availableTasks =
  TaskTree.grouped(...)`, `displayTitle(of:)` no seletor e no anel.
- Gotcha: `.strikethrough` como modificador de `View` é macOS 13.3+ — em `Text` ok, no `TextField`
  não usar (deployment 13.0).
- **Sheet reorganizado em header / body / footer (mesmo dia):** header fixo (título + "↳ Pai"),
  **body é a única `ScrollView`** (`draftForm` com `fixedSize` vertical + subtarefas + histórico, sem
  `ScrollView` nas seções), footer fixo com erro + Cancelar/Salvar. Substitui a nota "Formulário de
  edição maior" da FEAT-004. Sheet 560×760. Função interna chama `scrollBody` — `body(focused:)`
  colide com `var body` da `View`.
- `make test` **419 verdes** (Domain 130, Application 232, Infra 57); `xcodebuild` limpo.
- ✅ Validado à mão pelo usuário em 2026-10-27 (itens 1–7 da FEAT-003): criar filha por Return e
  pelo menu; editor da filha; linha aninhada conclui/edita/apaga; cascata de concluir/reabrir/apagar;
  Kanban (cartão próprio, pai → Done leva as filhas, escopo herdado); seletor e relatório; busca pela
  filha abre o pai; `tasks.json` antigo abre sem `.bak`.

**🎯 Seletor do foco: ícone na subtarefa + escopo por tag (RF-09.15 / T-50, 2026-10-27, mesmo dia):**
- Pedido: no menu do seletor a filha só tinha o título → agora ícone `arrow.turn.down.right` + título
  próprio (ela já vem logo abaixo do pai); botão do seletor e anel seguem "Pai › Filha"
  (`TimerViewModel.menuTitle(of:)` vs `displayTitle(of:)`). Para ter ícone **e** marca de seleção, os
  itens do `Menu` viraram **`Toggle`** (checkmark nativo do NSMenu) em vez de `Button`+`Label("checkmark")`.
- **`KanbanTaskScope` → `TaskScope`** (Domain, arquivo renomeado; docs antigos da FEAT-005 citam o nome
  velho). Ganhou `includes(_:in:)` (filha herda escopo do pai) — `KanbanBoard.columns` e o timer usam.
- `PomodoroConfiguration.focusTaskScope: TaskScope` (`decodeIfPresent`, default `.all`, independente do
  escopo do quadro). `ManageTasksUseCase(settings:)` opcional: `renameTag`/`deleteTag` → `updateScopes`
  (quadro + foco). `AppContainer` passa `settings` ao use case e `manageTasks` ao `SettingsViewModel`.
- `SettingsViewModel`: `focusTaskScope`/`knownTags`/`isPresented`/`reloadFocusScope()` (o
  `TaskChangeRelay` ganhou `focusSettings`), `setFocusScopeByTag`/`setFocusTag` → `save()` +
  `onFocusScopeChanged` (→ `timer.reloadAvailableTasks()`). `SettingsView.focusScopeSection` ("Tarefas no
  foco", aba Pomodoro, cópia da seção do Kanban). `TimerViewModel.reloadAvailableTasks` filtra pelo
  escopo mas **mantém a tarefa da sessão corrente** (seletor do pausado); `activeSnapshot` resolve
  "Pai › Filha" com o pai fora do escopo.
- `make test` **424 verdes** (Domain 133, Application 234, Infra 57); `xcodebuild` limpo.
- ⚠️ Validar à mão: menu do seletor mostra ↳ na filha e checkmark no item marcado (ocioso e pausado;
  modo único e múltiplo); "Sem tarefa" limpa; Configurações › Pomodoro › "Tarefas no foco": marcar tag
  filtra o seletor na hora, sem tag → aviso e seletor vazio, renomear/apagar tag na lista reflete nas
  caixas com a aba aberta; filha sem tag entra pelo pai; pausar com tarefa fora do escopo mantém ela no
  seletor; config antiga abre em "Todas".

**🔍 Code review do dia + 10 correções (2026-10-27, noite):** revisão de tudo que estava não
commitado (FEAT-005, T-48, FEAT-003, T-50). `make test` **437 verdes** (Domain 138, Application 242,
Infra 57); `xcodebuild` limpo. Lista também no FEAT-003 ("Histórico de decisões").
- 🔴 **Link importado corrompido ao salvar:** `editTask` renormalizava `sourceURL` mesmo sem mudar —
  `mailto:x` virava `https://mailto:x`, `file://` (sem host) impedia salvar qualquer campo. Agora
  `applyEdit` só normaliza/valida quando `edit.link != current.sourceURL`; `TaskEditorViewModel.linkURL`
  segue a mesma regra. Forma curta e completa de `editTask` passaram a **1 leitura/1 gravação**
  (`applyEdit(_:at:in:)` privado; `update(id:)` não é mais usado na edição).
- 🔴 **Filha sumia do Kanban ao buscar pelo nome:** herança de escopo era avaliada sobre a lista já
  filtrada pela barra. `KanbanBoard.columns(for:among:now:calendar:)` procura o pai em `among`
  (lista cheia); a sobrecarga antiga delega com `among: tasks`. Aviso "saiu do quadro" usa
  `includes(_:in:)`.
- 🔴 **`SettingsViewModel.save()` clobberava o escopo do foco:** montava a config do zero com a cópia
  em memória (só relida com a aba visível), desfazendo o que `renameTag`/`deleteTag` gravaram. Agora
  `save()` carrega a config gravada e sobrescreve só os campos da VM; `focusTaskScope` é gravado
  apenas por `applyFocusScope`. **Regra: campo da config que outra camada também escreve não entra
  no `save()` genérico.**
- **Invariante "subtarefa ativa ⇒ pai ativo"** (decisão 6 da FEAT-003): `addSubtask` em pai concluído
  e `reopenTask` de filha reabrem o pai (`applyReopenCascade`, 1 gravação; espelha os dois no
  Lembretes, `.failed` se qualquer um falhar). `ManageKanbanUseCase.moveTask` saindo da Done idem.
- **Relatório dobrava tempo:** roll-up da filha no pai era por total; pai + filha na mesma sessão
  multi-tarefa dava 2× ao pai. Agora por registro (`keys` ganha o pai uma vez por sessão).
- **Editor: falha na subtarefa pendente deixava janelas stale:** `save()` grava rascunho → histórico →
  subtarefa, com `onChanged()` em `defer` quando algo gravou e mensagem específica ("Rascunho salvo.
  Já existe uma subtarefa…").
- **Lista O(n²):** `activeChildren`/`completedChildren` (`[UUID: [FocusTask]]`) montados no `refresh()`;
  `displayedTasks`, `children(of:)`, `isExpanded`, `subtaskProgress` leem do índice.
- **Duplicação das abas de escopo:** `TaskScope` ganhou `isByTag`, `contains`, `selectableTags(knownTags:)`,
  `settingTag(_:selected:)`, `switchingByTag` (Domain, testados); `SettingsViewModel` e
  `KanbanSettingsViewModel` viraram wrappers de 1 linha.
- ⚠️ Validar à mão: tarefa do Lembretes com `mailto:` — editar só o título mantém o link; buscar
  pelo nome da filha no Kanban mantém o cartão; renomear tag com Configurações fechadas e depois
  mexer num toggle da aba Sites não zera "Tarefas no foco"; arrastar filha da Done para "A fazer"
  reabre o pai; relatório com pai + filha na mesma sessão.
