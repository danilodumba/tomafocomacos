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
            Button("Kanban…") { open("kanban") }
            Button("Relatórios…") { open("reports") }
            OpenSettingsControl { Text("Configurações…") }
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
}
