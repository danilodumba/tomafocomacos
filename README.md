# Tomafoco

App de Pomodoro para macOS que bloqueia sites e apps distrativos durante o foco.

> Documentação de produto/arquitetura em [`docs/`](docs/): `especificacao.md`, `arquitetura.md`, `tarefas.md`.

## Arquitetura

Clean Architecture com pacotes SPM por camada, dependências apontando sempre para o domínio:

```
Presentation (App/, SwiftUI)  →  TomafocoApplication  →  TomafocoDomain  ←  TomafocoInfrastructure
```

- **TomafocoDomain** — núcleo puro (entidades, value objects, ports). Sem AppKit. Roda em qualquer plataforma.
- **TomafocoApplication** — casos de uso + máquina de estados pura. Depende só do Domain.
- **TomafocoInfrastructure** — adapters do macOS (`NSWorkspace`, `/etc/hosts`, AppleScript, notificações).
- **App/** — Composition Root (`AppContainer`) + SwiftUI (janela, menu bar, preferências).
- **TomafocoTestSupport** — fakes/spies dos ports compartilhados pelos testes.

## Pré-requisitos

- macOS 13+, Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- (opcional) [SwiftLint](https://github.com/realm/SwiftLint): `brew install swiftlint`

## Começar

```bash
make project      # gera Tomafoco.xcodeproj a partir de project.yml
make open         # gera e abre no Xcode
make test         # roda os testes de todos os pacotes
```

O `.xcodeproj` NÃO é versionado — `project.yml` é a fonte da verdade (ADR-5). Rode `make project` após clonar.

## Estado atual

Núcleo SOLID implementado e testado (72 testes verdes; app compila e roda):

- ✅ Domain: modelo, ports e validações (com testes)
- ✅ Application: `SessionStateMachine` pura, `SessionCoordinator`, casos de uso (com testes de tabela)
- ✅ Infrastructure: `HostsFileEditor` (RNF-01) + `HostsFileWebsiteBlocker`, `WorkspaceAppBlocker`, `AppleScriptPrivilegeRunner`, `NSOpenPanelApplicationPicker`, clock, persistência, notificações
- ✅ App: Composition Root + UI (timer, menu bar, preferências) com a identidade DDS.TEC

Próximas tarefas: ver `docs/tarefas.md` (T-21 recuperação pós-crash, T-12/T-13 validação manual dos bloqueios, T-25 assinatura/notarização).

## Identidade visual

Paleta e símbolo vêm da marca **DDS.TEC** (`Brand.swift`):

| Token | Hex | Uso |
|---|---|---|
| cyan | `#17B9EB` | acento primário, anel de foco, botão principal |
| cyan claro | `#94DCF2` | acento de intervalo no tema escuro |
| cyan escuro | `#0D6985` | acento de intervalo no tema claro |
| navy | `#08143E` | fundo (escuro) e texto (claro) |

Todos os tokens semânticos são adaptativos claro/escuro via `Color.adaptive` (`NSColor` dinâmico) — nenhuma View precisa ler `@Environment(\.colorScheme)`.

## ⚠️ Emergência — bloqueio órfão no /etc/hosts

Se por algum motivo um bloqueio ficar preso (o failsafe do app deve evitar isso — RNF-02), remova o bloco manualmente:

```bash
sudo sed -i '' '/# Tomafoco-START/,/# Tomafoco-END/d' /etc/hosts
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

## Distribuição

Fora da Mac App Store, assinado com Developer ID e notarizado (Gatekeeper). Passo a passo: T-25 em `docs/tarefas.md`.
