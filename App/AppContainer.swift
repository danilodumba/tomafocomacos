import Foundation
import os
import SwiftUI
import TomafocoDomain
import TomafocoApplication
import TomafocoInfrastructure
import TomafocoMarkdown

/// Composition Root: ÚNICO lugar onde as implementações concretas são instanciadas e injetadas.
/// Trocar um adapter (ex.: AppleScript → XPC helper na v2) muda apenas este arquivo (OCP/DIP).
@MainActor
final class AppContainer: ObservableObject {

    /// Página local exibida no lugar do site bloqueado. Fica nos Resources do app.
    private static var blockPageURL: String {
        Bundle.main.url(forResource: "blocked", withExtension: "html")?.absoluteString
            ?? "about:blank"
    }

    let coordinator: SessionCoordinator
    let recover: RecoverFromCrashUseCase
    let manageBlockList: ManageBlockListUseCase

    let timerViewModel: TimerViewModel
    let settingsViewModel: SettingsViewModel
    let blockListViewModel: BlockListViewModel
    let unlockPasswordViewModel: UnlockPasswordViewModel
    /// Bloqueio contínuo com o app aberto (FEAT-002): reaplicado no lançamento e a cada
    /// mudança de flag ou de lista.
    let persistentBlocking: PersistentBlockingController
    let tasksViewModel: TasksViewModel
    /// Aba Kanban das Configurações (FEAT-005) e lista de quadros dos menus (FEAT-008). As
    /// janelas Kanban têm um VM cada (`makeKanbanViewModel`).
    let kanbanSettingsViewModel: KanbanSettingsViewModel
    let kanbanBoardList: KanbanBoardList
    private let manageKanban: ManageKanbanUseCase
    private let manageProjects: ManageProjectsUseCase
    let reportsViewModel: ReportsViewModel
    /// Relatórios › Projetos (FEAT-006 / RF-10.7).
    let projectReportsViewModel: ProjectReportsViewModel
    /// Documento em markdown das tarefas (FEAT-007): selo da lista/Kanban + janelas de documento.
    let documentIndex: TaskDocumentIndex
    private let manageDocuments: ManageTaskDocumentsUseCase
    /// Documentos dos projetos (FEAT-009) — usados pelo cadastro de projetos e pelas janelas.
    let manageProjectDocuments: ManageProjectDocumentsUseCase
    private let manageTasks: ManageTasksUseCase
    private let relay: TaskChangeRelay
    /// Atualização automática (ADR-9). Criado aqui — e não sob demanda numa View — porque o
    /// Sparkle precisa subir junto com o app para agendar a checagem periódica.
    let updater = UpdaterController()
    /// Retido pelo container: sem uma referência forte, a assinatura Combine morre e a tela
    /// cheia do intervalo nunca aparece.
    private let breakOverlay: BreakOverlayPresenter
    /// Idem: é quem põe o app no Dock (com menu superior) enquanto há janela aberta e o tira
    /// quando a última fecha. Sem referência forte os observers morrem.
    private let activationPolicy = ActivationPolicyController()

    private let notificationAdapter: UNNotificationAdapter?

    private init(
        coordinator: SessionCoordinator,
        recover: RecoverFromCrashUseCase,
        manageBlockList: ManageBlockListUseCase,
        manageTasks: ManageTasksUseCase,
        manageKanban: ManageKanbanUseCase,
        manageProjects: ManageProjectsUseCase,
        manageDocuments: ManageTaskDocumentsUseCase,
        manageProjectDocuments: ManageProjectDocumentsUseCase,
        settings: SettingsRepository,
        sessions: SessionRepository,
        tasks: TaskRepository,
        appPicker: ApplicationPicking,
        persistentBlocking: PersistentBlockingController,
        authorizer: ProtectedActionAuthorizer,
        passwordStore: AppUnlockPasswordStoring,
        notificationAdapter: UNNotificationAdapter?
    ) {
        self.persistentBlocking = persistentBlocking
        self.coordinator = coordinator
        self.recover = recover
        self.manageBlockList = manageBlockList
        self.notificationAdapter = notificationAdapter
        self.manageDocuments = manageDocuments
        self.manageProjectDocuments = manageProjectDocuments
        self.manageTasks = manageTasks
        self.manageKanban = manageKanban
        self.manageProjects = manageProjects
        let documentIndex = TaskDocumentIndex(useCase: manageDocuments)
        self.documentIndex = documentIndex
        let timer = TimerViewModel(coordinator: coordinator, settings: settings, manageTasks: manageTasks)
        self.timerViewModel = timer
        let refreshBlocking = { Task { await persistentBlocking.refresh() } }
        self.settingsViewModel = SettingsViewModel(
            settings: settings, loginItem: SMAppServiceLoginItem(),
            authorizer: authorizer, manageTasks: manageTasks,
            onBlockingSettingsChanged: { _ = refreshBlocking() },
            // Escopo do seletor do foco (RF-09.15) mudou: o timer refiltra na hora.
            onFocusScopeChanged: { timer.reloadAvailableTasks() })
        self.blockListViewModel = BlockListViewModel(
            useCase: manageBlockList, appPicker: appPicker,
            onListChanged: { _ = refreshBlocking() })
        self.unlockPasswordViewModel = UnlockPasswordViewModel(store: passwordStore, authorizer: authorizer)
        // Mudança de tarefa numa janela reflete na outra (lista ↔ Kanban, que podem estar lado
        // a lado) e no seletor do timer. Cada VM se relê sozinho; o relay só avisa os demais com
        // `refresh()` — que não avisa de volta, senão as janelas ficariam se avisando em laço.
        let relay = TaskChangeRelay(timer: self.timerViewModel, documentIndex: documentIndex)
        self.relay = relay
        self.tasksViewModel = TasksViewModel(
            useCase: manageTasks, manageProjects: manageProjects, manageProjectDocuments: manageProjectDocuments
        ) {
            relay.tasksChanged(from: .list)
        }
        self.kanbanSettingsViewModel = KanbanSettingsViewModel(
            useCase: manageKanban, manageTasks: manageTasks, manageProjects: manageProjects
        ) { relay.tasksChanged(from: .settings) }
        self.kanbanBoardList = KanbanBoardList(useCase: manageKanban)
        relay.connect(list: tasksViewModel, boardList: kanbanBoardList,
                      boardSettings: kanbanSettingsViewModel, focusSettings: settingsViewModel)
        self.reportsViewModel = ReportsViewModel(sessions: sessions, tasks: tasks)
        self.projectReportsViewModel = ProjectReportsViewModel(
            sessions: sessions, tasks: tasks, manageProjects: manageProjects)
        self.breakOverlay = BreakOverlayPresenter(viewModel: self.timerViewModel)
        self.activationPolicy.start()
    }

    /// Monta o grafo real de dependências do macOS.
    static func live() -> AppContainer {
        // Som + Dock pulando no fim de cada etapa, por cima da notificação do sistema (RF-08.1).
        // O decorador garante o aviso mesmo se o usuário tiver negado notificações.
        let notificationAdapter = UNNotificationAdapter()
        // Aviso na tela quando o usuário tenta abrir um app bloqueado (RF-03).
        let toastPresenter = BlockedAppToastPresenter()
        let notifier = BlockedAppToastNotifier(
            wrapping: PhaseAlertNotifier(
                wrapping: notificationAdapter,
                sound: SystemSoundPlayer(),
                attention: DockAttentionRequester()
            ),
            presenter: toastPresenter
        )

        // Bloqueio de sites por automação do navegador (ADR-8). Substituiu o /etc/hosts:
        // sem root, sem senha e imune a DNS de VPN / DNS-over-HTTPS. Ver `AppleScriptBrowserBlocker`.
        let settings = UserDefaultsSettingsStore()
        let websiteBlocker = AppleScriptBrowserBlocker(
            blockPageURL: Self.blockPageURL,
            scriptRunner: NSAppleScriptRunner(),
            runningApps: WorkspaceRunningApplications(),
            // Relê a cada varredura: mudar o site nas Configurações vale na próxima passada.
            redirectURLProvider: { settings.loadConfiguration().blockedRedirectURL }
        )
        // Senha de desbloqueio (FEAT-002): abrir app bloqueado pede a senha em vez de só encerrar.
        let passwordStore = KeychainAppUnlockPasswordStore(service: AppEnvironment.current.keychainService)
        let unlockPrompt = AppUnlockPromptPresenter()
        let authorizer = ProtectedActionAuthorizer(store: passwordStore, presenter: unlockPrompt)
        let rawAppBlocker = WorkspaceAppBlocker(
            notifier: notifier, passwordStore: passwordStore, prompt: unlockPrompt)

        // Bloqueio contínuo (FEAT-002): decoradores mantêm o bloqueio ao fim do foco quando a
        // flag está ligada. Coordinator e recuperação recebem os decorados e não sabem disso.
        let appBlocker = PersistentAppBlocker(wrapping: rawAppBlocker, settings: settings)
        let persistentWebsiteBlocker = PersistentWebsiteBlocker(wrapping: websiteBlocker, settings: settings)
        let persistentBlocking = PersistentBlockingController(
            apps: appBlocker, websites: persistentWebsiteBlocker,
            onWebsiteFailure: { _ in notifier.notify(.websiteBlockingUnavailable) })
        let clock = DispatchSessionClock()
        // Banco SwiftData (FEAT-006, ADR-11): tarefas, quadro, histórico, sessão ativa e tags.
        // Configurações seguem no UserDefaults e a senha no Keychain.
        let database = Self.openDatabase()
        let sessions = SwiftDataSessionStore(database: database)
        let taskStore = SwiftDataTaskStore(database: database)
        let kanbanStore = SwiftDataKanbanStore(database: database)
        let tagCatalog = SwiftDataTagCatalog(database: database)
        let projectStore = SwiftDataProjectStore(database: database)
        let documentStore = SwiftDataTaskDocumentStore(database: database)
        let projectDocumentStore = SwiftDataProjectDocumentStore(database: database)
        Self.importLegacyJSON(database: database, tasks: taskStore, sessions: sessions, tags: tagCatalog)
        Self.deleteOrphanDocuments(documents: documentStore, projectDocuments: projectDocumentStore)

        let coordinator = SessionCoordinator(
            clock: clock, appBlocker: appBlocker, websiteBlocker: persistentWebsiteBlocker,
            sessions: sessions, settings: settings, notifier: notifier
        )
        let recover = RecoverFromCrashUseCase(
            sessions: sessions, websiteBlocker: persistentWebsiteBlocker,
            appBlocker: appBlocker, clock: clock
        )
        let manageBlockList = ManageBlockListUseCase(settings: settings)
        let appPicker = NSOpenPanelApplicationPicker()

        // Tarefas + importação do Lembretes (RF-09).
        let manageTasks = ManageTasksUseCase(
            tasks: taskStore, importer: EventKitReminderImporter(), now: { clock.now },
            shouldSyncReminderCompletion: { settings.loadConfiguration().syncReminderCompletion },
            tagCatalog: tagCatalog, calendar: .autoupdatingCurrent,
            kanbanBoards: kanbanStore, settings: settings, projects: projectStore,
            // FEAT-007: documento sai junto com a tarefa e acompanha o clone da diária, com o
            // checklist desmarcado — na mesma transação do banco.
            documents: documentStore, unitOfWork: database, checklistResetter: MarkdownChecklistResetter())
        let manageDocuments = ManageTaskDocumentsUseCase(
            documents: documentStore, tasks: taskStore, now: { clock.now })
        // Quadros Kanban (FEAT-005/FEAT-008): lista de quadros numa linha do banco.
        let manageKanban = ManageKanbanUseCase(boards: kanbanStore, tasks: manageTasks, now: { clock.now })
        // Projetos (FEAT-006): apagar projeto + tirar das tarefas numa transação do banco.
        let manageProjects = ManageProjectsUseCase(
            projects: projectStore, tasks: taskStore, unitOfWork: database, now: { clock.now },
            calendar: .autoupdatingCurrent, kanbanBoards: kanbanStore, projectDocuments: projectDocumentStore)
        // Documentos dos projetos (FEAT-009): vários por projeto, saem junto com o projeto.
        let manageProjectDocuments = ManageProjectDocumentsUseCase(
            documents: projectDocumentStore, projects: projectStore, now: { clock.now })

        notificationAdapter.requestAuthorization()

        let container = AppContainer(
            coordinator: coordinator, recover: recover, manageBlockList: manageBlockList,
            manageTasks: manageTasks, manageKanban: manageKanban, manageProjects: manageProjects,
            manageDocuments: manageDocuments, manageProjectDocuments: manageProjectDocuments, settings: settings, sessions: sessions, tasks: taskStore,
            appPicker: appPicker, persistentBlocking: persistentBlocking,
            authorizer: authorizer, passwordStore: passwordStore,
            notificationAdapter: notificationAdapter
        )
        // Sem janela principal não há `.task` de View para disparar isso — o app é só barra
        // de menus e o popover pode nunca ser aberto.
        Task {
            await container.recoverFromCrashIfNeeded()
            // Depois da recuperação: se uma sessão foi retomada, o refresh é no-op (foco ativo);
            // senão liga o bloqueio contínuo desde o lançamento.
            await persistentBlocking.refresh()
        }
        return container
    }

    /// Abre o banco em Application Support. Se nem um banco novo abrir (disco cheio, permissão),
    /// o app sobe com um banco em memória em vez de não abrir — e avisa que nada será salvo.
    private static func openDatabase() -> TomafocoDatabase {
        do {
            return try TomafocoDatabase.open(at: AppEnvironment.current.databaseURL)
        } catch {
            logger.fault("Banco não abriu, usando memória: \(String(describing: error), privacy: .public)")
            let openError = error
            do {
                let database = try TomafocoDatabase.inMemory()
                DatabaseAlert.presentUnavailable(error: openError)
                return database
            } catch {
                // Nem em memória: é defeito de esquema (`@Model` mudado sem V2), não de disco.
                // Explicar e sair limpo é melhor que o trap. Só este alerta é síncrono — o
                // enfileirado nunca apareceria antes do `exit`.
                logger.fault("Banco em memória também falhou: \(String(describing: error), privacy: .public)")
                DatabaseAlert.presentFatalAndExit(error: error)
            }
        }
    }

    /// Migração única dos JSON antigos (P5). Falha aqui não impede o app de abrir: os JSON
    /// continuam no lugar e a migração é tentada de novo no próximo lançamento.
    private static func importLegacyJSON(database: TomafocoDatabase, tasks: SwiftDataTaskStore,
                                         sessions: SwiftDataSessionStore, tags: SwiftDataTagCatalog) {
        // Banco em memória = disco indisponível: importar renomearia os JSON sem salvar nada.
        // Os arquivos ficam onde estão e a migração roda quando o banco voltar a abrir.
        guard !database.isInMemory else { return }
        if database.wasReset { DatabaseAlert.presentReset() }
        let importer = JSONToSwiftDataImporter(
            database: database, tasks: tasks, sessions: sessions, tags: tags,
            directory: AppEnvironment.current.databaseURL.deletingLastPathComponent(),
            legacyTags: UserDefaultsTagCatalog(), now: { Date() })
        do {
            let report = try importer.run()
            if !report.unreadableFiles.isEmpty {
                DatabaseAlert.presentUnreadableFiles(report.unreadableFiles)
            }
        } catch {
            logger.error("Migração JSON → banco falhou: \(String(describing: error), privacy: .public)")
            DatabaseAlert.presentMigrationFailed(error: error)
        }
    }

    /// Rede de segurança do FEAT-007: documento de tarefa que não existe mais é apagado. Falha
    /// aqui só deixa o órfão para o próximo lançamento.
    private static func deleteOrphanDocuments(documents: SwiftDataTaskDocumentStore,
                                              projectDocuments: SwiftDataProjectDocumentStore) {
        do {
            try documents.deleteOrphans()
            try projectDocuments.deleteOrphans()
        } catch {
            logger.error("Limpeza de documentos órfãos falhou: \(String(describing: error), privacy: .public)")
        }
    }

    /// VM de uma janela Kanban (FEAT-008). Registrado no relay (referência fraca): mudança feita
    /// numa janela reflete nas dos outros quadros.
    func makeKanbanViewModel(boardID: UUID?) -> KanbanViewModel {
        let relay = relay
        // Fraca: o VM guarda este closure — forte seria ciclo e a janela fechada nunca liberaria.
        weak var origin: KanbanViewModel?
        let created = KanbanViewModel(
            boardID: boardID, useCase: manageKanban, manageTasks: manageTasks, manageProjects: manageProjects,
            manageProjectDocuments: manageProjectDocuments
        ) {
            if let origin { relay.tasksChanged(from: .board(origin)) }
        }
        origin = created
        relay.register(board: created)
        return created
    }

    /// VM de uma janela de documento de tarefa (FEAT-007) — registrado no relay para acompanhar
    /// renomear/apagar a tarefa em outra janela.
    func makeDocumentViewModel(taskID: UUID) -> DocumentViewModel {
        let index = documentIndex
        let viewModel = DocumentViewModel(
            source: TaskDocumentSource(taskID: taskID, documents: manageDocuments, tasks: manageTasks),
            onPresenceChanged: { index.reload() })
        relay.register(documentWindow: viewModel)
        return viewModel
    }

    /// Janela de um documento de projeto (FEAT-009). No relay para ver projeto/documento apagado.
    func makeProjectDocumentViewModel(documentID: UUID) -> DocumentViewModel {
        let viewModel = DocumentViewModel(
            source: ProjectDocumentSource(documentID: documentID, documents: manageProjectDocuments,
                                          projects: manageProjects),
            onPresenceChanged: { ProjectDocumentsChange.post() })
        relay.register(documentWindow: viewModel)
        return viewModel
    }

    private static let logger = Logger(subsystem: "com.dsdumba.tomafoco", category: "AppContainer")

    /// Executado no lançamento: resolve sessões órfãs (UC-04) e pergunta ao usuário o que fazer
    /// com uma sessão que sobreviveu ao encerramento.
    func recoverFromCrashIfNeeded() async {
        let result = await recover.execute()
        timerViewModel.handleRecovery(result, recover: recover)

        guard let session = timerViewModel.pendingRecovery else { return }
        // O `LaunchAlert` espera o lançamento terminar e enfileira atrás dos avisos do banco.
        switch await RecoveryAlert.present(description: timerViewModel.recoveryDescription(for: session)) {
        case .resume: await timerViewModel.resumeRecoveredSession()
        case .discard: await timerViewModel.discardRecoveredSession()
        }
    }
}
