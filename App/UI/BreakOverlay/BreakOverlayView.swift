import SwiftUI
import TomafocoDomain

/// Tela cheia exibida no intervalo (RF-01.3). Ocupa o monitor inteiro para tirar o usuário
/// da tarefa — um aviso discreto seria ignorado, que é justamente o problema que ela resolve.
struct BreakOverlayView: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()

            VStack(spacing: 34) {
                VStack(spacing: 10) {
                    Text(viewModel.phaseTitle.uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(2.4)
                        .foregroundStyle(Brand.textFaint)

                    Text(headline)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                        .multilineTextAlignment(.center)
                }

                ProgressRing(progress: viewModel.progress, phase: viewModel.phase, lineWidth: 8) {
                    VStack(spacing: 8) {
                        Text(viewModel.timeText)
                            .font(.system(size: 76, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Brand.textPrimary)
                            .contentTransition(.numericText())

                        if !viewModel.cycleText.isEmpty {
                            Text(viewModel.cycleText.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.6)
                                .foregroundStyle(Brand.textFaint)
                        }
                    }
                }
                .frame(width: 300, height: 300)

                controls
            }
            .padding(48)
        }
    }

    private var headline: String {
        viewModel.isAwaitingNext
            ? "Foco concluído. Hora de pausar."
            : "Levante, respire, olhe para longe."
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 14) {
            // Sair da tela sem mexer no timer: o intervalo continua correndo por trás.
            Button("Fechar") { viewModel.dismissBreakOverlay() }
                .buttonStyle(.bordered)
                .controlSize(.large)

            if viewModel.isAwaitingNext {
                Button("Iniciar intervalo") { Task { await viewModel.beginNextPhase() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent(for: viewModel.phase))
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Pular intervalo") { Task { await viewModel.skip() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent(for: viewModel.phase))
                    .controlSize(.large)
            }
        }

        Text("Esc fecha esta tela")
            .font(.system(size: 11))
            .foregroundStyle(Brand.textFaint)
    }
}
