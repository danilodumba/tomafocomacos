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

        MenuBarExtra {
            MenuBarView(viewModel: container.timerViewModel)
        } label: {
            Text(container.timerViewModel.menuBarLabel)
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
