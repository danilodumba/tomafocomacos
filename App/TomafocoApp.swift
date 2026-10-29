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
            MainView(viewModel: container.timerViewModel, updater: container.updater)
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
            // ⌥⌘K abre o Kanban. Só existe com alguma janela aberta (o app é `.accessory` no
            // resto do tempo); fora disso o caminho é o menu de engrenagem do popover.
            CommandGroup(before: .windowList) {
                OpenKanbanMenuItem()
            }
        }

        reportsWindow
        projectReportsWindow
        kanbanWindow

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
            TasksView(viewModel: container.tasksViewModel)
                .frame(minWidth: 520, minHeight: 540)
        }
    }

    /// Kanban em janela própria (FEAT-005) para usar tela cheia e Split View.
    private var kanbanWindow: some Scene {
        Window("Kanban", id: "kanban") {
            KanbanBoardView(viewModel: container.kanbanViewModel)
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

/// Item "Kanban" (⌥⌘K) do menu Janela. View própria porque `openWindow` vem do ambiente.
private struct OpenKanbanMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Kanban") {
            openWindow(id: "kanban")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("k", modifiers: [.command, .option])
    }
}
