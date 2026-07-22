import SwiftUI
import AppKit
import TomafocoDomain

/// Tokens visuais do Tomafoco, derivados da identidade **DDS.TEC**.
///
/// As cores-base saem dos SVGs oficiais da marca; os tokens semânticos (`textPrimary`,
/// `surface`, …) são adaptativos: resolvem sozinhos em claro/escuro via `NSColor` dinâmico,
/// então nenhuma View precisa ler `@Environment(\.colorScheme)`.
enum Brand {

    // MARK: - Cores da marca (fixas)

    static let cyan = Color(hex: 0x17B9EB)       // primária DDS
    static let cyanLight = Color(hex: 0x94DCF2)
    static let cyanDeep = Color(hex: 0x0D6985)
    static let navy = Color(hex: 0x08143E)       // fundo institucional
    static let navyLift = Color(hex: 0x0F2360)   // navy clareado, para gradientes

    // MARK: - Tokens semânticos (adaptativos)

    static let textPrimary = Color.adaptive(light: navy, dark: .white)
    static let textSecondary = Color.adaptive(
        light: navy.opacity(0.55), dark: Color.white.opacity(0.62))
    static let textFaint = Color.adaptive(
        light: navy.opacity(0.38), dark: Color.white.opacity(0.42))

    /// Fundo da janela — gradiente diagonal sutil.
    static var background: LinearGradient {
        LinearGradient(
            colors: [
                .adaptive(light: Color(hex: 0xFBFDFF), dark: navy),
                .adaptive(light: Color(hex: 0xE6F3FB), dark: navyLift)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Superfície de cartão sobre o fundo.
    static let surface = Color.adaptive(
        light: Color.white.opacity(0.75), dark: Color.white.opacity(0.06))
    static let surfaceStroke = Color.adaptive(
        light: navy.opacity(0.08), dark: Color.white.opacity(0.10))

    /// Trilho do anel de progresso (parte não percorrida).
    static let ringTrack = Color.adaptive(
        light: navy.opacity(0.08), dark: Color.white.opacity(0.10))

    static let danger = Color.adaptive(light: Color(hex: 0xC0392B), dark: Color(hex: 0xFF7A6B))

    // MARK: - Acento por fase

    /// Foco usa a cyan da marca; intervalos usam a variante que mantém contraste no tema atual.
    static func accent(for phase: SessionPhase) -> Color {
        switch phase {
        case .focus, .idle: return cyan
        case .shortBreak, .longBreak: return .adaptive(light: cyanDeep, dark: cyanLight)
        }
    }

    /// Gradiente do arco de progresso — mesma lógica de acento, com brilho na ponta.
    static func accentGradient(for phase: SessionPhase) -> AngularGradient {
        let base = accent(for: phase)
        return AngularGradient(
            colors: [base.opacity(0.55), base, base.opacity(0.95)],
            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
        )
    }
}

// MARK: - Helpers de cor

extension Color {

    /// Cor de hex 0xRRGGBB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Cor que se resolve conforme a aparência do sistema (claro/escuro), inclusive quando o
    /// usuário troca o tema com o app aberto — `NSColor` dinâmico reavalia sozinho.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}
