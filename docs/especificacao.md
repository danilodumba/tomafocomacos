# Tomafoco — Especificação do Produto

**Versão:** 1.0
**Data:** 2026-07-22
**Plataforma:** macOS 13+ (Ventura ou superior)
**Distribuição:** Fora da Mac App Store (Developer ID, assinado e notarizado)
**Stack:** Swift 5.10+ / SwiftUI

> Documento complementar: `arquitetura.md` (design técnico) e `tarefas.md` (backlog de implementação).

---

## 1. Visão do produto

O **Tomafoco** é um aplicativo de Pomodoro para macOS que, durante as sessões de foco, bloqueia o acesso a sites e aplicativos que distraem o usuário. Ao terminar a sessão (ou durante os intervalos), os bloqueios são revertidos automaticamente.

**Problema que resolve:** a força de vontade sozinha não sustenta o foco; o app adiciona *fricção* real (site não carrega, app fecha sozinho) durante os períodos de trabalho.

**O que o produto NÃO é:** não é uma ferramenta de controle parental nem um MDM corporativo. Um usuário tecnicamente habilidoso consegue burlar os bloqueios — o objetivo é fricção de autodisciplina, não segurança.

---

## 2. Personas e cenário de uso

| Persona | Cenário |
|---|---|
| Desenvolvedor/profissional de tecnologia | Inicia um ciclo de foco de 25 min; Slack e Discord são fechados; twitter.com e youtube.com param de resolver; ao fim do ciclo tudo volta ao normal para o intervalo de 5 min. |
| Estudante | Configura ciclos de 50/10 min e uma lista de bloqueio com redes sociais; a tela cheia de intervalo o tira da máquina entre os blocos de estudo. |

---

## 3. Requisitos funcionais

### RF-01 — Timer Pomodoro
- **RF-01.1** — O usuário pode iniciar, pausar, retomar e cancelar uma sessão de foco.
- **RF-01.2** — Durações configuráveis: foco (padrão 25 min), intervalo curto (padrão 5 min), intervalo longo (padrão 15 min), ciclos até o intervalo longo (padrão 4).
- **RF-01.3** — Ao fim de uma sessão de foco, o app notifica o usuário e inicia o intervalo (curto ou longo, conforme o ciclo). O início é automático apenas se "avançar etapas automaticamente" estiver ligado; caso contrário aguarda confirmação. **Os bloqueios caem imediatamente ao fim do foco, mesmo aguardando confirmação.** *(alterado em 2026-07-22: antes o intervalo sempre emendava sozinho, o que contrariava a expectativa do usuário sobre o ajuste)*
- **RF-01.4** — Ao fim de um intervalo, o app notifica o usuário e aguarda confirmação para iniciar o próximo foco (mesmo ajuste do RF-01.3).
- **RF-01.5** — O estado da sessão (horário de término absoluto, não apenas tempo restante) é persistido em disco, de modo que crash/reinício do app não perca a sessão.

### RF-02 — Bloqueio de sites
- **RF-02.1** — O usuário mantém uma lista de domínios bloqueados (ex.: `twitter.com`, `youtube.com`).
- **RF-02.2** — Ao iniciar uma sessão de foco, os domínios da lista (e seus subdomínios `www.`) são redirecionados para `127.0.0.1` via inserção de um bloco delimitado no `/etc/hosts`, seguido de flush do cache de DNS.
- **RF-02.3** — Ao terminar/cancelar a sessão de foco, apenas o bloco delimitado é removido do `/etc/hosts`, preservando integralmente o conteúdo original do arquivo.
- **RF-02.4** — A edição do `/etc/hosts` solicita privilégio de administrador via prompt nativo do macOS (MVP). Em versão futura, um privileged helper (`SMAppService.daemon` + XPC) elimina os prompts repetidos.
- **RF-02.5** — **Failsafe:** se o app for encerrado/crashar com bloqueio ativo, na próxima abertura ele detecta a condição (flag persistida com horário de término) e restaura o `/etc/hosts` caso a sessão já devesse ter terminado.

### RF-03 — Bloqueio de aplicativos
- **RF-03.1** — O usuário mantém uma lista de aplicativos bloqueados, identificados por *bundle ID*, adicionados por seleção em `/Applications` ou arrastar-e-soltar.
- **RF-03.2** — Ao iniciar a sessão de foco, todos os apps da lista em execução são encerrados (`terminate()`; `forceTerminate()` como fallback configurável).
- **RF-03.3** — Durante a sessão, qualquer app da lista que for aberto é encerrado imediatamente (observação de `NSWorkspace.didLaunchApplicationNotification`) e o usuário recebe uma notificação explicando o bloqueio.
- **RF-03.4** — Ao terminar/cancelar a sessão, a observação é desativada e os apps voltam a poder ser abertos.

### RF-04 — Menu bar
- **RF-04.1** — O app exibe um item na barra de menus com o tempo restante da sessão atual.
- **RF-04.2** — Pelo menu bar é possível: iniciar foco, pausar, cancelar, pular intervalo e abrir a janela principal/configurações.

### RF-05 — Configurações e listas
- **RF-05.1** — Tela de configurações para durações, auto-início e comportamento de encerramento (terminate vs. force).
- **RF-05.2** — Telas de gerenciamento das listas de sites e de apps bloqueados (adicionar, remover, ativar/desativar item individualmente).
- **RF-05.3** — Suporte a múltiplos *perfis* de bloqueio (ex.: "Trabalho", "Estudo") — pós-MVP.

### RF-06 — ~~Modo hardcore~~ (removido em 2026-08-03)
Restringia cancelar/pular o foco durante uma carência e exigia um "motivo da sessão" ao iniciar.
Removido do produto: o app é de autodisciplina, não de coerção (ver §"o que o produto NÃO é") —
a trava atrapalhava quem precisava legitimamente interromper o foco e era contornável de qualquer
forma (Force Quit não é bloqueável sem root). A tela cheia de intervalo cobre a intenção original.

### RF-07 — Histórico e estatísticas (pós-MVP)
- **RF-07.1** — Registro de sessões concluídas/canceladas com data, duração e perfil.
- **RF-07.2** — Visualização de estatísticas por dia/semana (ciclos completos, tempo total de foco).

### RF-08 — Notificações
- **RF-08.1** — Notificações locais (`UNUserNotificationCenter`) para: fim de foco, fim de intervalo, app bloqueado encerrado. Fim de etapa também toca **som de alerta** e faz o ícone do Dock pular — o som independe da permissão de notificação.
- **RF-08.2** — Solicitação de permissão de notificação no primeiro uso, com degradação graciosa se negada.

---

## 4. Requisitos não funcionais

| ID | Requisito |
|---|---|
| RNF-01 | **Confiabilidade do hosts:** o app jamais pode corromper o `/etc/hosts`. Toda escrita usa bloco delimitado (`# Tomafoco-START` / `# Tomafoco-END`), backup prévio e operação idempotente (ativar 2× não duplica; desativar sem bloco presente é no-op). |
| RNF-02 | **Failsafe obrigatório:** nenhum caminho de execução (crash, kill, logout, reboot) pode deixar o usuário permanentemente bloqueado. |
| RNF-03 | **Desempenho:** consumo de CPU em idle < 1%; o observer de apps não faz polling (usa notificações do sistema). |
| RNF-04 | **Segurança:** nenhum dado sai da máquina; sem telemetria; a senha de admin nunca é manipulada pelo app (o prompt é do próprio macOS). |
| RNF-05 | **Testabilidade:** lógica de domínio e casos de uso 100% testáveis sem tocar em `/etc/hosts`, `NSWorkspace` ou timers reais (ver arquitetura: inversão de dependência em todas as fronteiras de sistema). Meta: ≥ 80% de cobertura em Domain + Application. |
| RNF-06 | **Distribuição:** binário assinado com Developer ID e notarizado (Gatekeeper limpo). |
| RNF-07 | **Compatibilidade:** macOS 13+; Apple Silicon e Intel (universal binary). |
| RNF-08 | **Idioma:** UI em pt-BR com estrutura preparada para localização (en como segunda língua futura). |
| RNF-09 | **Acessibilidade:** navegação por teclado e suporte a VoiceOver nas telas principais. |

---

## 5. Casos de uso principais

### UC-01 — Iniciar sessão de foco
1. Usuário aciona "Iniciar foco" (janela ou menu bar).
2. Sistema ativa o bloqueio de apps: encerra os que estão rodando e ativa o observer.
3. Sistema ativa o bloqueio de sites: solicita privilégio admin, insere bloco no hosts, faz flush de DNS, persiste flag de failsafe.
4. Timer inicia; menu bar exibe contagem regressiva.
- **Fluxo alternativo 3a:** usuário nega a senha de admin → app pergunta se deseja continuar com bloqueio apenas de apps ou cancelar a sessão.
- **Critério de aceite:** com sessão ativa, domínio bloqueado não resolve no navegador e app bloqueado fecha em < 2 s após tentativa de abertura.

### UC-02 — Concluir sessão de foco
1. Timer chega a zero.
2. Sistema desativa bloqueios (remove bloco do hosts, flush DNS, remove observer, limpa flag de failsafe).
3. Sistema registra a sessão no histórico e notifica o usuário.
4. Intervalo (curto ou longo) inicia conforme o contador de ciclos.
- **Critério de aceite:** `/etc/hosts` byte-idêntico ao estado pré-sessão (exceto se o usuário o editou externamente durante a sessão — nesse caso apenas o bloco delimitado é removido).

### UC-03 — Cancelar sessão de foco
1. Usuário aciona "Cancelar".
2. Sistema desativa bloqueios e registra a sessão como cancelada.

### UC-04 — Recuperação após crash/reinício
1. App abre e detecta flag de failsafe ativa.
2. Se `endDate` já passou: restaura hosts, limpa flag, informa o usuário.
3. Se `endDate` ainda não chegou: oferece retomar a sessão (reativando bloqueios) ou encerrá-la (restaurando tudo).

### UC-05 — Gerenciar listas de bloqueio
1. Usuário abre configurações → aba Sites ou Apps.
2. Adiciona/remove/ativa/desativa entradas. Domínios são validados (formato) e normalizados (lowercase, sem esquema/caminho).
3. Alterações durante uma sessão ativa têm efeito imediato configurável (padrão: aplicar no próximo ciclo).

---

## 6. Fora de escopo (v1)

- Bloqueio por URL/caminho específico (exigiria NetworkExtension Content Filter + entitlement aprovado pela Apple) — candidato à v3.
- Sincronização entre Macs (iCloud) — pós-MVP.
- Versões iOS/iPadOS.
- Integração com calendário/Focus Modes do macOS.
- Bloqueio resistente a usuário root/técnico.

---

## 7. Riscos e mitigações

| Risco | Impacto | Mitigação |
|---|---|---|
| Corrupção do `/etc/hosts` | Alto | Bloco delimitado, backup, operações idempotentes, testes de integração dedicados (RNF-01) |
| Usuário preso em bloqueio após crash | Alto | Failsafe na inicialização (RF-02.5, UC-04) + script manual de emergência documentado no README |
| Prompts de senha repetidos irritarem o usuário | Médio | Comunicar claramente no onboarding; privileged helper na v2 |
| `terminate()` causar perda de dados em apps de terceiros | Médio | `terminate()` (quit gracioso) como padrão; `forceTerminate()` apenas opt-in |
| Mudanças de API do macOS | Baixo | Fronteiras de sistema isoladas atrás de protocolos (ver arquitetura) |
