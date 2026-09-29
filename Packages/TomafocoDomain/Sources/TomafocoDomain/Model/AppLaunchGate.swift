import Foundation

/// Decide o que fazer quando um app bloqueado é aberto (FEAT-002). Pura: o adapter de
/// `NSWorkspace` observa os lançamentos e pergunta aqui.
///
/// A liberação por senha vale **até o app ser fechado** e é chaveada por PID, não por bundle ID:
/// se a instância fechar durante o prompt e for relançada, a notificação de término da velha pode
/// chegar depois da liberação — chaveado por bundle ID, ela apagaria a liberação da nova.
///
/// A liberação sobrevive a `activate`/`deactivate` do bloqueio: a senha vale no foco e fora dele,
/// então a virada de fase não pode fechar um app que o usuário acabou de liberar.
public struct AppLaunchGate: Sendable {

    public enum Decision: Equatable, Sendable {
        /// Instância já liberada por senha — deixa abrir.
        case allow
        /// Sem senha cadastrada: encerra e avisa (comportamento clássico).
        case terminate
        /// Esconde o app e pede a senha (certa → reaparece; cancelou → encerra).
        case terminateAndPrompt
        /// Encerra sem novo prompt nem aviso: já há um prompt aberto para este app
        /// (usuário clicou várias vezes, ou o app relança sozinho).
        case terminateSilently
    }

    private var unlockedPIDs: Set<Int32> = []
    /// Apps liberados aguardando o relançamento feito pelo próprio Tomafoco.
    private var pendingLaunch: Set<String> = []
    private var prompting: Set<String> = []

    public init() {}

    /// Um app **bloqueado** acabou de abrir.
    public mutating func decideLaunch(bundleID: String, pid: Int32, hasPassword: Bool) -> Decision {
        if unlockedPIDs.contains(pid) { return .allow }
        if pendingLaunch.remove(bundleID) != nil {
            unlockedPIDs.insert(pid)
            return .allow
        }
        if prompting.contains(bundleID) { return .terminateSilently }
        guard hasPassword else { return .terminate }
        prompting.insert(bundleID)
        return .terminateAndPrompt
    }

    public func isUnlocked(pid: Int32) -> Bool {
        unlockedPIDs.contains(pid)
    }

    /// Há prompt aberto para este app? Enquanto houver, reativar o bloqueio não pode encerrá-lo.
    public func isPrompting(bundleID: String) -> Bool {
        prompting.contains(bundleID)
    }

    /// Senha certa. `runningPID` é a instância que esperou o prompt (escondida) — ela passa a ser
    /// a liberada. `nil` → a instância fechou durante o prompt; a próxima abertura é liberada.
    public mutating func unlock(bundleID: String, runningPID: Int32?) {
        prompting.remove(bundleID)
        if let runningPID {
            unlockedPIDs.insert(runningPID)
        } else {
            pendingLaunch.insert(bundleID)
        }
    }

    /// Usuário cancelou o prompt: app fica fechado, próxima abertura pergunta de novo.
    public mutating func cancelPrompt(bundleID: String) {
        prompting.remove(bundleID)
    }

    /// O relançamento falhou — sem isso, a próxima abertura manual passaria sem senha.
    public mutating func abandonPendingLaunch(bundleID: String) {
        pendingLaunch.remove(bundleID)
    }

    /// Uma instância fechou: a liberação dela acaba aqui.
    public mutating func didTerminate(pid: Int32) {
        unlockedPIDs.remove(pid)
    }
}
