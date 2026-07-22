import Foundation

/// Agregado com as listas de bloqueio de sites e apps (RF-02.1, RF-03.1).
public struct BlockList: Equatable, Codable, Sendable {
    public var domains: [BlockedDomain]
    public var apps: [BlockedApp]

    public init(domains: [BlockedDomain] = [], apps: [BlockedApp] = []) {
        self.domains = domains
        self.apps = apps
    }

    /// Domínios que devem ser bloqueados na sessão atual.
    public var activeDomains: [BlockedDomain] { domains }

    /// Bundle IDs dos apps habilitados — o que o `AppBlocking` precisa (ISP).
    public var activeAppBundleIDs: Set<String> {
        Set(apps.filter(\.isEnabled).map(\.bundleID))
    }
}
