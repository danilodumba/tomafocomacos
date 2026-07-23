#if canImport(ServiceManagement)
import Foundation
import ServiceManagement
import TomafocoDomain

/// `LoginItemManaging` sobre `SMAppService.mainApp` (macOS 13+): registra o próprio app
/// como item de login, sem helper embarcado. O usuário pode desfazer em
/// Ajustes do Sistema › Geral › Itens de Início — por isso o estado é sempre relido de lá.
public final class SMAppServiceLoginItem: LoginItemManaging {

    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
#endif
