import Foundation
import TomafocoDomain

/// `SessionClock` real baseado em `DispatchSourceTimer`, entregando ticks na main queue
/// (o `SessionCoordinator` é `@MainActor`).
public final class DispatchSessionClock: SessionClock {

    public var now: Date { Date() }

    public init() {}

    public func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void) -> ClockSubscription {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler(handler: tick)
        timer.resume()
        return DispatchClockSubscription(timer: timer)
    }
}

private final class DispatchClockSubscription: ClockSubscription {
    private let timer: DispatchSourceTimer
    private var cancelled = false

    init(timer: DispatchSourceTimer) { self.timer = timer }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        timer.cancel()
    }

    deinit { if !cancelled { timer.cancel() } }
}
