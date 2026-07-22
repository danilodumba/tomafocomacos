import SwiftUI
import AppKit

/// Conteúdo do `MenuBarExtra` (RF-04). Controle rápido sem abrir a janela principal.
struct MenuBarView: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()

            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(viewModel.phaseTitle.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Brand.textFaint)

                    Text(viewModel.timeText)
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Brand.textPrimary)

                    if !viewModel.cycleText.isEmpty {
                        Text(viewModel.cycleText)
                            .font(.system(size: 11))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }

                HStack(spacing: 18) {
                    GhostControl(systemName: "arrow.counterclockwise", title: "RESET",
                                 isEnabled: !viewModel.isIdle) {
                        Task { await viewModel.cancel() }
                    }

                    PrimaryCircleButton(
                        systemName: viewModel.isRunning ? "pause.fill" : "play.fill",
                        phase: viewModel.phase,
                        accessibilityText: viewModel.isRunning ? "Pausar" : "Iniciar"
                    ) {
                        Task { await primaryAction() }
                    }

                    GhostControl(systemName: "forward.end.fill", title: "SKIP",
                                 isEnabled: viewModel.canSkip) {
                        Task { await viewModel.skip() }
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.4)

                HStack {
                    settingsButton
                    Spacer()
                    Button("Sair") { NSApplication.shared.terminate(nil) }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .tint(Brand.accent(for: viewModel.phase))
            }
            .padding(16)
        }
        .frame(width: 250)
    }

    private func primaryAction() async {
        if viewModel.isRunning { return await viewModel.pause() }
        if viewModel.isPaused { return await viewModel.resume() }
        if viewModel.isAwaitingNext { return await viewModel.beginNextPhase() }
        await viewModel.startFocus()
    }

    /// `SettingsLink` só existe no macOS 14+. No 13, abre as preferências pelo seletor padrão.
    @ViewBuilder private var settingsButton: some View {
        if #available(macOS 14, *) {
            SettingsLink { Text("Configurações…") }
        } else {
            Button("Configurações…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}
