import SwiftUI

/// Controle que abre a janela de Configurações, opcionalmente já numa aba. `SettingsLink` não
/// aceita ação própria — a aba é escolhida por um gesto simultâneo ao clique.
struct OpenSettingsControl<Label: View>: View {
    var tab: SettingsTab?
    /// Roda junto com o clique, antes de as Configurações aparecerem (ex.: o quadro Kanban
    /// escolhe qual quadro a aba vai mostrar — FEAT-008).
    var onOpen: (() -> Void)? = nil
    @ViewBuilder let label: () -> Label

    var body: some View {
        SettingsLink(label: label)
            .simultaneousGesture(TapGesture().onEnded { selectTab() })
    }

    private func selectTab() {
        onOpen?()
        if let tab { SettingsTab.select(tab) }
    }
}
