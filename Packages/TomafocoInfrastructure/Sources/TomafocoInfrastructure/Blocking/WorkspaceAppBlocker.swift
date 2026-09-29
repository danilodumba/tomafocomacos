import Foundation
import TomafocoDomain

#if canImport(AppKit)
import AppKit

/// Bloqueio de apps via `NSWorkspace` (RF-03). Encerra os apps da lista em execução e observa
/// novos lançamentos para encerrá-los durante a sessão. Não faz polling (usa notificações do sistema).
///
/// Com senha de desbloqueio cadastrada (FEAT-002), abrir um app bloqueado **esconde** o app e
/// pede a senha; certa → o app reaparece e fica liberado até ser fechado; cancelou → encerrado.
/// Quem decide é o `AppLaunchGate` (puro, testado); aqui só há a cola com o `NSWorkspace`.
///
/// Por que esconder e não encerrar + relançar: `didLaunchApplicationNotification` chega antes de
/// o app terminar de carregar, e nessa hora muitos apps ignoram o `terminate()` — o app ficava
/// vivo (ou fechava bem depois) e o relançamento nunca acontecia. Esconder também evita o
/// "abre e fecha" antes da senha.
public final class WorkspaceAppBlocker: AppBlocking, @unchecked Sendable {

    /// Quando `true`, usa `forceTerminate()` (sem chance de o app cancelar) — opt-in (RF-03.2).
    public var forceTerminate: Bool

    private let workspace: NSWorkspace
    private let notifier: UserNotifying?
    private let passwordStore: AppUnlockPasswordStoring?
    private let prompt: AppUnlockPrompting?
    private var observer: NSObjectProtocol?
    /// Vive enquanto o blocker existir, e não só com o bloqueio ativo: a liberação por senha
    /// sobrevive à virada foco ↔ fora do foco, então o fim do app precisa ser visto sempre.
    private var terminationObserver: NSObjectProtocol?
    private var blockedBundleIDs: Set<String> = []

    private let lock = NSLock()
    private var gate = AppLaunchGate()

    public init(
        workspace: NSWorkspace = .shared,
        notifier: UserNotifying? = nil,
        passwordStore: AppUnlockPasswordStoring? = nil,
        prompt: AppUnlockPrompting? = nil,
        forceTerminate: Bool = false
    ) {
        self.workspace = workspace
        self.notifier = notifier
        self.passwordStore = passwordStore
        self.prompt = prompt
        self.forceTerminate = forceTerminate

        terminationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.withLock { self?.gate.didTerminate(pid: app.processIdentifier) }
        }
    }

    deinit {
        if let terminationObserver { workspace.notificationCenter.removeObserver(terminationObserver) }
        if let observer { workspace.notificationCenter.removeObserver(observer) }
    }

    public func activate(blockedBundleIDs: Set<String>) {
        // Idempotência (RNF-01): reativar sem desativar antes sobrescreveria `observer` e vazaria
        // o anterior — cada relançamento passaria a gerar terminate + aviso em dobro.
        deactivate()
        self.blockedBundleIDs = blockedBundleIDs
        terminateRunning(in: blockedBundleIDs)

        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  self.blockedBundleIDs.contains(bundleID) else { return }
            self.handleBlockedLaunch(app, bundleID: bundleID)
        }
    }

    public func deactivate() {
        if let observer { workspace.notificationCenter.removeObserver(observer) }
        observer = nil
        blockedBundleIDs = []
    }

    // MARK: - Lançamento de app bloqueado

    private func handleBlockedLaunch(_ app: NSRunningApplication, bundleID: String) {
        let canPrompt = prompt != nil && passwordStore?.hasPassword == true
        let decision = withLock {
            gate.decideLaunch(bundleID: bundleID, pid: app.processIdentifier, hasPassword: canPrompt)
        }
        let name = app.localizedName ?? bundleID

        switch decision {
        case .allow:
            return
        case .terminate:
            terminateReliably(app)
            notifier?.notify(.appBlocked(name: name))
        case .terminateSilently:
            terminateReliably(app)
        case .terminateAndPrompt:
            Task { @MainActor [weak self] in await self?.askPassword(for: app, bundleID: bundleID, name: name) }
        }
    }

    @MainActor
    private func askPassword(for app: NSRunningApplication, bundleID: String, name: String) async {
        guard let prompt, let passwordStore else { return }
        let store = passwordStore

        // Mantém o app escondido enquanto o prompt estiver aberto: recém-lançado, ele ainda vai
        // abrir janelas e se ativar, e clicar no Dock o traria de volta.
        let keepHidden = Task { @MainActor in
            while !Task.isCancelled && !app.isTerminated {
                if !app.isHidden || app.isActive {
                    app.hide()
                    // Devolve o teclado ao prompt — o app bloqueado tinha roubado o foco.
                    NSRunningApplication.current.activate(options: [])
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        let unlocked = await prompt.requestPassword(appName: name) { store.verify($0) }
        keepHidden.cancel()

        guard unlocked else {
            withLock { gate.cancelPrompt(bundleID: bundleID) }
            terminateReliably(app)
            return
        }

        guard app.isTerminated else {
            withLock { gate.unlock(bundleID: bundleID, runningPID: app.processIdentifier) }
            app.unhide()
            app.activate(options: [])
            return
        }

        // Fechou durante o prompt (usuário encerrou pelo Dock, crash): abre de novo, já liberado.
        withLock { gate.unlock(bundleID: bundleID, runningPID: nil) }
        guard let url = app.bundleURL else {
            withLock { gate.abandonPendingLaunch(bundleID: bundleID) }
            return
        }
        do {
            _ = try await workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            withLock { gate.abandonPendingLaunch(bundleID: bundleID) }
        }
    }

    // MARK: - Encerramento

    private func terminateRunning(in ids: Set<String>) {
        for app in workspace.runningApplications
        where app.bundleIdentifier.map(ids.contains) == true {
            // Liberado por senha continua aberto, e o que está esperando o prompt também; os demais
            // caem sem prompt — abrir N diálogos de uma vez no início do foco seria hostil.
            let spared = withLock {
                gate.isUnlocked(pid: app.processIdentifier)
                    || app.bundleIdentifier.map(gate.isPrompting(bundleID:)) == true
            }
            guard !spared else { continue }
            terminateReliably(app)
        }
    }

    private func terminate(_ app: NSRunningApplication) {
        _ = forceTerminate ? app.forceTerminate() : app.terminate()
    }

    /// Encerra e insiste: app recém-lançado costuma ignorar o `terminate()` enquanto termina de
    /// carregar. Repete o pedido algumas vezes antes de desistir (o `forceTerminate` segue opt-in).
    private func terminateReliably(_ app: NSRunningApplication) {
        terminate(app)
        Task { @MainActor [weak self] in
            for delay in [0.5, 1.0, 2.0] as [Double] {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !app.isTerminated else { return }
                // Liberado nesse meio-tempo (senha certa em outra instância) não é encerrado.
                guard let self, !self.withLock({ self.gate.isUnlocked(pid: app.processIdentifier) }) else { return }
                self.terminate(app)
            }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}
#endif
