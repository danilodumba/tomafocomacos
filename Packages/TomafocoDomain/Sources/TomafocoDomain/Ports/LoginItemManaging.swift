import Foundation

/// Registro do app como item de login do macOS (RF-05.3 — "iniciar junto com o sistema").
/// Port para a UI não depender de ServiceManagement e ser testável com fake.
public protocol LoginItemManaging: AnyObject {
    /// Estado atual no sistema — pode mudar por fora (Ajustes do Sistema › Itens de Início).
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}
