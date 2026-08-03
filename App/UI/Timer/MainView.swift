import SwiftUI
import TomafocoDomain

/// Janela principal do timer (RF-01, T-18).
/// Layout em três faixas: cabeçalho, anel de progresso e controles — identidade DDS.TEC.
struct MainView: View {
    @ObservedObject var viewModel: TimerViewModel
    @ObservedObject var updater: UpdaterController

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
                OverflowMenu(updater: updater)
            }
        }
        .frame(height: 24)
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

                if let task = viewModel.currentTaskTitle {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                            .font(.system(size: 9))
                        Text(task)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: 150)
                    .accessibilityLabel("Tarefa em foco: \(task)")
                }
            }
        }
        .frame(width: 232, height: 232)
        .accessibilityLabel("Tempo restante \(viewModel.timeText)")
    }

    // MARK: - Rodapé: motivo, erro e controles

    private var footer: some View {
        VStack(spacing: 18) {
            if viewModel.isIdle && !viewModel.availableTasks.isEmpty {
                taskSelector(
                    selected: viewModel.selectedTaskIDs,
                    accessibility: viewModel.allowsMultipleTasks
                        ? "Tarefas do próximo foco" : "Tarefa do próximo foco",
                    toggle: { viewModel.toggleSelectedTask($0) },
                    clear: { viewModel.selectedTaskIDs = [] })
            }

            // Pausado: permite trocar a(s) tarefa(s) (usuário finalizou/mudou de tarefa no meio do foco).
            if viewModel.isPaused && !viewModel.availableTasks.isEmpty {
                taskSelector(
                    selected: viewModel.currentSessionTaskIDs,
                    accessibility: "Trocar a tarefa do foco",
                    toggle: { id in Task { await viewModel.toggleCurrentTask(id) } },
                    clear: { Task { await viewModel.changeCurrentTasks([]) } })
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

    /// Seletor compacto de tarefa(s). Uma única com o multi-tarefa desligado; várias (checkmarks)
    /// quando ligado (RF-09.4). Ocioso escolhe a(s) do próximo foco (RF-09); pausado troca a(s)
    /// da sessão corrente (RF-09.1). `toggle` alterna uma tarefa; `clear` esvazia a seleção.
    private func taskSelector(
        selected: Set<UUID>, accessibility: String,
        toggle: @escaping (UUID) -> Void, clear: @escaping () -> Void
    ) -> some View {
        Menu {
            Button { clear() } label: {
                Label("Sem tarefa", systemImage: selected.isEmpty ? "checkmark" : "")
            }
            Divider()
            ForEach(viewModel.availableTasks) { task in
                Button { toggle(task.id) } label: {
                    Label(task.title, systemImage: selected.contains(task.id) ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textFaint)
                Text(selectionSummary(selected))
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(accessibility)
    }

    /// Rótulo do seletor: "Sem tarefa", o título quando é uma só, ou "N tarefas".
    private func selectionSummary(_ selected: Set<UUID>) -> String {
        guard !selected.isEmpty else { return "Sem tarefa" }
        if selected.count == 1, let id = selected.first,
           let title = viewModel.availableTasks.first(where: { $0.id == id })?.title {
            return title
        }
        return "\(selected.count) tarefas"
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
        if viewModel.isAwaitingNext { return "Iniciar \(viewModel.phase == .focus ? "foco" : "intervalo")" }
        return "Iniciar foco"
    }

    private func primaryAction() async {
        if viewModel.isRunning { return await viewModel.pause() }
        if viewModel.isPaused { return await viewModel.resume() }
        if viewModel.isAwaitingNext { return await viewModel.beginNextPhase() }
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
