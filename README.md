# Tomafoco

App de Pomodoro para macOS que bloqueia sites e apps distrativos durante o foco.

> Documentação de produto/arquitetura controlada em [`../DOCS - Tomafoco/APP/`](../DOCS%20-%20Tomafoco/APP/) (vault Obsidian): `especificacao.md`, `arquitetura.md`, `tarefas.md`, `release.md`, `produto-para-site.md`. O `docs/` deste repo só guarda assets operacionais (`screenshots/`, `release-notes/`).

## Funcionalidades

- **Timer Pomodoro** — foco/intervalo curto/intervalo longo, ciclos configuráveis, avanço manual ou automático das etapas.
- **Bloqueio de sites** por automação do navegador (ADR-8): redireciona abas bloqueadas para uma página local — sem root, sem senha, imune a DNS de VPN/DoH. Safari, Chrome, Edge, Brave, Opera, Vivaldi (Firefox não expõe abas por AppleScript).
  - Site de redirecionamento configurável nas Configurações › Sites (vazio = página padrão).
- **Bloqueio de apps** — `NSWorkspace` encerra e observa relançamentos; aviso na tela ao tentar reabrir.
- **Tela cheia de intervalo** — cobre todos os monitores; Esc dispensa.
- **Tarefas** — CRUD manual, tags livres, importação do app Lembretes (EventKit), vínculo tarefa↔sessão.
- **Relatórios** — horas por tarefa/dia, intervalos, streak (Swift Charts).
- **Sobrevive a crash/sleep/reboot** — estado com término absoluto (`endsAt`) + fluxo de recuperação.
- **Iniciar com o macOS** (item de login), alerta sonoro no fim de cada etapa.
- **Atualização automática** via Sparkle — checa uma vez por dia e pergunta antes de instalar.

## Arquitetura

Clean Architecture com pacotes SPM por camada, dependências apontando sempre para o domínio:

```
Presentation (App/, SwiftUI)  →  TomafocoApplication  →  TomafocoDomain  ←  TomafocoInfrastructure
```

- **TomafocoDomain** — núcleo puro (entidades, value objects, ports). Sem AppKit. Roda em qualquer plataforma.
- **TomafocoApplication** — casos de uso + `SessionStateMachine` pura + `SessionCoordinator`. Depende só do Domain.
- **TomafocoInfrastructure** — adapters do macOS (automação de navegador, `NSWorkspace`, EventKit, clock, persistência, notificações). AppKit sob `#if canImport(AppKit)`.
- **App/** — Composition Root (`AppContainer`) + SwiftUI (janela, menu bar, preferências, tarefas/relatórios).
- **TomafocoTestSupport** — fakes/spies dos ports compartilhados pelos testes.

Regras de ouro: nada de `Date()`/`Timer` no Domain/Application (tudo via `SessionClock`); efeitos colaterais saem da máquina como `SessionEffect` e quem executa é o `SessionCoordinator`.

## Pré-requisitos

- macOS 13+, Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- (opcional) [SwiftLint](https://github.com/realm/SwiftLint): `brew install swiftlint`

## Começar

```bash
make project      # gera Tomafoco.xcodeproj a partir de project.yml
make open         # gera e abre no Xcode
make test         # roda os testes de todos os pacotes SPM
```

O `.xcodeproj` NÃO é versionado — `project.yml` é a fonte da verdade (ADR-5). Rode `make project` após clonar.

## Estado atual

**Versão publicada: 1.8** (2026-08-06). Núcleo SOLID implementado e testado (228 testes verdes: Domain 50, Application 134, Infrastructure 44; app compila e roda):

- ✅ Domain: modelo, ports e validações (com testes)
- ✅ Application: `SessionStateMachine` pura, `SessionCoordinator`, casos de uso + `ReportBuilder`/`ManageTasksUseCase` (testes de tabela)
- ✅ Infrastructure: `AppleScriptBrowserBlocker` (ADR-8), `WorkspaceAppBlocker`, `NSOpenPanelApplicationPicker`, `EventKitReminderImporter`, clock, persistência (`FileSessionSnapshotStore`/`FileTaskStore`), notificações
- ✅ App: Composition Root + UI (timer, menu bar, preferências, tarefas/relatórios) com a identidade DDS.TEC

Próximas tarefas: ver `../DOCS - Tomafoco/APP/tarefas.md`.

## Identidade visual

Paleta e símbolo vêm da marca **DDS.TEC** (`Brand.swift`):

| Token | Hex | Uso |
|---|---|---|
| cyan | `#17B9EB` | acento primário, anel de foco, botão principal |
| cyan claro | `#94DCF2` | acento de intervalo no tema escuro |
| cyan escuro | `#0D6985` | acento de intervalo no tema claro |
| navy | `#08143E` | fundo (escuro) e texto (claro) |

Todos os tokens semânticos são adaptativos claro/escuro via `Color.adaptive` (`NSColor` dinâmico) — nenhuma View precisa ler `@Environment(\.colorScheme)`.

## Permissões (TCC)

- **Automação** (Ajustes do Sistema › Privacidade › Automação): autoriza o Tomafoco a pilotar cada navegador — pedida uma vez por navegador. Sem ela, o site não bloqueia.
- **Lembretes**: só se você importar tarefas do app Lembretes.

Se um site não bloquear, o problema é permissão de Automação, navegador não suportado (Firefox) ou navegador fechado — **não** há mais DNS/rede no caminho.

## Distribuição

Fora da Mac App Store, assinado com Developer ID e notarizado (Gatekeeper). `make release` gera o `.dmg` assinado, notarizado e grampeado. Detalhes em `../DOCS - Tomafoco/APP/tarefas.md` (T-25).

O app **se atualiza sozinho** via Sparkle (ADR-9): checa `https://tomafoco.dds.tec.br/downloads/appcast.xml` uma vez por dia e pergunta antes de instalar. O `make release` também gera o `appcast.xml` assinado com a chave EdDSA — passo a passo em `../DOCS - Tomafoco/APP/release.md`.

## Emergência (legado)

O bloqueio de sites deixou de usar `/etc/hosts` no ADR-8. Se sua máquina ainda tiver um bloco órfão de uma versão antiga:

```bash
sudo sed -i '' '/# Tomafoco-START/,/# Tomafoco-END/d' /etc/hosts
```
