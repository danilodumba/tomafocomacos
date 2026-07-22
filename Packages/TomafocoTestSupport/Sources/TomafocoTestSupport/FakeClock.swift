import Foundation
import TomafocoDomain

/// Clock determinístico para testes. `advance(by:)` avança o tempo e dispara os ticks agendados.
public final class FakeClock: SessionClock {
    public private(set) var now: Date
    private var ticks: [FakeSubscription] = []

    public init(now: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.now = now
    }

    public func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void) -> ClockSubscription {
        let sub = FakeSubscription(onCancel: { [weak self] id in
            self?.ticks.removeAll { $0.id == id }
        })
        sub.action = tick
        ticks.append(sub)
        return sub
    }

    /// Avança o relógio e dispara UMA rodada de tick em cada assinatura ativa.
    public func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        ticks.forEach { $0.action?() }
    }

    /// Apenas dispara os ticks sem mover o relógio (útil para acionar transições manualmente).
    public func fireTick() {
        ticks.forEach { $0.action?() }
    }

    public var hasActiveSubscription: Bool { !ticks.isEmpty }
}

public final class FakeSubscription: ClockSubscription {
    let id = UUID()
    var action: (() -> Void)?
    private let onCancel: (UUID) -> Void

    init(onCancel: @escaping (UUID) -> Void) { self.onCancel = onCancel }

    public func cancel() {
        action = nil
        onCancel(id)
    }
}
