import SwiftUI
import TomafocoDomain

/// Conteúdo da janela de senha. Verifica a cada tentativa; após 3 erros seguidos, trava por 5s
/// — freia chute em série sem punir quem só errou a digitação.
struct AppUnlockPromptView: View {
    let title: String
    let message: String
    let confirmTitle: String
    let verify: (String) -> Bool
    let onUnlock: () -> Void
    let onCancel: () -> Void

    private static let maxAttempts = 3
    private static let cooldown: TimeInterval = 5

    @State private var password = ""
    @State private var errorText: String?
    @State private var failures = 0
    @State private var lockedUntil: Date?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Brand.cyan)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Senha", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(submit)
                .disabled(isLocked)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.danger)
            }

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.cyan)
                    .disabled(password.isEmpty || isLocked)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Brand.surfaceStroke, lineWidth: 1)
        )
        .onAppear { fieldFocused = true }
    }

    private var isLocked: Bool {
        guard let lockedUntil else { return false }
        return lockedUntil > Date()
    }

    private func submit() {
        guard !password.isEmpty, !isLocked else { return }
        if verify(password) {
            onUnlock()
            return
        }
        password = ""
        failures += 1
        if failures >= Self.maxAttempts {
            failures = 0
            let until = Date().addingTimeInterval(Self.cooldown)
            lockedUntil = until
            errorText = "Muitas tentativas. Aguarde \(Int(Self.cooldown))s."
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.cooldown) {
                lockedUntil = nil
                errorText = nil
                fieldFocused = true
            }
        } else {
            errorText = "Senha incorreta."
        }
    }
}
