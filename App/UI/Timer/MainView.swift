import SwiftUI
import TomafocoDomain

/// Janela principal do timer (RF-01, T-18).
/// Layout em três faixas: cabeçalho, anel de progresso e controles — identidade DDS.TEC.
struct MainView: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                ring
                Spacer(minLength: 12)
                footer
            }
            .padding(24)
        }
        .frame(minWidth: 340, minHeight: 480)
        .sheet(item: $viewModel.pendingRecovery) { session in
            RecoverySheet(session: session, viewModel: viewModel)
        }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        ZStack {
            Text(viewModel.phaseTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.textSecondary)
                .lineLimit(1)

            HStack {
                Spacer()
                overflowMenu
            }
        }
        .frame(height: 24)
    }

    private var overflowMenu: some View {
        Menu {
            settingsButton
            Divider()
            Button("Sair do Tomafoco") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.textSecondary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Mais opções")
    }

    /// `SettingsLink` só existe no macOS 14+; no 13 usamos o seletor padrão.
    @ViewBuilder private var settingsButton: some View {
        if #available(macOS 14, *) {
            SettingsLink { Text("Configurações…") }
        } else {
            Button("Configurações…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }

    // MARK: - Anel + tempo

    private var ring: some View {
        ProgressRing(progress: viewModel.progress, phase: viewModel.phase, lineWidth: 6) {
            VStack(spacing: 6) {
                Text(viewModel.timeText)
                    .font(.system(size: 54, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Brand.textPrimary)
                    .contentTransition(.numericText())

                if !viewModel.cycleText.isEmpty {
                    Text(viewModel.cycleText.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Brand.textFaint)
                }
            }
        }
        .frame(width: 232, height: 232)
        .accessibilityLabel("Tempo restante \(viewModel.timeText)")
    }

    // MARK: - Rodapé: motivo, erro e controles

    private var footer: some View {
        VStack(spacing: 18) {
            if viewModel.isIdle && viewModel.requiresReason {
                TextField("Motivo do foco", text: $viewModel.reason)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Brand.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
                            )
                    )
                    .onSubmit { Task { await viewModel.startFocus() } }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 22) {
            GhostControl(systemName: "arrow.counterclockwise", title: "RESET",
                         isEnabled: !viewModel.isIdle) {
                Task { await viewModel.cancel() }
            }

            PrimaryCircleButton(
                systemName: primaryIcon,
                phase: viewModel.phase,
                accessibilityText: primaryLabel
            ) {
                Task { await primaryAction() }
            }
            .keyboardShortcut(.space, modifiers: [])

            GhostControl(systemName: "forward.end.fill", title: "SKIP",
                         isEnabled: viewModel.canSkip) {
                Task { await viewModel.skip() }
            }
        }
    }

    private var primaryIcon: String { viewModel.isRunning ? "pause.fill" : "play.fill" }

    private var primaryLabel: String {
        if viewModel.isRunning { return "Pausar" }
        if viewModel.isPaused { return "Retomar" }
        if viewModel.isAwaitingNextFocus { return "Iniciar próximo foco" }
        return "Iniciar foco"
    }

    private func primaryAction() async {
        if viewModel.isRunning { return await viewModel.pause() }
        if viewModel.isPaused { return await viewModel.resume() }
        if viewModel.isAwaitingNextFocus { return await viewModel.beginNextFocus() }
        await viewModel.startFocus()
    }
}

/// Diálogo de recuperação pós-crash (UC-04).
private struct RecoverySheet: View {
    let session: PomodoroSession
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Brand.accent(for: .focus))

                Text("Sessão recuperada")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)

                Text("Havia uma sessão em andamento quando o app foi encerrado.")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)

                Text(viewModel.recoveryDescription(for: session).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Brand.textFaint)

                HStack(spacing: 10) {
                    Button("Encerrar e liberar", role: .destructive) {
                        Task { await viewModel.discardRecoveredSession() }
                    }
                    .buttonStyle(.bordered)

                    Button("Retomar") {
                        Task { await viewModel.resumeRecoveredSession() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent(for: session.phase))
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(26)
        }
        .frame(width: 330)
    }
}
