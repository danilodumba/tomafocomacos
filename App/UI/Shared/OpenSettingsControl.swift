import SwiftUI

/// Controle que abre a janela de Configurações, opcionalmente já numa aba. Único lugar com o
/// branch de disponibilidade: `SettingsLink` só existe no macOS 14+ (e não aceita ação própria
/// — a aba é escolhida por um gesto simultâneo ao clique); no 13 vale o seletor padrão.
struct OpenSettingsControl<Label: View>: View {
    var tab: SettingsTab?
    @ViewBuilder let label: () -> Label

    var body: some View {
        if #available(macOS 14, *) {
            SettingsLink(label: label)
                .simultaneousGesture(TapGesture().onEnded { selectTab() })
        } else {
            Button {
                selectTab()
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                label()
            }
        }
    }

    private func selectTab() {
        if let tab { SettingsTab.select(tab) }
    }
}
