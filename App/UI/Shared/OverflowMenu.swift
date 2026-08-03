import SwiftUI

/// Menu de engrenagem compartilhado pela janela principal e pela barra de menus (item 2):
/// os mesmos itens nos dois lugares. Na barra também oferece "Abrir janela principal" (item 10),
/// já que o app não abre janela sozinho ao iniciar.
struct OverflowMenu: View {
    /// Observado DIRETAMENTE (não via `AppContainer`): sem isso o item de atualização não
    /// reagiria a `canCheckForUpdates` — mesma armadilha do rótulo do `MenuBarExtra`.
    @ObservedObject var updater: UpdaterController
    /// Mostra o item "Abrir janela principal" (só faz sentido na barra de menus).
    var showsOpenMainWindow: Bool = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            if showsOpenMainWindow {
                Button("Abrir janela principal") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider()
            }
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
