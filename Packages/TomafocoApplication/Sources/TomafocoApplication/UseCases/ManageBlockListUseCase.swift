import Foundation
import TomafocoDomain

/// Resultado da inclusão em lote de apps (T-20).
public struct AddAppsResult: Equatable {
    public let list: BlockList
    public let addedNames: [String]
    public let duplicateNames: [String]

    public init(list: BlockList, addedNames: [String], duplicateNames: [String]) {
        self.list = list
        self.addedNames = addedNames
        self.duplicateNames = duplicateNames
    }
}

/// CRUD das listas de bloqueio com validação/normalização (UC-05, RF-05.2).
public final class ManageBlockListUseCase {
    private let settings: SettingsRepository

    public init(settings: SettingsRepository) {
        self.settings = settings
    }

    public func currentList() -> BlockList { settings.loadBlockList() }

    /// Adiciona um domínio validado. Lança `invalidDomain` ou `duplicateEntry`.
    @discardableResult
    public func addDomain(raw: String) throws -> BlockList {
        let domain = try BlockedDomain(raw: raw)
        var list = settings.loadBlockList()
        guard !list.domains.contains(domain) else { throw DomainError.duplicateEntry(domain.value) }
        list.domains.append(domain)
        settings.save(list)
        return list
    }

    @discardableResult
    public func removeDomain(_ domain: BlockedDomain) -> BlockList {
        var list = settings.loadBlockList()
        list.domains.removeAll { $0 == domain }
        settings.save(list)
        return list
    }

    /// Adiciona um app. Lança `duplicateEntry` se o bundle ID já existir.
    @discardableResult
    public func addApp(_ app: BlockedApp) throws -> BlockList {
        var list = settings.loadBlockList()
        guard !list.apps.contains(where: { $0.bundleID == app.bundleID }) else {
            throw DomainError.duplicateEntry(app.bundleID)
        }
        list.apps.append(app)
        settings.save(list)
        return list
    }

    /// Adiciona vários apps de uma vez (seleção múltipla do `NSOpenPanel`, T-20).
    /// Diferente de `addApp`, não lança: os já presentes voltam em `duplicateNames` para aviso na UI.
    /// Duplicatas dentro do próprio lote também são descartadas.
    @discardableResult
    public func addApps(_ apps: [BlockedApp]) -> AddAppsResult {
        var list = settings.loadBlockList()
        var known = Set(list.apps.map(\.bundleID))
        var duplicateNames: [String] = []
        var addedNames: [String] = []

        for app in apps {
            guard known.insert(app.bundleID).inserted else {
                duplicateNames.append(app.displayName)
                continue
            }
            list.apps.append(app)
            addedNames.append(app.displayName)
        }

        if !addedNames.isEmpty { settings.save(list) }
        return AddAppsResult(list: list, addedNames: addedNames, duplicateNames: duplicateNames)
    }

    @discardableResult
    public func removeApp(bundleID: String) -> BlockList {
        var list = settings.loadBlockList()
        list.apps.removeAll { $0.bundleID == bundleID }
        settings.save(list)
        return list
    }

    @discardableResult
    public func setApp(bundleID: String, enabled: Bool) -> BlockList {
        var list = settings.loadBlockList()
        if let idx = list.apps.firstIndex(where: { $0.bundleID == bundleID }) {
            list.apps[idx].isEnabled = enabled
        }
        settings.save(list)
        return list
    }
}
