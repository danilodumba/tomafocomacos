import Foundation
import TomafocoDomain

#if canImport(AppKit)
import AppKit

/// Bloqueio de apps via `NSWorkspace` (RF-03). Encerra os apps da lista em execução e observa
/// novos lançamentos para encerrá-los durante a sessão. Não faz polling (usa notificações do sistema).
public final class WorkspaceAppBlocker: AppBlocking, @unchecked Sendable {

    /// Quando `true`, usa `forceTerminate()` (sem chance de o app cancelar) — opt-in (RF-03.2).
    public var forceTerminate: Bool

    private let workspace: NSWorkspace
    private let notifier: UserNotifying?
    private var observer: NSObjectProtocol?
    private var blockedBundleIDs: Set<String> = []

    public init(
        workspace: NSWorkspace = .shared,
        notifier: UserNotifying? = nil,
        forceTerminate: Bool = false
    ) {
        self.workspace = workspace
        self.notifier = notifier
        self.forceTerminate = forceTerminate
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
            self.terminate(app)
            self.notifier?.notify(.appBlocked(name: app.localizedName ?? bundleID))
        }
    }

    public func deactivate() {
        if let observer { workspace.notificationCenter.removeObserver(observer) }
        observer = nil
        blockedBundleIDs = []
    }

    private func terminateRunning(in ids: Set<String>) {
        for app in workspace.runningApplications
        where app.bundleIdentifier.map(ids.contains) == true {
            terminate(app)
        }
    }

    private func terminate(_ app: NSRunningApplication) {
        _ = forceTerminate ? app.forceTerminate() : app.terminate()
    }
}
#endif
