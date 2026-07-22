import Foundation
import Observation

public protocol TranslationSettingsStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public struct UserDefaultsTranslationSettingsStore: TranslationSettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

public final class InMemoryTranslationSettingsStore: TranslationSettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) -> Data? {
        lock.withLock { values[key] }
    }

    public func set(_ data: Data?, forKey key: String) {
        lock.withLock { values[key] = data }
    }
}

@MainActor
@Observable
public final class TranslationSettings {
    public nonisolated static let defaultStorageKey = "AutoTranslateKit.settings"

    public var isEnabled: Bool {
        didSet { persist() }
    }

    public var targetLanguage: TranslationLanguage {
        didSet { persist() }
    }

    private let store: any TranslationSettingsStore
    private let storageKey: String

    public init(
        isEnabled: Bool = true,
        targetLanguage: TranslationLanguage = .system,
        store: any TranslationSettingsStore = UserDefaultsTranslationSettingsStore(),
        storageKey: String = defaultStorageKey
    ) {
        self.store = store
        self.storageKey = storageKey

        if let data = store.data(forKey: storageKey),
           let persisted = try? JSONDecoder().decode(Persisted.self, from: data) {
            self.isEnabled = persisted.isEnabled
            self.targetLanguage = persisted.targetLanguage
        } else {
            self.isEnabled = isEnabled
            self.targetLanguage = targetLanguage
        }
    }

    private func persist() {
        let value = Persisted(isEnabled: isEnabled, targetLanguage: targetLanguage)
        store.set(try? JSONEncoder().encode(value), forKey: storageKey)
    }
}

private struct Persisted: Codable {
    let isEnabled: Bool
    let targetLanguage: TranslationLanguage
}
