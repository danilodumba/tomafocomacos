import SwiftUI

/// Ponto de entrada do app. Monta o `AppContainer` (Composition Root) e as cenas SwiftUI.
///
/// App **só barra de menus** (`LSUIElement: true`): não há janela principal — o popover do
/// `MenuBarExtra` mostra a `MainView` inteira. O ícone do Dock e o menu superior aparecem só
/// enquanto Tarefas/Relatórios/Configurações estão abertas (`ActivationPolicyController`).
@main
struct TomafocoApp: App {
    @StateObject private var container = AppContainer.live()

    var body: some Scene {
        // PRIMEIRA cena de propósito: a cena inicial é a que o SwiftUI abre no lançamento.
        // Com uma `Window` na frente, a janela de Tarefas subia sozinha ao abrir o app.
        MenuBarExtra {
            MainView(viewModel: container.timerViewModel, updater: container.updater,
                     kanbanBoards: container.kanbanBoardList)
        } label: {
            MenuBarLabel(viewModel: container.timerViewModel)
        }
        .menuBarExtraStyle(.window)

        tasksWindow
        // "Buscar atualizações…" logo abaixo de "Sobre o Tomafoco", onde o macOS ensinou o
        // usuário a procurar. Fica nesta cena porque o menu do app só existe quando alguma
        // janela está aberta (o app é `.accessory` no resto do tempo); o mesmo item também
        // vive no menu de engrenagem do popover.
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesMenuItem(updater: container.updater)
            }
            // ⌥⌘K abre o último quadro Kanban usado; os demais quadros vêm logo abaixo. Só
            // existe com alguma janela aberta (o app é `.accessory` no resto do tempo); fora
            // disso o caminho é o menu de engrenagem do popover.
            CommandGroup(before: .windowList) {
                OpenKanbanMenuItem(boards: container.kanbanBoardList)
            }
        }

        reportsWindow
        projectReportsWindow
        kanbanWindow
        documentWindow
        projectDocumentWindow

        Settings {
            SettingsView(
                settingsViewModel: container.settingsViewModel,
                blockListViewModel: container.blockListViewModel,
                unlockPasswordViewModel: container.unlockPasswordViewModel,
                updater: container.updater,
                kanbanSettingsViewModel: container.kanbanSettingsViewModel
            )
        }
    }

    // `SceneBuilder` não aceita `if #available` (não tem `buildEither`), então
    // `defaultLaunchBehavior(.suppressed)` (macOS 15+) está fora de alcance com deployment
    // target 14 — quem impede a abertura automática é a ordem das cenas acima.
    private var tasksWindow: some Scene {
        Window("Tarefas", id: "tasks") {
            TasksView(viewModel: container.tasksViewModel, documentIndex: container.documentIndex)
                .frame(minWidth: 520, minHeight: 540)
        }
    }

    /// Kanban em janela própria (FEAT-005) para usar tela cheia e Split View — uma janela por
    /// quadro (FEAT-008): o `WindowGroup(for:)` reaproveita a janela já aberta do mesmo quadro.
    /// Nunca abre sozinho no lançamento (o `MenuBarExtra` é a primeira cena).
    private var kanbanWindow: some Scene {
        WindowGroup("Kanban", id: KanbanBoardWindow.sceneID, for: UUID.self) { $boardID in
            KanbanBoardWindow(boardID: $boardID, documentIndex: container.documentIndex,
                              viewModel: container.makeKanbanViewModel(boardID: boardID))
                .frame(minWidth: 840, minHeight: 540)
                .allowsFullScreen()
        }
        .defaultSize(width: 1200, height: 760)
    }

    private var reportsWindow: some Scene {
        Window("Relatórios — Tarefas", id: "reports") {
            ReportsView(viewModel: container.reportsViewModel)
                .frame(minWidth: 560, minHeight: 560)
        }
    }
}

extension TomafocoApp {
    /// Documento em markdown de uma tarefa (FEAT-007) — uma janela por tarefa: o
    /// `WindowGroup(for:)` reaproveita a janela já aberta do mesmo `UUID`. Nunca abre sozinho no
    /// lançamento (o `MenuBarExtra` é a primeira cena).
    fileprivate var documentWindow: some Scene {
        WindowGroup("Documento", id: DocumentWindow.taskSceneID, for: UUID.self) { $taskID in
            if let taskID {
                DocumentWindow(viewModel: container.makeDocumentViewModel(taskID: taskID))
                    .id(taskID)
                    .frame(minWidth: 560, minHeight: 420)
                    .allowsFullScreen()
            } else {
                Text("Nenhuma tarefa selecionada.")
                    .foregroundStyle(Brand.textFaint)
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .defaultSize(width: 980, height: 720)
    }

    /// Documento de projeto (FEAT-009) — uma janela por documento; mesma janela do documento da
    /// tarefa, com o título editável. Nunca abre sozinho no lançamento.
    fileprivate var projectDocumentWindow: some Scene {
        WindowGroup("Documento do projeto", id: DocumentWindow.projectSceneID, for: UUID.self) { $documentID in
            if let documentID {
                DocumentWindow(viewModel: container.makeProjectDocumentViewModel(documentID: documentID))
                    .id(documentID)
                    .frame(minWidth: 560, minHeight: 420)
                    .allowsFullScreen()
            } else {
                Text("Nenhum documento selecionado.")
                    .foregroundStyle(Brand.textFaint)
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
        .defaultSize(width: 980, height: 720)
    }

    /// Relatórios › Projetos (FEAT-006 / RF-10.7).
    fileprivate var projectReportsWindow: some Scene {
        Window("Relatórios — Projetos", id: "project-reports") {
            ProjectReportsView(viewModel: container.projectReportsViewModel)
                .frame(minWidth: 620, minHeight: 520)
        }
        .defaultSize(width: 760, height: 640)
    }
}

/// O rótulo do `MenuBarExtra` precisa observar o `TimerViewModel` DIRETAMENTE: `AppContainer`
/// nunca publica mudanças, então ler `container.timerViewModel.menuBarLabel` no body do App
/// congelaria o texto no valor inicial — o countdown jamais apareceria na barra de menus.
private struct MenuBarLabel: View {
    @ObservedObject var viewModel: TimerViewModel
    /// Escolhe a arte pronta do tema. O `NSImage` cacheia o desenho, então uma cor dinâmica
    /// dentro dele congelaria no tema da primeira renderização.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            // `.renderingMode(.original)` preserva a metade cyan do anel; sem ele o SwiftUI
            // trataria a imagem como template e pintaria tudo de uma cor só.
            Image(nsImage: MenuBarIcon.image(for: colorScheme))
                .renderingMode(.original)
            if let symbol = viewModel.menuBarSymbol {
                Image(systemName: symbol)
            }
            if !viewModel.menuBarLabel.isEmpty {
                Text(viewModel.menuBarLabel)
            }
            // Build de desenvolvimento roda ao lado do app instalado — dois tomates iguais na
            // barra confundiriam. Só `Text`/`Image` renderizam aqui.
            if AppEnvironment.current.isDevelopment {
                Text("DEV")
            }
        }
    }
}

/// Idem para o item de menu: precisa observar o `UpdaterController` direto para desabilitar
/// enquanto uma checagem está em andamento.
private struct CheckForUpdatesMenuItem: View {
    @ObservedObject var updater: UpdaterController

    var body: some View {
        Button("Buscar atualizações…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

/// Item "Kanban" (⌥⌘K, último quadro usado) do menu Janela e, com mais de um quadro, um submenu
/// com todos (FEAT-008). View própria porque `openWindow` vem do ambiente.
private struct OpenKanbanMenuItem: View {
    @ObservedObject var boards: KanbanBoardList
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Kanban") { openWindow.kanbanBoard(fallback: boards.items) }
            .keyboardShortcut("k", modifiers: [.command, .option])
        if boards.items.count > 1 {
            Menu("Quadros Kanban") {
                KanbanBoardMenuItems(boards: boards)
            }
        }
    }
}
