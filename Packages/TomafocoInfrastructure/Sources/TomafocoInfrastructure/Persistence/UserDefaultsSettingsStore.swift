import Foundation
import TomafocoDomain

/// `SettingsRepository` sobre `UserDefaults` + `Codable` (RF-05). Se o histórico crescer, migrar
/// para SwiftData (T-28) sem afetar os consumidores (DIP).
public final class UserDefaultsSettingsStore: SettingsRepository {

    private enum Key {
        static let configuration = "tomafoco.configuration"
        static let blockList = "tomafoco.blockList"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadConfiguration() -> PomodoroConfiguration {
        decode(Key.configuration) ?? PomodoroConfiguration()
    }

    public func save(_ configuration: PomodoroConfiguration) {
        encode(configuration, forKey: Key.configuration)
    }

    public func loadBlockList() -> BlockList {
        decode(Key.blockList) ?? BlockList()
    }

    public func save(_ blockList: BlockList) {
        encode(blockList, forKey: Key.blockList)
    }

    // MARK: - helpers

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
