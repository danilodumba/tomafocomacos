import Foundation
import TomafocoDomain

/// Decide quando a tela cheia de intervalo deve aparecer (RF-01.3).
///
/// Pura e derivada só do estado da sessão: a View não inventa regra própria, e a decisão fica
/// testável sem AppKit. Devolve uma **chave** em vez de um `Bool` para que a apresentação saiba
/// distinguir um intervalo de outro — sem isso, dispensar a tela de um intervalo dispensaria
/// também a do intervalo seguinte.
public enum BreakOverlayPolicy {

    /// Chave estável do intervalo a exibir, ou `nil` quando não há intervalo em cena.
    public static func presentationKey(for state: SessionMachineState) -> String? {
        switch state {
        case .running(let session), .paused(let session, _):
            guard !session.phase.appliesBlocking, session.phase != .idle else { return nil }
            return "running-\(session.id.uuidString)"

        case .awaitingNext(let phase, let cycle, _):
            // Foco terminou e o intervalo aguarda confirmação: é justamente a hora de chamar
            // a atenção — o usuário pode estar em outro app sem perceber que a etapa acabou.
            guard !phase.appliesBlocking else { return nil }
            return "awaiting-\(phase.rawValue)-\(cycle)"

        case .idle:
            return nil
        }
    }
}
