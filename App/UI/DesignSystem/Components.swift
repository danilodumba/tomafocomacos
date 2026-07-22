import SwiftUI
import TomafocoDomain

/// Anel de progresso da sessão: trilho estático + arco preenchido conforme o tempo decorrido.
struct ProgressRing<Content: View>: View {
    let progress: Double          // 0…1
    let phase: SessionPhase
    let lineWidth: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(Brand.ringTrack, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(
                    Brand.accentGradient(for: phase),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Brand.accent(for: phase).opacity(0.35), radius: 8)
                // 1s = intervalo do tick; anima linear para o arco não "pular".
                .animation(.linear(duration: 1), value: progress)

            content()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Botão circular principal (play/pause) — o único elemento sólido da tela.
struct PrimaryCircleButton: View {
    let systemName: String
    let phase: SessionPhase
    let accessibilityText: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Brand.accent(for: phase))
                    .shadow(color: Brand.accent(for: phase).opacity(isHovering ? 0.5 : 0.3),
                            radius: isHovering ? 14 : 8, y: 3)
                Image(systemName: systemName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    // O glifo de play é opticamente descentrado; compensa.
                    .offset(x: systemName == "play.fill" ? 2 : 0)
            }
            .frame(width: 62, height: 62)
            .scaleEffect(isHovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
        .accessibilityLabel(accessibilityText)
    }
}

/// Ação secundária: ícone discreto com legenda em caixa alta (RESET / SKIP).
struct GhostControl: View {
    let systemName: String
    let title: String
    var isEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
            }
            .foregroundStyle(color)
            .frame(width: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 && isEnabled }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .accessibilityLabel(title)
    }

    private var color: Color {
        guard isEnabled else { return Brand.textFaint }
        return isHovering ? Brand.textPrimary : Brand.textSecondary
    }
}

/// Cartão translúcido usado como base das telas.
struct BrandCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Brand.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
            )
    }
}
