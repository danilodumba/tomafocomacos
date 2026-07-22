# CLAUDE.md — Memória do projeto Tomafoco

App de Pomodoro para macOS que bloqueia sites e apps distrativos durante o foco.
Este arquivo registra o contexto e **onde o trabalho parou** para retomar em sessões futuras.

## Contexto do projeto

- **Local no disco:** `/Volumes/danilo_ssd/Projetos/ds.focus`
- **Plataforma/stack:** macOS 13+, Swift 5.9 / SwiftUI, universal binary
- **Distribuição:** FORA da Mac App Store (Developer ID, assinado + notarizado). Sandbox desligado.
- **Decisões-chave (ADRs em `docs/arquitetura.md`):**
  - Bloqueio de sites: edição idempotente do `/etc/hosts` (MVP). NetworkExtension fica para v3.
  - Privilégio: `AppleScriptPrivilegeRunner` (prompt admin) no MVP; XPC helper (`SMAppService`) na v2 — trocável só no Composition Root.
  - Bloqueio de apps: `NSWorkspace` encerra + observa relançamentos.
  - Estado com término absoluto (`endsAt`) para sobreviver a crash/sleep/reboot.

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
- ✅ Application: `SessionStateMachine` pura, `SessionCoordinator`, `HardcoreCancelPolicy`, `RecoverFromCrashUseCase`, `ManageBlockListUseCase` + testes de tabela
- ✅ Infrastructure: `HostsFileEditor` (lógica idempotente RNF-01, testada), `HostsFileWebsiteBlocker`, `WorkspaceAppBlocker`, `AppleScriptPrivilegeRunner`, `DispatchSessionClock`, `FileSessionSnapshotStore`, `UserDefaultsSettingsStore`, `UNNotificationAdapter`
- ✅ App: `TomafocoApp`, `AppContainer`, `TimerViewModel`/`MainView`, `MenuBarView`, `SettingsView`/`SettingsViewModel`, `BlockListViewModel`
- ✅ Tooling: `project.yml` (XcodeGen), `App/Resources/Tomafoco.entitlements`, `.swiftlint.yml`, `Makefile`, `.gitignore`, `README.md`
- 52 arquivos Swift; chaves/parênteses balanceados.

**✅ Build/testes validados no Mac (2026-07-22, Swift 6.3.2):**
- `make test` → 51/51 testes verdes (Domain 19, Application 21, Infrastructure 11)
- `xcodegen generate` + `xcodebuild -scheme Tomafoco` → **BUILD SUCCEEDED**, zero warnings de código
- Correções aplicadas nessa validação:
  - `HardcoreCancelPolicyTests`: `Result<Void, DomainError>` não é `Equatable` → asserts trocados por helpers `assertSuccess`/`assertFailure`
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
- Renomeação completa `DSFocus*`/`ds.focus` → `Tomafoco*`: módulos SPM, pastas, `TomafocoApp.swift`, entitlements, bundle ID `com.dsdumba.tomafoco`, marcador do `/etc/hosts` (`# Tomafoco-START/END`), pasta em Application Support, docs. **A pasta do projeto no disco continua `ds.focus`** (renomear é opcional: `mv ds.focus Tomafoco`).
- Design system em `App/UI/DesignSystem/`:
  - `Brand.swift` — paleta DDS.TEC extraída dos SVGs oficiais (cyan `#17B9EB`, navy `#08143E`, cyan claro `#94DCF2`, cyan escuro `#0D6985`) + tokens adaptativos claro/escuro via `NSColor` dinâmico (`Color.adaptive`), então nenhuma View lê `colorScheme`.
  - `Components.swift` — `ProgressRing`, `PrimaryCircleButton`, `GhostControl`, `BrandCard`.
- `MainView` refeita: cabeçalho com fase + menu "•••", anel de progresso com tempo ao centro, rodapé RESET / play-pause / SKIP. Janela 340×480, `.hiddenTitleBar`. `MenuBarView` no mesmo idioma visual.
- **Novo evento `skipBreak` na máquina pura** (RF-04.2): pula intervalo (running ou pausado), grava `SessionRecord.Outcome.skipped` com `endedAt = now`; no-op durante foco/idle/awaiting. Fim de intervalo natural e pulado compartilham o helper `endBreak`. 8 testes novos.
- `TimerViewModel` ganhou `progress`, `phase`, `canSkip`, `skip()`.
- App icon gerado em `App/Resources/Assets.xcassets/AppIcon.appiconset` (squircle navy + símbolo DDS branco + anel cyan). Script de geração: `scratchpad/makeicon.swift` (não versionado — regerar se quiser ajustar).
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

## Como retomar

```bash
cd /Volumes/danilo_ssd/Projetos/ds.focus
make test     # roda testes dos pacotes SPM (Domain/Application/Infra)
make open     # gera Tomafoco.xcodeproj via XcodeGen e abre no Xcode
```

Pré-requisitos: `brew install xcodegen` (e opcional `brew install swiftlint`). O `.xcodeproj` não é versionado — `project.yml` é a fonte da verdade.

## Próximas tarefas (backlog em docs/tarefas.md)

1. ~~Validar build/testes reais no Mac~~ ✅ feito em 2026-07-22.
2. ~~T-20 — UI de adicionar apps via `NSOpenPanel`~~ ✅ feito em 2026-07-22 (falta smoke test manual).
3. ~~Validar T-20 e ADR-8 à mão~~ ✅ feito em 2026-07-22 — bloqueio de sites confirmado funcionando.
4. ~~T-21 — fluxo de "retomar" pós-crash~~ ✅ feito em 2026-07-22: evento puro `adoptRecovered` (só a partir de ocioso, preserva `endsAt`, não bloqueia se a fase for intervalo) + `SessionCoordinator.adoptRecoveredSession` + diálogo com "Retomar"/"Encerrar e liberar" mostrando fase/ciclo/restante.
5. **T-12** — validação manual do bloqueio de apps (app fecha < 2s). T-13 (hosts) está suspenso pelo ADR-8.
6. ~~T-25 — assinatura, notarização e DMG~~ ✅ feito em 2026-07-22. `make release` gera `build/Tomafoco-1.0.dmg` assinado, notarizado (`Accepted`) e grampeado. Certificado *Developer ID Application: Danilo Dumba (CJQ7T4KV7H)*, válido até 2027-02-01. Credencial de notarização: perfil `tomafoco` no chaveiro, via chave de API do App Store Connect (Apple ID + senha de app dava 401).
7. ~~`git init`~~ ✅ feito em 2026-07-22 (branch `main`, commit inicial `d374955`).
8. ~~Decidir o destino do código parado~~ ✅ removido em 2026-07-22.

## Convenções / gotchas

- Nunca usar `Date()`/`Timer` no Domain/Application — tudo via `SessionClock` (testabilidade).
- Efeitos colaterais saem da máquina como `SessionEffect`; quem executa é o `SessionCoordinator`.
- `HostsFileEditor` recebe o caminho por injeção → testado contra arquivo temporário, sem root.
- Emergência (bloqueio órfão no hosts, de antes do ADR-8): `sudo sed -i '' '/# Tomafoco-START/,/# Tomafoco-END/d' /etc/hosts`
- Bloqueio de sites NÃO usa mais rede: se um site não bloquear, o problema é permissão de Automação do navegador (Ajustes do Sistema › Privacidade › Automação), navegador não suportado (Firefox) ou navegador fechado.
- `xcodegen` instalado via Homebrew (2026-07-22). `swiftlint` ainda NÃO instalado — `make lint` falha.
