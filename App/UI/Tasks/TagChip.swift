import SwiftUI

/// Selo "URGENTE" (RF-09.13) — lista e cartões do Kanban.
struct UrgentBadge: View {
    var body: some View {
        Label("URGENTE", systemImage: "flame.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Brand.danger, in: Capsule())
            .accessibilityLabel("Urgente")
    }
}

/// Chip de tag das tarefas (lista e cartões do Kanban).
struct TagChip: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Brand.cyan)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Brand.cyan.opacity(0.14), in: Capsule())
    }
}
