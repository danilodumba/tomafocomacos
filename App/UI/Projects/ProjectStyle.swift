import AppKit
import SwiftUI
import TomafocoDomain

/// Único lugar que conhece cor e ícone de projeto na tela (FEAT-006). Views não escolhem tom.
extension ProjectColor {
    /// Tom adaptativo: mais escuro no tema claro, mais claro no escuro — legível nos dois.
    var color: Color { .adaptive(light: palette.light, dark: palette.dark) }

    /// Tom fixo para papel/PDF (fundo branco): sempre a variante do tema claro. A cor adaptativa
    /// resolveria pelo tema do app e sairia clara demais num PDF gerado em modo escuro.
    var printColor: Color { palette.light }

    private var palette: (light: Color, dark: Color) {
        switch self {
        case .red: return (Color(hex: 0xB83227), Color(hex: 0xFF8A80))
        case .wine: return (Color(hex: 0x7A1F3D), Color(hex: 0xF48FB1))
        case .orange: return (Color(hex: 0xC2610C), Color(hex: 0xFFB060))
        case .amber: return (Color(hex: 0xA16207), Color(hex: 0xFBBF24))
        case .brown: return (Color(hex: 0x7C4A1E), Color(hex: 0xD4A373))
        case .yellow: return (Color(hex: 0x9A7A00), Color(hex: 0xFFD84D))
        case .olive: return (Color(hex: 0x5B6B1F), Color(hex: 0xC5D86D))
        case .green: return (Color(hex: 0x2E7D32), Color(hex: 0x7FD98A))
        case .mint: return (Color(hex: 0x0E8F5B), Color(hex: 0x86EFAC))
        case .teal: return (Color(hex: 0x0F766E), Color(hex: 0x5EEAD4))
        case .cyan: return (Brand.cyanDeep, Brand.cyan)
        case .sky: return (Color(hex: 0x0369A1), Color(hex: 0x7DD3FC))
        case .blue: return (Color(hex: 0x1F5FBF), Color(hex: 0x6EA8FF))
        case .navy: return (Brand.navy, Brand.cyanLight)
        case .indigo: return (Color(hex: 0x4338CA), Color(hex: 0xA5B4FC))
        case .purple: return (Color(hex: 0x6B3FB8), Color(hex: 0xB79CFF))
        case .lavender: return (Color(hex: 0x8E4EC6), Color(hex: 0xD8B4FE))
        case .magenta: return (Color(hex: 0xA21CAF), Color(hex: 0xF0ABFC))
        case .pink: return (Color(hex: 0xB8357A), Color(hex: 0xFF8CC6))
        case .gray: return (Color(hex: 0x5F6B7A), Color(hex: 0xA9B4C2))
        case .charcoal: return (Color(hex: 0x1F2937), Color(hex: 0xD1D5DB))
        }
    }

    var displayName: String {
        switch self {
        case .red: return "Vermelho"
        case .wine: return "Vinho"
        case .orange: return "Laranja"
        case .amber: return "Âmbar"
        case .brown: return "Marrom"
        case .yellow: return "Amarelo"
        case .olive: return "Oliva"
        case .green: return "Verde"
        case .mint: return "Menta"
        case .teal: return "Turquesa"
        case .cyan: return "Ciano"
        case .sky: return "Céu"
        case .blue: return "Azul"
        case .navy: return "Marinho"
        case .indigo: return "Índigo"
        case .purple: return "Roxo"
        case .lavender: return "Lilás"
        case .magenta: return "Magenta"
        case .pink: return "Rosa"
        case .gray: return "Cinza"
        case .charcoal: return "Grafite"
        }
    }
}

enum ProjectIcon {
    /// Ícones oferecidos no formulário (decisão 6 da FEAT-006), por tema. Todos existem desde
    /// o SF Symbols 4 (macOS 13) — símbolo ausente cairia no padrão e a célula ficaria vazia.
    static let curated = [
        // Trabalho e estudo
        "folder", "briefcase", "building.2", "doc.text", "pencil", "paperclip", "chart.bar",
        "target", "lightbulb", "megaphone", "book", "graduationcap", "brain", "puzzlepiece",
        // Dinheiro e casa
        "creditcard", "dollarsign.circle", "banknote", "cart", "shippingbox", "tag", "house", "hammer",
        "wrench.and.screwdriver", "paintbrush", "scissors", "tshirt", "gift",
        // Tecnologia
        "laptopcomputer", "terminal", "gear", "cpu", "globe", "lock", "key", "bolt", "sparkles",
        // Pessoas e comunicação
        "person.2", "envelope", "phone", "bell", "calendar", "clock", "bookmark", "flag", "star",
        // Saúde e esporte
        "heart", "stethoscope", "dumbbell", "figure.run", "trophy", "bicycle", "fork.knife", "cup.and.saucer",
        // Lazer e viagem
        "music.note", "headphones", "gamecontroller", "film", "camera", "tv", "theatermasks",
        "airplane", "car", "sailboat", "map", "tent",
        // Natureza
        "leaf", "tree", "pawprint", "sun.max", "moon", "flame", "drop"
    ]
}

extension Project {
    /// Símbolo gravado, ou o padrão se não existir nesta versão do macOS.
    var symbolName: String {
        NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil ? icon : Project.defaultIcon
    }
}

/// Faixa vertical da cor do projeto à esquerda da linha/cartão (decisão 10).
struct ProjectStripe: View {
    let project: Project

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(project.color.color)
            .frame(width: 4)
            .padding(.vertical, 2)
            .accessibilityHidden(true)
    }
}

/// Selo do projeto na lista e no cartão do Kanban — mesmo formato do `UrgentBadge` (cápsula cheia, texto
/// em caixa alta e negrito), na cor do projeto. O texto inverte com o tema: os tons do projeto
/// são escuros no claro (texto branco) e claros no escuro (texto marinho).
struct ProjectBadge: View {
    let project: Project

    var body: some View {
        Label(project.title.uppercased(), systemImage: project.symbolName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.adaptive(light: .white, dark: Brand.navy))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(project.color.color, in: Capsule())
            .help("Projeto: \(project.title)")
            .accessibilityLabel("Projeto \(project.title)")
    }
}

/// Escolha de projeto de uma tarefa (formulário, criação rápida, lote): "Sem projeto" + todos.
struct ProjectPicker: View {
    let projects: [Project]
    @Binding var selection: UUID?
    var compact = false

    private var selected: Project? { selection.flatMap { id in projects.first { $0.id == id } } }

    var body: some View {
        Menu {
            Toggle("Sem projeto", isOn: Binding(get: { selection == nil }, set: { if $0 { selection = nil } }))
            if !projects.isEmpty { Divider() }
            ForEach(projects) { project in
                Toggle(isOn: Binding(get: { selection == project.id }, set: { if $0 { selection = project.id } })) {
                    Label(project.title, systemImage: project.symbolName)
                }
            }
        } label: {
            if let selected {
                Label(selected.title, systemImage: selected.symbolName)
            } else {
                Label(compact ? "Projeto" : "Sem projeto", systemImage: "folder")
            }
        }
        .fixedSize()
        .accessibilityLabel("Projeto: \(selected?.title ?? "nenhum")")
    }
}

/// Filtro por projeto da barra (lista e quadro).
struct ProjectFilterMenu: View {
    let projects: [Project]
    @Binding var filter: ProjectFilter

    private var title: String {
        switch filter {
        case .all: return "Projeto"
        case .none: return "Sem projeto"
        case .project(let id): return projects.first { $0.id == id }?.title ?? "Projeto"
        }
    }

    var body: some View {
        Menu {
            option("Todos", .all)
            option("Sem projeto", .none)
            if !projects.isEmpty { Divider() }
            ForEach(projects) { project in
                Toggle(isOn: binding(.project(project.id))) {
                    Label(project.title, systemImage: project.symbolName)
                }
            }
        } label: {
            Label(title, systemImage: "folder")
        }
        .fixedSize()
    }

    private func option(_ label: String, _ value: ProjectFilter) -> some View {
        Toggle(label, isOn: binding(value))
    }

    private func binding(_ value: ProjectFilter) -> Binding<Bool> {
        Binding(get: { filter == value }, set: { if $0 { filter = value } })
    }
}
