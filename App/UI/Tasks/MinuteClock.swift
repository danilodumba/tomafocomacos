import Foundation

/// Relógio de minuto das telas de tarefas (FEAT-006, H3): o filtro por vencimento e o destaque
/// de atrasada usam **o mesmo** `now`, que avança na virada de cada minuto enquanto a janela
/// está aberta. Antes cada linha lia `Date()` no render e a lista não re-renderizava com o tempo
/// — a tarefa passava do vencimento e continuava sem destaque (e filtro e destaque podiam
/// discordar no mesmo render).
@MainActor
final class MinuteClock {
    private var timer: Timer?

    /// Dispara `onTick` na virada de cada minuto. Chamar de novo reinicia.
    func start(_ onTick: @escaping @MainActor (Date) -> Void) {
        stop()
        let now = Date()
        let nextMinute = Calendar.current.dateInterval(of: .minute, for: now)?.end ?? now.addingTimeInterval(60)
        let timer = Timer(fire: nextMinute, interval: 60, repeats: true) { _ in
            Task { @MainActor in onTick(Date()) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Dono solto sem `stop()`: o run loop retém o `Timer` repetitivo para sempre.
    deinit {
        timer?.invalidate()
    }
}

/// Tela que mostra tarefas com vencimento (lista, Kanban): publica `now` e liga/desliga o
/// relógio junto com a janela. A fiação mora aqui para as duas telas não divergirem (uma
/// esquecer o `stop()` vazaria o timer; esquecer o `resetNow()` no `refresh()` deixaria o
/// recorte com o `now` do minuto anterior logo após uma mudança).
@MainActor
protocol MinuteClockHosting: AnyObject {
    var now: Date { get set }
    var clock: MinuteClock { get }
}

extension MinuteClockHosting {
    /// `didAppear`: começa a avançar `now` por minuto.
    func startMinuteClock() {
        clock.start { [weak self] in self?.now = $0 }
    }

    /// `didDisappear`: janela fechada não precisa de tick.
    func stopMinuteClock() {
        clock.stop()
    }

    /// `refresh()`: toda releitura parte do agora real, não do último tick.
    func resetNow() {
        now = Date()
    }

    /// Relógio para quem a tela abre (formulário de edição): lê o `now` da tela enquanto ela viver.
    var nowProvider: () -> Date {
        { [weak self] in self?.now ?? Date() }
    }
}
