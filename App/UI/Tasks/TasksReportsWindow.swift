import SwiftUI

/// Janela "Tarefas & Relatórios" (RF-09/RF-10) — separada do timer para manter a
/// janela principal minimalista.
struct TasksReportsWindow: View {
    @ObservedObject var tasksViewModel: TasksViewModel
    @ObservedObject var reportsViewModel: ReportsViewModel

    var body: some View {
        TabView {
            TasksView(viewModel: tasksViewModel)
                .tabItem { Label("Tarefas", systemImage: "checklist") }

            ReportsView(viewModel: reportsViewModel)
                .tabItem { Label("Relatórios", systemImage: "chart.bar") }
        }
        .frame(minWidth: 520, minHeight: 540)
        .background(Brand.background.ignoresSafeArea())
    }
}
