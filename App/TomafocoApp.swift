import SwiftUI

/// Ponto de entrada do app. Monta o `AppContainer` (Composition Root) e as cenas SwiftUI.
///
/// App normal, com ícone no Dock (`LSUIElement: false`). O `MenuBarExtra` é um atalho: abre o
/// formulário compacto (`MenuBarView`, 250pt) sem precisar da janela principal.
@main
struct TomafocoApp: App {
    @StateObject private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup("Tomafoco") {
            MainView(viewModel: container.timerViewModel, updater: container.updater)
                .frame(width: 340, height: 480)
                .task { await container.recoverFromCrashIfNeeded() }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        // "Buscar atualizações…" logo abaixo de "Sobre o Tomafoco", onde o macOS ensinou o
        // usuário a procurar. O mesmo item também vive no menu "•••" (janela e barra de menus).
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesMenuItem(updater: container.updater)
            }
        }

        Window("Tarefas", id: "tasks") {
            TasksView(viewModel: container.tasksViewModel)
                .frame(minWidth: 520, minHeight: 540)
        }

        Window("Relatórios", id: "reports") {
            ReportsView(viewModel: container.reportsViewModel)
                .frame(minWidth: 560, minHeight: 560)
        }

        MenuBarExtra {
            MenuBarView(viewModel: container.timerViewModel)
        } label: {
            MenuBarLabel(viewModel: container.timerViewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settingsViewModel: container.settingsViewModel,
                blockListViewModel: container.blockListViewModel,
                updater: container.updater
            )
        }
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
