import SwiftUI

/// Menu de engrenagem do cabeçalho da `MainView` (popover da barra de menus): tudo que não é
/// o timer em si — tarefas, relatórios, configurações, atualização e sair.
struct OverflowMenu: View {
    /// Observado DIRETAMENTE (não via `AppContainer`): sem isso o item de atualização não
    /// reagiria a `canCheckForUpdates` — mesma armadilha do rótulo do `MenuBarExtra`.
    @ObservedObject var updater: UpdaterController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            Button("Tarefas…") { open("tasks") }
            Button("Relatórios…") { open("reports") }
            settingsButton
            Divider()
            Button("Buscar atualizações…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
            Divider()
            Button("Sair do Tomafoco") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.textSecondary)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Mais opções")
    }

    /// Abre uma janela e traz o app à frente — necessário porque, como app `.accessory`
    /// (sem Dock), a janela abriria atrás sem o `activate`.
    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// `SettingsLink` só existe no macOS 14+; no 13 usamos o seletor padrão.
    @ViewBuilder private var settingsButton: some View {
        if #available(macOS 14, *) {
            SettingsLink { Text("Configurações…") }
        } else {
            Button("Configurações…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }
}
