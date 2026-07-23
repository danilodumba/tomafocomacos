import SwiftUI

/// Ponto de entrada do app. Monta o `AppContainer` (Composition Root) e as cenas SwiftUI.
@main
struct TomafocoApp: App {
    @StateObject private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup("Tomafoco") {
            MainView(viewModel: container.timerViewModel)
                .frame(width: 340, height: 480)
                .task { await container.recoverFromCrashIfNeeded() }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window("Tarefas & Relatórios", id: "tasks") {
            TasksReportsWindow(
                tasksViewModel: container.tasksViewModel,
                reportsViewModel: container.reportsViewModel
            )
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
                blockListViewModel: container.blockListViewModel
            )
        }
    }
}

/// O rótulo do `MenuBarExtra` precisa observar o `TimerViewModel` DIRETAMENTE: `AppContainer`
/// nunca publica mudanças, então ler `container.timerViewModel.menuBarLabel` no body do App
/// congelaria o texto no valor inicial — o countdown jamais apareceria na barra de menus.
private struct MenuBarLabel: View {
    @ObservedObject var viewModel: TimerViewModel

    var body: some View {
        Text(viewModel.menuBarLabel)
    }
}
