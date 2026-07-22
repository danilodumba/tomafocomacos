import SwiftUI

/// Aviso flutuante exibido quando o usuário tenta abrir um app bloqueado (RF-03, RF-08.1).
struct BlockedAppToastView: View {
    let appName: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.accent(for: .focus))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(appName) está bloqueado")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)

                Text("Ele não abre enquanto durar o foco.")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)          // legível sobre qualquer janela por baixo
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
        )
        .fixedSize()
    }
}
