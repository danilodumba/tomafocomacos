import Foundation
import TomafocoInfrastructure

/// Ponto de entrada do helper privilegiado (launchd daemon registrado via `SMAppService`).
///
/// Só publica o Mach service e fica ouvindo; toda a lógica está em `HostsHelperService`.
/// Conexões passam pelo `HelperListenerDelegate`, que exige assinatura de código válida do cliente.
let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HostsHelperInfo.machServiceName)
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
