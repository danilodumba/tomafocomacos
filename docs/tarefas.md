# Tomafoco — Backlog de Tarefas

**Versão:** 1.0
**Data:** 2026-07-22
**Referências:** `especificacao.md` (RF/RNF/UC), `arquitetura.md` (camadas e ports)

Convenções: tarefas numeradas `T-XX`, agrupadas por épico. Cada tarefa lista **dependências** e **critérios de aceite (CA)**. Estimativas em tamanho relativo: P (≤ meio dia), M (1–2 dias), G (3+ dias).

---

## Épico 0 — Fundação do projeto

### T-01 — Criar solução Xcode + pacotes SPM por camada `[P]`
- Criar `Tomafoco.xcodeproj` (target macOS 13+, universal binary) e os pacotes locais `TomafocoDomain`, `TomafocoApplication`, `TomafocoInfrastructure` conforme a estrutura da arquitetura (§10).
- Configurar dependências entre pacotes: Application → Domain; Infrastructure → Domain; App → todos.
- **Dependências:** —
- **CA:** projeto compila vazio; `TomafocoDomain` **não** consegue importar AppKit (verificado por tentativa de import falhando).

### T-02 — Configurar targets de teste + CI local `[P]`
- Targets de teste espelhando os pacotes; pacote `TomafocoTestSupport` para fakes compartilhados (`FakeClock`, `InMemorySessionRepository`, `SpyAppBlocker`, `SpyWebsiteBlocker`).
- Script `make test` / esquema Xcode rodando todos os testes.
- **Dependências:** T-01
- **CA:** `xcodebuild test` verde com um teste placeholder por pacote.

### T-03 — Definir convenções de código `[P]`
- SwiftLint/SwiftFormat com regras alinhadas às convenções Clean Code do §8 da arquitetura (tamanho de função, nomes, sem force-unwrap em produção).
- **Dependências:** T-01
- **CA:** lint roda no build; violação quebra o build local.

---

## Épico 1 — Domain (núcleo puro)

### T-04 — Modelar entidades e value objects `[M]`
- `SessionPhase`, `PomodoroSession` (com `endsAt` absoluto — ADR-6), `BlockedDomain` (validação/normalização), `BlockedApp`, `BlockList`, `PomodoroConfiguration`, `DomainError`, `SessionRecord`.
- **Dependências:** T-01
- **CA (RF-01.5, UC-05):** testes unitários cobrindo: normalização de domínio (`HTTPS://WWW.Twitter.com/feed` → `twitter.com`), rejeição de domínio inválido, `isExpired`, igualdade/Codable de todos os tipos. Cobertura ~100% do pacote.

### T-05 — Definir ports (protocolos) `[P]`
- `AppBlocking`, `WebsiteBlocking`, `SessionClock`/`ClockSubscription`, `SessionRepository`, `SettingsRepository`, `UserNotifying`, `PrivilegeEscalating` — com contratos de idempotência documentados (RNF-01).
- **Dependências:** T-04
- **CA:** fakes de todos os ports implementados em `TomafocoTestSupport` (LSP verificável).

---

## Épico 2 — Application (casos de uso e máquina de estados)

### T-06 — Implementar `SessionStateMachine` pura `[M]`
- Função `(estado, evento, config, now) → (novoEstado, [Efeito])` cobrindo: start, tick, expiração de foco, transição para break curto/longo (contagem de ciclos — RF-01.3), fim de break com/sem auto-início (RF-01.4), pausa/retomada, cancelamento.
- **Dependências:** T-04
- **CA:** suíte de testes por tabela cobrindo todas as transições, incluindo casos-limite (tick após expiração, pausa durante break, ciclo 4 → long break). Cobertura ≥ 90%.

### T-07 — `StartFocusSessionUseCase` `[M]` (UC-01)
- Ativar app blocking, ativar website blocking (falha vira `Outcome.websiteBlockFailed` — fluxo 3a), persistir failsafe **antes** de retornar.
- **Dependências:** T-05, T-06
- **CA:** testes com spies verificando ordem de efeitos; falha de privilégio não impede a sessão; failsafe salvo em todos os caminhos.

### T-08 — `CompleteSessionUseCase` + `AdvancePhaseUseCase` `[M]` (UC-02)
- Desativar bloqueios, limpar failsafe, gravar histórico, decidir próxima fase.
- **Dependências:** T-07
- **CA:** com fakes, hosts "restaurado" e observer removido em conclusão normal; histórico recebe registro `completed`.

### T-09 — `CancelSessionUseCase` `[M]` (UC-03)
- Cancelar desativa bloqueios e grava o registro. ~~Regras do modo hardcore~~ — removidas em 2026-08-03 (ver RF-06).
- **Dependências:** T-07
- **CA:** `test_cancel_desativaBloqueioEVoltaParaIdle`; cancelamento desativa bloqueios e grava `cancelled`.

### T-10 — `RecoverFromCrashUseCase` `[M]` (UC-04, RNF-02)
- Ler sessão ativa persistida; expirada → restaurar tudo e limpar; vigente → devolver decisão para a UI (retomar/encerrar).
- **Dependências:** T-08
- **CA:** três cenários testados (sem sessão, expirada, vigente); nenhum caminho deixa bloqueio ativo sem sessão correspondente.

### T-11 — `ManageBlockListUseCase` `[P]` (UC-05)
- CRUD com validação/normalização; política "aplicar no próximo ciclo" para alterações durante sessão ativa (RF-05.2).
- **Dependências:** T-04
- **CA:** duplicatas rejeitadas; domínio inválido retorna `DomainError.invalidDomain`.

---

## Épico 3 — Infrastructure (adapters macOS)

### T-12 — `WorkspaceAppBlocker` `[M]` (RF-03)
- Encerrar apps em execução da lista; observer de `didLaunchApplicationNotification`; `terminate()` padrão com `forceTerminate()` opt-in; emitir evento para notificação.
- **Dependências:** T-05
- **CA (UC-01):** teste manual roteirizado: app bloqueado fecha em < 2 s após abertura; observer removido em `deactivate()` (verificado por teste de unidade com notificação simulada onde possível).

### T-13 — `HostsFileWebsiteBlocker` `[G]` (RF-02, RNF-01) ⚠️ tarefa mais crítica
- Bloco delimitado `# Tomafoco-START/END`; **caminho do hosts injetado** (testável contra arquivo temporário); idempotência de activate/deactivate; backup `.tomafoco.bak`; flush de DNS.
- **Dependências:** T-05
- **CA:** suíte de integração contra arquivo temporário: activate 2× não duplica; deactivate sem bloco é no-op; conteúdo original preservado byte a byte após ciclo completo; hosts com o bloco no meio (edição externa) é limpo corretamente; arquivo sem newline final não corrompe.

### T-14 — `AppleScriptPrivilegeRunner` `[M]` (RF-02.4, ADR-4)
- `NSAppleScript` com `with administrator privileges`; escaping seguro do conteúdo; mapeamento de erros (usuário cancelou vs. falha real).
- **Dependências:** T-05
- **CA:** cancelamento do prompt vira erro tipado distinguível (necessário para o fluxo 3a do UC-01).

### T-15 — `DispatchSessionClock` + `FileSessionSnapshotStore` + `UserDefaultsSettingsStore` `[M]`
- Clock com `DispatchSourceTimer`; snapshot JSON com escrita atômica em Application Support; settings via `UserDefaults`+`Codable`.
- **Dependências:** T-05
- **CA:** snapshot sobrevive a kill -9 simulado (escrita atômica testada); round-trip Codable de configuração e listas.

### T-16 — `UNNotificationAdapter` `[P]` (RF-08)
- Pedido de permissão no primeiro uso; notificações de fim de foco/break e app bloqueado; degradação graciosa se negada.
- **Dependências:** T-05
- **CA:** permissão negada não lança erro nem quebra fluxo (verificação manual + teste de unidade do fallback).

---

## Épico 4 — Presentation (SwiftUI)

### T-17 — Composition Root (`AppContainer`) `[P]`
- `AppContainer.live()` e `.test()`; nenhum `.shared`/singleton fora dos adapters (arquitetura §7).
- **Dependências:** T-07..T-16
- **CA:** app inicia com container real; previews usam `.test()` com fakes.

### T-18 — Janela principal do timer `[M]` (RF-01) ✅ FEITO (2026-07-22)
- `MainView` + `TimerViewModel`: contagem, iniciar/pausar/retomar/cancelar, indicador de ciclo.
- **Dependências:** T-17
- **CA (UC-01/02/03):** fluxo completo de um pomodoro operável pela janela; estado da UI sempre derivado do estado do coordinator (fonte única).
- **Como ficou:** identidade DDS.TEC (`App/UI/DesignSystem/Brand.swift`), anel de progresso + tempo ao centro, controles RESET / play-pause / SKIP, tema claro+escuro adaptativo. Falta só o passe de acessibilidade do T-23.

### T-19 — Menu bar `[M]` (RF-04) ✅ FEITO (2026-07-22)
- `MenuBarExtra` com tempo restante no label; ações: iniciar, pausar, cancelar, pular intervalo, abrir janela/configurações.
- **Dependências:** T-18
- **CA:** todas as ações do RF-04.2 funcionam sem abrir a janela principal.
- **Como ficou:** "pular intervalo" virou o evento `skipBreak` na máquina pura (grava `outcome: .skipped`); `MenuBarView` usava os mesmos componentes da janela (`PrimaryCircleButton`/`GhostControl`).
- **Atualização (2026-08-05):** `MenuBarView` foi **apagada** — o popover passou a renderizar a própria `MainView` e a janela principal deixou de existir (app só barra de menus).

### T-20 — Configurações + listas de bloqueio `[G]` (RF-05, UC-05) ✅ FEITO (2026-07-22)
- `SettingsView` (durações, auto-início, force-terminate) + `BlockListView` de sites (input com validação) e de apps (file picker em `/Applications` + drag-and-drop capturando bundle ID).
- **Como ficou:** port `ApplicationPicking` (Domain) → `NSOpenPanelApplicationPicker` (Infra, `NSOpenPanel` + `Bundle(url:)`); `ManageBlockListUseCase.addApps` faz inclusão em lote sem lançar, devolvendo `duplicateNames`; `BlockListViewModel.addAppsFromPicker()` e `addApps(fromDroppedURLs:)`; UI com botão "Adicionar…" + `.dropDestination(for: URL.self)`.
- Seleção sem bundle ID legível volta em `unreadableNames` e vira aviso na UI — nunca é descartada em silêncio.
- **Falta validar à mão:** o painel em si (interação do usuário) não é coberto por teste automatizado.
- **Dependências:** T-17, T-11
- **CA:** adicionar/remover/ativar/desativar itens persiste e reflete na próxima sessão; domínio inválido mostra erro inline.

### T-21 — Fluxo de recuperação pós-crash na UI `[M]` (UC-04) ✅ FEITO (2026-07-22)
- Na inicialização, executar `RecoverFromCrashUseCase`; se sessão vigente, diálogo "Retomar ou encerrar?"; se expirada, restaurar silenciosamente e informar.
- **Dependências:** T-10, T-18
- **CA:** matar o app (kill -9) durante foco e reabrir cobre os três cenários do T-10 na prática.

### ~~T-22 — Modo hardcore na UI~~ `[P]` (RF-06) — CANCELADA em 2026-08-03
Removida junto com o modo hardcore. Ver a justificativa em `especificacao.md` §RF-06.

### T-23 — Acessibilidade e localização base `[M]` (RNF-08, RNF-09)
- Strings em catálogo (pt-BR), labels de VoiceOver, navegação por teclado nas telas principais.
- **Dependências:** T-18..T-20
- **CA:** VoiceOver anuncia timer e botões; tab percorre os controles das telas principais.

---

## Épico 5 — Qualidade e release

### T-24 — Roteiro de QA end-to-end `[M]`
- Checklist manual cobrindo UC-01..UC-05: domínio bloqueado não resolve; app bloqueado fecha < 2 s; hosts byte-idêntico após ciclo; failsafe com kill -9; senha negada (fluxo 3a).
- **Dependências:** T-18..T-22
- **CA:** checklist executado e arquivado em `docs/qa/` a cada release.

### T-25 — Assinatura, notarização e empacotamento `[M]` (RNF-06) ✅ FEITO (2026-07-22)
- `scripts/release.sh` + `make release` / `make release-dry`; passo a passo em `docs/release.md`.
- Validado até o DMG (build Release + `codesign --options runtime --timestamp` + entitlements + DMG assinado com atalho para `/Applications`).
- **Notarizado com sucesso pela Apple** (status `Accepted`); DMG final 889 KB, `spctl` → `source=Notarized Developer ID`.
- Notariza em dois passos: primeiro o `.app` (que recebe ticket próprio), depois o DMG. Grampear só o DMG deixaria o app sem ticket ao ser arrastado para `/Applications` — num Mac offline, o Gatekeeper barraria a primeira abertura.
- Credencial via **chave de API do App Store Connect** (`xcrun notarytool store-credentials tomafoco --key ...`): Apple ID + senha específica de app dava 401 persistente.
- Developer ID Application; hardened runtime; `notarytool` + stapling; DMG de distribuição; documento passo a passo em `docs/release.md`.
- **Dependências:** T-24
- **CA:** DMG abre em um Mac limpo sem aviso de Gatekeeper.

### T-32 — Atualização automática (Sparkle) `[M]` (ADR-9) ✅ FEITO (2026-07-30)
- Sparkle 2.9.4 via SPM, só no target do app. Feed `https://tomafoco.dds.tec.br/downloads/appcast.xml`.
- Checa 1×/dia em segundo plano e **pergunta antes de instalar** (`SUAutomaticallyUpdate: false`) — trocar de versão sozinho poderia cair no meio de uma sessão de foco.
- `App/UI/Updates/UpdaterController.swift`; itens "Buscar atualizações…" no menu "•••" e no menu do app; seção "Atualizações" nas Configurações.
- Confiança por assinatura **EdDSA** do appcast (`make sparkle-keys`; privada no chaveiro, pública em `SUPublicEDKey`). Servidor comprometido ou DNS envenenado não bastam para entregar update forjado.
- `release.sh` passou a assinar os bundles aninhados do Sparkle de dentro para fora e a gerar o `appcast.xml` com `generate_appcast` depois do staple.
- **Dependências:** T-25
- **CA:** app na versão anterior encontra a nova, mostra as notas e instala após confirmação.

### T-26 — Documentação de emergência `[P]` (RNF-02)
- README com o script manual de restauração do hosts (`sudo sed -i '' '/# Tomafoco-START/,/# Tomafoco-END/d' /etc/hosts`) para o pior caso.
- **Dependências:** T-13
- **CA:** instrução testada em cenário real de bloqueio órfão.

---

## Épico 6 — Pós-MVP (v2/v3, não bloqueia o release)

| Tarefa | Descrição | Ref. |
|---|---|---|
| T-27 `[G]` | Privileged helper via `SMAppService.daemon` + XPC (`XPCHelperPrivilegeRunner` substituindo o AppleScript por injeção — zero mudança fora do Composition Root) | ADR-4, RF-02.4 |
| T-28 `[M]` | Histórico e estatísticas (SwiftData) com visão dia/semana | RF-07 |
| T-29 `[M]` | Perfis de bloqueio múltiplos ("Trabalho", "Estudo") | RF-05.3 |
| T-30 `[M]` | Sincronização de configurações via iCloud | Fora de escopo v1 |
| T-31 `[G]` | Spike: NetworkExtension Content Filter (bloqueio por URL/caminho) — inclui pedido de entitlement à Apple | ADR-3 |

---

## Ordem de execução sugerida (caminho crítico)

```
T-01 → T-02/T-03 → T-04 → T-05 → T-06 → T-07 → T-08/T-09/T-10/T-11
                          ↘ T-12/T-13/T-14/T-15/T-16 (paralelo ao Épico 2)
T-17 → T-18 → T-19/T-20/T-21/T-22 → T-23 → T-24 → T-25/T-26 → release v1
```

O par **T-13 (hosts) + T-10/T-21 (failsafe)** concentra os dois maiores riscos do projeto (RNF-01 e RNF-02) — priorize e teste exaustivamente antes de investir em polish de UI.
