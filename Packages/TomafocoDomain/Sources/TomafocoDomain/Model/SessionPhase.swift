import Foundation

/// Fase atual do ciclo Pomodoro. `Codable` para persistência do failsafe (RF-01.5).
public enum SessionPhase: String, Equatable, Codable, Sendable {
    case idle
    case focus
    case shortBreak
    case longBreak

    /// Apenas a fase de foco aplica bloqueios de sites e apps.
    public var appliesBlocking: Bool { self == .focus }
}
