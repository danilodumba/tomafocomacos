import Foundation

/// Fonte de tempo do domínio. NUNCA use `Date()` ou `Timer` diretamente no Domain/Application —
/// tudo passa por aqui para permitir testes determinísticos (RNF-05).
public protocol SessionClock: AnyObject {
    /// Instante atual.
    var now: Date { get }
    /// Agenda um tick periódico. Retorna uma assinatura cancelável.
    func schedule(every interval: TimeInterval, _ tick: @escaping () -> Void) -> ClockSubscription
}

/// Assinatura de um agendamento de clock.
public protocol ClockSubscription {
    func cancel()
}
