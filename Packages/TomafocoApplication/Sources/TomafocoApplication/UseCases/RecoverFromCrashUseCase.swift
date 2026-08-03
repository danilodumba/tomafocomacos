import Foundation
import TomafocoDomain

/// Recuperação após crash/reinício (UC-04, RNF-02).
///
/// Lê a sessão de foco persistida (failsafe). Se ela já deveria ter terminado, restaura
/// tudo silenciosamente. Se ainda está vigente, devolve a decisão para a UI (retomar/encerrar).
/// Garante que NENHUM caminho deixe o usuário bloqueado sem uma sessão correspondente.
public final class RecoverFromCrashUseCase {
    public enum Result: Equatable {
        /// Não havia sessão pendente.
        case nothingToRecover
        /// Sessão expirada foi restaurada (bloqueio removido) automaticamente.
        case restoredExpiredSession
        /// Sessão ainda vigente — a UI deve perguntar ao usuário (retomar ou encerrar).
        case pendingActiveSession(PomodoroSession)
    }

    private let sessions: SessionRepository
    private let websiteBlocker: WebsiteBlocking
    private let appBlocker: AppBlocking
    private let clock: SessionClock

    public init(
        sessions: SessionRepository,
        websiteBlocker: WebsiteBlocking,
        appBlocker: AppBlocking,
        clock: SessionClock
    ) {
        self.sessions = sessions
        self.websiteBlocker = websiteBlocker
        self.appBlocker = appBlocker
        self.clock = clock
    }

    public func execute() async -> Result {
        guard let session = try? sessions.loadActive() else { return .nothingToRecover }

        if session.isExpired(now: clock.now) {
            await restoreEverything()
            let record = SessionRecord(
                sessionID: session.id, phase: session.phase,
                startedAt: session.startedAt, endedAt: session.endsAt,
                outcome: .recovered, cycleNumber: session.cycleNumber,
                taskIDs: session.taskIDs
            )
            try? sessions.appendToHistory(record)
            try? sessions.clearActive()
            return .restoredExpiredSession
        }

        return .pendingActiveSession(session)
    }

    /// Encerra à força uma sessão pendente escolhida pelo usuário (remove bloqueios).
    public func discardPendingSession() async {
        await restoreEverything()
        try? sessions.clearActive()
    }

    private func restoreEverything() async {
        appBlocker.deactivate()
        try? await websiteBlocker.deactivate()
    }
}
