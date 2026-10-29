import Foundation
import TomafocoDomain

/// Critério de ordenação das tarefas — o mesmo na lista e dentro de cada raia do Kanban
/// (FEAT-005). Cada janela guarda a sua escolha.
enum TaskSortOrder: String, CaseIterable, Identifiable {
    case createdAt, dueDate, dueTime, priority

    var id: String { rawValue }

    var label: String {
        switch self {
        case .createdAt: return "Criação"
        case .dueDate: return "Data"
        case .dueTime: return "Hora"
        case .priority: return "Prioridade"
        }
    }

    /// Ordenação salva em `defaults`; `rawValue` desconhecido (versão antiga/futura) volta ao padrão.
    static func stored(in defaults: UserDefaults, key: String) -> TaskSortOrder {
        defaults.string(forKey: key).flatMap(TaskSortOrder.init(rawValue:)) ?? .createdAt
    }

    /// Comparador conforme o critério. **Urgente vai para o topo** em qualquer critério
    /// (RF-09.13); entre iguais vale o critério, e empates caem para o mais recente primeiro.
    func areInIncreasingOrder(_ a: FocusTask, _ b: FocusTask) -> Bool {
        if a.isUrgent != b.isUrgent { return a.isUrgent }
        switch self {
        case .createdAt:
            return a.createdAt > b.createdAt
        case .dueDate:
            return Self.byOptionalDate(a.dueDate, b.dueDate, a, b)
        case .dueTime:
            return Self.byOptionalDate(Self.timeOfDay(a.dueDate), Self.timeOfDay(b.dueDate), a, b)
        case .priority:
            // Prioridade menor = mais urgente; sem prioridade vai para o fim.
            let pa = a.priority ?? Int.max
            let pb = b.priority ?? Int.max
            if pa != pb { return pa < pb }
            return a.createdAt > b.createdAt
        }
    }

    /// Ordena por data opcional (nil por último); empate → mais recente primeiro.
    private static func byOptionalDate(_ da: Date?, _ db: Date?, _ a: FocusTask, _ b: FocusTask) -> Bool {
        switch (da, db) {
        case let (x?, y?): return x != y ? x < y : a.createdAt > b.createdAt
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return a.createdAt > b.createdAt
        }
    }

    /// Segundos desde a meia-noite de uma data — base para ordenar por "hora" do vencimento.
    private static func timeOfDay(_ date: Date?) -> Date? {
        guard let date else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let seconds = (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
        return Date(timeIntervalSinceReferenceDate: TimeInterval(seconds))
    }
}

extension TaskDueFilter {
    var displayName: String {
        switch self {
        case .all: return "Todas as datas"
        case .today: return "Hoje"
        case .next7Days: return "Próximos 7 dias"
        case .overdue: return "Atrasadas"
        }
    }
}

extension FocusTask {
    /// Vencida: tem data de vencimento no passado e não está concluída (item 6). `now` vem do
    /// relógio da tela (`MinuteClock`) — o mesmo que o filtro por vencimento usa.
    func isOverdue(now: Date) -> Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < now
    }

    /// Destaque de urgente só enquanto aberta — concluída não grita mais (RF-09.13).
    var showsUrgent: Bool { isUrgent && !isCompleted }

    /// Link gravado, pronto para abrir (`nil` se ausente ou ilegível).
    var linkURL: URL? { sourceURL.flatMap(URL.init(string:)) }
}
