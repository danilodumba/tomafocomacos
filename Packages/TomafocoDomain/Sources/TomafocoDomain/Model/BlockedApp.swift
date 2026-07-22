import Foundation

/// Aplicativo a ser bloqueado durante o foco, identificado por bundle ID (RF-03.1).
public struct BlockedApp: Equatable, Codable, Hashable, Sendable {
    public let bundleID: String
    public let displayName: String
    public var isEnabled: Bool

    public init(bundleID: String, displayName: String, isEnabled: Bool = true) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.isEnabled = isEnabled
    }
}
