import SwiftUI
import TomafocoDomain
import TomafocoInfrastructure

/// Janela de preferências com abas: durações/comportamento e listas de bloqueio (RF-05).
struct SettingsView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var blockListViewModel: BlockListViewModel
    @ObservedObject var unlockPasswordViewModel: UnlockPasswordViewModel
    @ObservedObject var updater: UpdaterController

    /// Largura da coluna de rótulos — evita que "Ciclos até o intervalo longo" seja truncado.
    private let labelWidth: CGFloat = 210

    var body: some View {
        TabView {
            timerTab.tabItem { Label("Pomodoro", systemImage: "timer") }
            sitesTab.tabItem { Label("Sites", systemImage: "network") }
            appsTab.tabItem { Label("Apps", systemImage: "app.badge") }
        }
        .tint(Brand.cyan)
        .frame(width: 560, height: 560)
        .background(Brand.background)
    }

    // MARK: - Pomodoro

    private var timerTab: some View {
        Form {
            Section("Durações") {
                minutesRow("Foco", value: $settingsViewModel.focusMinutes, range: 1...120)
                minutesRow("Intervalo curto", value: $settingsViewModel.shortBreakMinutes, range: 1...60)
                minutesRow("Intervalo longo", value: $settingsViewModel.longBreakMinutes, range: 1...60)
                row("Ciclos até o intervalo longo") {
                    stepper(value: $settingsViewModel.cyclesBeforeLongBreak, range: 1...12, suffix: "")
                }
            }

            Section("Comportamento") {
                toggleRow("Avançar etapas automaticamente",
                          help: "Desligado, cada etapa termina avisando e espera você confirmar a próxima.",
                          isOn: $settingsViewModel.autoAdvancePhases)
                toggleRow("Forçar encerramento de apps",
                          help: "Usa force-terminate: fecha na marra, o app pode perder dados não salvos.",
                          isOn: $settingsViewModel.forceTerminateApps)
                toggleRow("Iniciar junto com o macOS",
                          help: "Registra o Tomafoco como item de login do sistema.",
                          isOn: $settingsViewModel.launchAtLogin)
                toggleRow("Sincronizar conclusão com o Lembretes",
                          help: "Concluir ou reabrir uma tarefa importada espelha o mesmo estado no app Lembretes.",
                          isOn: $settingsViewModel.syncReminderCompletion)
                toggleRow("Selecionar várias tarefas no foco",
                          help: "Permite vincular mais de uma tarefa a uma mesma sessão de foco. Cada tarefa recebe o tempo cheio da sessão nos relatórios.",
                          isOn: $settingsViewModel.allowMultipleTasksInFocus)
                if let error = settingsViewModel.launchAtLoginError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Atualizações") {
                toggleRow("Buscar atualizações automaticamente",
                          help: "Checa em segundo plano uma vez por dia. Nada é instalado sem você confirmar.",
                          isOn: $updater.automaticallyChecks)
                row("Checar agora", help: lastCheckText) {
                    Button("Buscar atualizações…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Text(AppInfo.display)
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textFaint)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            settingsViewModel.refreshLaunchAtLogin()
            // O Sparkle mexe em `automaticallyChecksForUpdates` por fora (diálogo de primeira
            // execução, fluxo de instalação) — sem reler, o toggle mostraria valor velho.
            updater.refresh()
        }
    }

    /// "Última verificação: 30/07/2026 14:12" — ou o texto de nunca-checou.
    private var lastCheckText: String {
        guard let date = updater.lastCheckDate else {
            return "Ainda não houve nenhuma verificação."
        }
        return "Última verificação: " + date.formatted(date: .numeric, time: .shortened)
    }

    // MARK: Linhas do formulário

    /// Rótulo em coluna de largura fixa + controle à direita: nada é truncado ao redimensionar.
    private func row<Control: View>(
        _ title: String, help: String? = nil, @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Brand.textPrimary)
                if let help {
                    Text(help)
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: labelWidth, alignment: .leading)

            control()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func minutesRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        row(title) {
            HStack(spacing: 8) {
                Text("\(Int(value.wrappedValue)) min")
                    .monospacedDigit()
                    .foregroundStyle(Brand.textPrimary)
                    .frame(width: 60, alignment: .trailing)
                Stepper("", value: value, in: range, step: 1).labelsHidden()
            }
        }
    }

    private func stepper(value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack(spacing: 8) {
            Text("\(value.wrappedValue)\(suffix)")
                .monospacedDigit()
                .foregroundStyle(Brand.textPrimary)
                .frame(width: 60, alignment: .trailing)
            Stepper("", value: value, in: range).labelsHidden()
        }
    }

    private func toggleRow(_ title: String, help: String? = nil, isOn: Binding<Bool>) -> some View {
        row(title, help: help) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    // MARK: - Sites

    private var sitesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            alwaysOnToggle(
                "Bloquear sites sempre que o Tomafoco estiver aberto",
                isOn: settingsViewModel.blockSitesWhileRunning,
                set: settingsViewModel.setBlockSitesWhileRunning)

            Text(settingsViewModel.blockSitesWhileRunning ? "Sites bloqueados" : "Sites bloqueados durante o foco")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.textSecondary)

            HStack(spacing: 8) {
                TextField("exemplo.com", text: $blockListViewModel.newDomain)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { blockListViewModel.addDomain() }
                Button("Adicionar") { blockListViewModel.addDomain() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.cyan)
            }

            Text("Bloqueia o endereço exato: “www.globo.com” não bloqueia “ge.globo.com” nem “globo.com”. Use “*.globo.com” para bloquear o domínio e todos os subdomínios. Inclua um caminho para bloquear só uma parte do site: “www.youtube.com/shorts” bloqueia os Shorts, mas não o resto do YouTube.")
                .font(.system(size: 11))
                .foregroundStyle(Brand.textFaint)
                .fixedSize(horizontal: false, vertical: true)

            errorLine

            listContainer {
                if blockListViewModel.domains.isEmpty {
                    emptyState("Nenhum site na lista.")
                }
                ForEach(blockListViewModel.domains, id: \.value) { domain in
                    HStack {
                        Text(domain.value).foregroundStyle(Brand.textPrimary)
                        Spacer()
                        removeButton { blockListViewModel.removeDomain(domain) }
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Redirecionar aba bloqueada para")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
                TextField("exemplo.com", text: $settingsViewModel.blockedRedirectURL)
                    .textFieldStyle(.roundedBorder)
                Text("Deixe vazio para usar a página de bloqueio padrão. Sem “https://”, ele é adicionado.")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
    }

    // MARK: - Apps

    private var appsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            alwaysOnToggle(
                "Bloquear apps sempre que o Tomafoco estiver aberto",
                isOn: settingsViewModel.blockAppsWhileRunning,
                set: settingsViewModel.setBlockAppsWhileRunning)

            HStack {
                Text(settingsViewModel.blockAppsWhileRunning ? "Apps bloqueados" : "Apps bloqueados durante o foco")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
                Spacer()
                Button("Adicionar…") { Task { await blockListViewModel.addAppsFromPicker() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.cyan)
                    .disabled(blockListViewModel.isPickingApps)
            }

            errorLine

            listContainer {
                if blockListViewModel.apps.isEmpty {
                    emptyState("Nenhum app. Use “Adicionar…” ou arraste um app aqui.")
                }
                ForEach(blockListViewModel.apps, id: \.bundleID) { app in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { app.isEnabled },
                            set: { blockListViewModel.setApp(app, enabled: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.displayName).foregroundStyle(Brand.textPrimary)
                                Text(app.bundleID)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Brand.textFaint)
                            }
                        }
                        .toggleStyle(.switch)
                        Spacer()
                        removeButton { blockListViewModel.removeApp(app) }
                    }
                    .padding(.vertical, 2)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                blockListViewModel.addApps(fromDroppedURLs: urls)
                return true
            }

            Divider().padding(.vertical, 2)

            unlockPasswordSection
        }
        .padding(20)
    }

    // MARK: - Senha de desbloqueio (FEAT-002)

    private var unlockPasswordSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Senha de desbloqueio")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
                Spacer()
                if unlockPasswordViewModel.hasPassword {
                    Button("Remover senha") { Task { await unlockPasswordViewModel.remove() } }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Brand.danger)
                }
            }
            HStack(spacing: 8) {
                SecureField(unlockPasswordViewModel.hasPassword ? "Nova senha" : "Senha",
                            text: $unlockPasswordViewModel.newPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirmar", text: $unlockPasswordViewModel.confirmation)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await unlockPasswordViewModel.save() } }
                Button(unlockPasswordViewModel.hasPassword ? "Alterar" : "Definir") {
                    Task { await unlockPasswordViewModel.save() }
                }
                .disabled(!unlockPasswordViewModel.canSave)
            }
            if let error = unlockPasswordViewModel.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(Brand.danger)
            } else if let info = unlockPasswordViewModel.infoMessage {
                Text(info).font(.system(size: 11)).foregroundStyle(Brand.textSecondary)
            }
            Text("Com senha, abrir um app bloqueado pede a senha — certa, o app abre e fica liberado até ser fechado. Desligar o bloqueio contínuo e trocar a senha também pedem a senha.")
                .font(.system(size: 11))
                .foregroundStyle(Brand.textFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Toggle do bloqueio contínuo. Não escreve direto no VM: desligar pode pedir senha, e se o
    /// usuário cancelar o toggle precisa voltar a ligado.
    private func alwaysOnToggle(_ title: String, isOn: Bool,
                                set: @escaping (Bool) async -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { value in Task { await set(value) } })) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Brand.textPrimary)
        }
        .toggleStyle(.switch)
    }

    // MARK: - Peças compartilhadas

    @ViewBuilder private var errorLine: some View {
        if let error = blockListViewModel.errorMessage {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func listContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        List { content() }
            .scrollContentBackground(.hidden)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
            )
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Brand.textFaint)
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash")
                .foregroundStyle(Brand.textSecondary)
        }
        .buttonStyle(.borderless)
        .help("Remover")
    }
}
