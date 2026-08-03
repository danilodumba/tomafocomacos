# Tomafoco — Briefing de produto para o site

**Para quê serve este documento:** insumo único para gerar o site de divulgação (landing page) do Tomafoco com o Claude Design. Reúne o que o app faz, para quem, os diferenciais, a identidade visual e a estrutura sugerida de páginas/seções. Descreve o **estado real do produto em 2026-07-30 (v1.2)** — o que está aqui já existe e funciona; nada é roadmap disfarçado de feature.

> Documentos irmãos: `especificacao.md` (requisitos), `arquitetura.md` (design técnico), `release.md` (assinatura/notarização).
> ⚠️ A `especificacao.md` ainda descreve o bloqueio de sites via `/etc/hosts` — **isso mudou** (ADR-8). Para o site, vale o que está aqui.

---

## 1. Resumo em uma frase

**Tomafoco é um timer Pomodoro para macOS que bloqueia de verdade os sites e apps que te distraem enquanto você foca — e libera tudo sozinho no intervalo.**

Variações curtas para hero/meta description:

- "Foco com fricção real: o site não abre, o app fecha. No intervalo, tudo volta."
- "Pomodoro + bloqueio de sites e apps para macOS. Sem senha de admin, sem nuvem, sem telemetria."
- "O Pomodoro que não depende só da sua força de vontade."

## 2. Problema e proposta

**Problema:** força de vontade sozinha não sustenta o foco. Timers de Pomodoro comuns avisam que o tempo acabou, mas não impedem a aba do YouTube nem o Slack piscando.

**Proposta:** durante a sessão de foco o Tomafoco adiciona *fricção real* — a aba bloqueada é redirecionada, o app bloqueado é encerrado. Terminou o foco, os bloqueios caem **imediatamente e automaticamente**.

**Honestidade (usar como diferencial, não esconder):** o Tomafoco **não é controle parental nem MDM corporativo**. Quem sabe mexer no Mac burla. O objetivo é autodisciplina, não segurança. Esse recado cabe numa seção "o que o Tomafoco não é" — passa credibilidade.

## 3. Público-alvo

| Persona | Cenário concreto (bom para storytelling do site) |
|---|---|
| Dev / profissional de tecnologia | Ciclo de 25 min; Slack e Discord fecham; abas de twitter.com e youtube.com são redirecionadas; ao fim do ciclo tudo volta para o intervalo de 5 min. |
| Estudante | Ciclos de 50/10 min, lista com redes sociais, e a tela cheia de intervalo tirando ele da máquina entre os blocos. |
| Quem já usa o app Lembretes | Importa a tarefa do Lembretes, foca nela, e a conclusão volta marcada no Lembretes. |

## 4. Funcionalidades (copy-ready)

Cada item abaixo é um card/seção em potencial: **título curto + o que faz + por que importa**.

### 4.1 Timer Pomodoro completo
Foco, intervalo curto e intervalo longo, com durações e número de ciclos configuráveis. Você escolhe se as etapas avançam sozinhas ou se cada uma espera sua confirmação. Iniciar, pausar, retomar, cancelar e pular intervalo — pela janela ou pela barra de menus.
*Por que importa:* Pomodoro rígido demais vira ruído; aqui o ritmo é seu.

### 4.2 Bloqueio de sites que funciona mesmo com VPN
Liste os domínios (`youtube.com`, `twitter.com`…). Durante o foco, qualquer aba desses domínios é redirecionada para uma página de bloqueio — ou para um site que você escolher (sua própria página de metas, por exemplo).
**Sem senha de administrador, sem mexer em arquivos do sistema, sem depender de DNS.** O Tomafoco pilota o navegador diretamente, então VPN corporativa, DNS-over-HTTPS e cache de DNS não atrapalham. Subdomínio bloqueia junto (`m.youtube.com`); domínio parecido não é bloqueado por engano (`naoglobo.com` continua livre se você bloqueou `globo.com`).
Navegadores suportados: **Safari, Chrome, Edge, Brave, Opera, Vivaldi**. **Firefox não é suportado** — ele não expõe as abas para automação no macOS. (Dizer isso no site evita review ruim.)

### 4.3 Bloqueio de aplicativos
Adicione apps pelo seletor ou arrastando o ícone. Ao iniciar o foco, os apps da lista são encerrados; se você (ou o próprio app) tentar reabrir durante a sessão, ele fecha de novo e um aviso discreto aparece no topo da tela — na tela onde o cursor está, some em segundos, não rouba o clique. Apps que relançam sozinhos (Slack, Teams) não viram enxurrada de avisos: o aviso é represado por app.

### 4.4 Tela cheia de intervalo
Quando o intervalo começa, uma tela cheia cobre **todos os monitores** para te tirar da máquina de verdade. Esc dispensa. Não é modo quiosque: ⌘Tab continua funcionando — de novo, autodisciplina, não prisão.

### 4.5 Tarefas — com importação do app Lembretes
CRUD completo de tarefas: título, tags livres, observação, prioridade e data/hora de vencimento. Busca, filtros e ordenação persistida.
**Importação do Lembretes (EventKit):** um seletor pesquisável mostra seus lembretes em aberto; clicar importa aquele lembrete na hora, com notas, vencimento, prioridade e URL anexada. Reimportar não duplica.
**Sincronização de conclusão nas duas vias:** concluiu no Tomafoco, o lembrete aparece riscado no Lembretes (e vice-versa ao reabrir). Pode desligar num toggle.

### 4.6 Cada foco vinculado a uma tarefa
Escolha a tarefa antes de iniciar o foco — o título aparece no anel do timer. Precisou trocar no meio? Pause e troque: o tempo restante é preservado.

### 4.7 Relatórios
Horas por tarefa, horas por dia, intervalos por dia e um resumo com **streak** de dias seguidos (Swift Charts). O tempo contado é de parede: do início ao fim da sessão.

### 4.8 Sobrevive a crash, sleep e reboot
O estado guarda o **horário absoluto de término**, não um contador. Fechou o Mac, o app caiu, reiniciou? Ao abrir, o Tomafoco detecta a sessão pendente e oferece **retomar** (com os bloqueios de volta) ou **encerrar e liberar**. E o mais importante: **nenhum caminho de execução deixa você bloqueado para sempre** — se a sessão já deveria ter terminado, tudo é liberado sozinho.

### 4.9 Detalhes que fazem diferença
- **Barra de menus** com a contagem regressiva e controles rápidos.
- **Alerta sonoro + ícone do Dock pulando** ao fim de cada etapa — toca mesmo se você tiver negado permissão de notificação.
- **Iniciar com o macOS** (item de login), num toggle.
- **Tema claro e escuro** adaptativos.
- **Interface em português (pt-BR)**, com acessibilidade por teclado e VoiceOver nas telas principais.

## 5. Diferenciais para destacar no hero / seção de comparação

1. **Não pede senha de administrador.** Não edita `/etc/hosts`, não instala daemon root, não vira driver de rede.
2. **Funciona onde o bloqueio por DNS falha:** VPN corporativa, DNS-over-HTTPS, cache do sistema.
3. **100% local.** Nenhum dado sai da máquina. Sem conta, sem nuvem, sem telemetria, sem analytics.
4. **Failsafe garantido.** Crash, kill, logout ou reboot nunca te deixam preso no bloqueio.
5. **Pomodoro + tarefas + relatórios num app só**, integrado ao app Lembretes que você já usa.
6. **Assinado com Developer ID e notarizado pela Apple** — Gatekeeper limpo, sem "clique com o botão direito para abrir".
7. **Honesto sobre os limites** — diz o que não faz (Firefox, root, controle parental).

## 6. Como funciona (seção "how it works", 3 passos)

1. **Monte suas listas** — domínios e apps que te distraem, uma vez só.
2. **Escolha a tarefa e inicie o foco** — abas bloqueadas são redirecionadas, apps bloqueados fecham, o anel começa a contar.
3. **Intervalo automático** — tudo desbloqueia, a tela cheia de descanso aparece; a sessão vai para o relatório.

## 7. Permissões e privacidade (seção dedicada — gera confiança)

- **Automação do navegador** (Ajustes do Sistema › Privacidade e Segurança › Automação): você autoriza o Tomafoco a controlar cada navegador, uma vez por navegador. É o que permite redirecionar a aba. Sem ela, o bloqueio de sites não funciona.
- **Lembretes:** pedida **só** se você importar tarefas do app Lembretes.
- **Notificações:** opcional; sem ela o alerta sonoro continua tocando.
- **Nada mais.** Sem acesso a rede, sem servidor, sem conta de usuário. Suas listas, tarefas e histórico ficam em arquivos na sua pasta de usuário.

## 8. Requisitos e distribuição

| Item | Valor |
|---|---|
| Sistema | macOS 13 Ventura ou superior |
| Processador | Apple Silicon e Intel (binário universal) |
| Versão atual | 1.2 |
| Formato | `.dmg` assinado com Developer ID e notarizado pela Apple |
| Onde | Download direto (fora da Mac App Store) |
| Idioma | Português (pt-BR) |
| Preço | *(definir — o site precisa desse campo preenchido)* |

## 9. Perguntas frequentes (FAQ pronto)

**Preciso digitar minha senha de administrador?**
Não. O Tomafoco não altera arquivos do sistema. Você só concede a permissão de Automação do navegador na primeira vez.

**Funciona com o Firefox?**
Não. O Firefox não expõe suas abas para automação no macOS. Safari, Chrome, Edge, Brave, Opera e Vivaldi funcionam.

**E se o app travar com o bloqueio ligado?**
Ao abrir de novo, ele detecta a sessão pendente e libera tudo se o horário já passou — ou pergunta se você quer retomar. Você nunca fica preso.

**Funciona com VPN da empresa?**
Sim. O bloqueio não passa por DNS nem rede, então VPN e DNS corporativo não interferem.

**Meus dados vão para algum servidor?**
Não. Tudo fica na sua máquina. Sem conta, sem nuvem, sem telemetria.

**Dá para burlar?**
Dá — de propósito. A ferramenta é de autodisciplina; ela cria atrito, não uma jaula.

**Preciso do app Lembretes?**
Não. As tarefas funcionam sozinhas; a importação do Lembretes é opcional.

## 10. Identidade visual (usar no site)

Paleta da marca **DDS.TEC**, a mesma do app:

| Token | Hex | Uso no app | Sugestão no site |
|---|---|---|---|
| cyan | `#17B9EB` | acento primário, anel de foco, botão principal | CTA, links, destaques |
| cyan claro | `#94DCF2` | acento de intervalo (tema escuro) | detalhes, gradientes, ícones |
| cyan escuro | `#0D6985` | acento de intervalo (tema claro) | hover, texto sobre cyan |
| navy | `#08143E` | fundo (escuro) e texto (claro) | fundo do hero, texto de corpo |

Diretrizes: interface do app é minimalista e centrada num **anel de progresso** com o tempo ao centro; janela pequena (340×480) sem barra de título. O site deve ter a mesma pegada — muito espaço em branco (ou navy), pouca borda, um acento cyan só. **Tema claro e escuro** (o app é adaptativo; o site deveria ser também).

**Tom de voz:** direto, técnico, sem hype. Frases curtas. Nada de "revolucione sua produtividade". O produto vende por ser honesto e por funcionar onde outros falham.

## 11. Estrutura sugerida do site (uma página)

1. **Hero** — logo, frase única (§1), print do timer com o anel, botão "Baixar para macOS" + "macOS 13+ · Apple Silicon e Intel · grátis de telemetria".
2. **O problema** (§2) — 2 ou 3 linhas.
3. **Como funciona** — os 3 passos do §6, com ícones.
4. **Funcionalidades** — grid de cards a partir do §4 (priorizar 4.2, 4.3, 4.5, 4.7, 4.8).
5. **Por que é diferente** — os 7 pontos do §5, ou comparação com "bloqueio por hosts/DNS".
6. **Privacidade e permissões** (§7) — bloco de destaque.
7. **Relatórios** — print dos gráficos, texto do §4.7.
8. **O que o Tomafoco não é** (§2, parágrafo de honestidade) — diferencia de concorrentes.
9. **FAQ** (§9) — acordeão.
10. **Download** — requisitos do §8, aviso de notarização, link do `.dmg`.
11. **Rodapé** — DDS.TEC, versão 1.2, sem newsletter, sem rastreador.

## 12. Capturas de tela a produzir (não existem ainda)

- Janela principal em foco: anel cyan, tempo ao centro, título da tarefa.
- Tela cheia de intervalo.
- Aba Sites das Configurações com a lista de domínios.
- Aba Apps com apps bloqueados.
- Janela de Tarefas com tags e vencimento.
- Janela de Relatórios com os gráficos.
- Aviso de app bloqueado (toast no topo da tela).
- Sheet de importação do Lembretes.

## 13. Coisas que o site NÃO deve prometer

- Bloqueio no Firefox.
- Bloqueio por URL/caminho específico (só por domínio).
- Bloqueio à prova de usuário técnico/root.
- Sincronização entre Macs / iCloud.
- Versão para iPhone ou iPad.
- Filtro por *tags* do Lembretes (a API da Apple não expõe tags; só listas).
- Perfis de bloqueio ("Trabalho", "Estudo") — ainda não existe.
- Integração com os Modos de Foco do macOS.
