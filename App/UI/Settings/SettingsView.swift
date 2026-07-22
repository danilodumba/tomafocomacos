import SwiftUI
import TomafocoDomain
import TomafocoInfrastructure

/// Janela de preferências com abas: durações/hardcore e listas de bloqueio (RF-05).
struct SettingsView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var blockListViewModel: BlockListViewModel

    /// Largura da coluna de rótulos — evita que "Ciclos até o intervalo longo" seja truncado.
    private let labelWidth: CGFloat = 210

    var body: some View {
        TabView {
            timerTab.tabItem { Label("Pomodoro", systemImage: "timer") }
            sitesTab.tabItem { Label("Sites", systemImage: "network") }
            appsTab.tabItem { Label("Apps", systemImage: "app.badge") }
        }
        .tint(Brand.cyan)
        .frame(width: 560, height: 500)
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
            }

            Section("Modo hardcore") {
                toggleRow("Ativar modo hardcore",
                          help: "Restringe o cancelamento e o pulo do foco durante a carência.",
                          isOn: $settingsViewModel.hardcoreEnabled)
                toggleRow("Exigir motivo ao iniciar", isOn: $settingsViewModel.hardcoreRequireReason)
                    .disabled(!settingsViewModel.hardcoreEnabled)
                row("Carência para cancelar") {
                    stepper(value: $settingsViewModel.hardcoreGraceMinutes, range: 0...30, suffix: " min")
                }
                .disabled(!settingsViewModel.hardcoreEnabled)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
            Text("Sites bloqueados durante o foco")
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
        }
        .padding(20)
    }

    // MARK: - Apps

    private var appsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Apps bloqueados durante o foco")
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
        }
        .padding(20)
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
