import Foundation

/// A string whose display and translation policy are explicit.
///
/// Use ``localized(_:)`` for static interface copy in a String Catalog,
/// ``dynamic(_:source:)`` for runtime copy, and ``verbatim(_:)`` for content
/// that must never be translated.
public struct DisplayString: @unchecked Sendable {
    enum Storage {
        case localized(LocalizedStringResource)
        case dynamic(String, TranslationLanguage)
        case verbatim(String)
    }

    let storage: Storage
    let translationAllowed: Bool

    private init(storage: Storage, translationAllowed: Bool = true) {
        self.storage = storage
        self.translationAllowed = translationAllowed
    }

    public static func localized(_ resource: LocalizedStringResource) -> Self {
        Self(storage: .localized(resource))
    }

    public static func dynamic(
        _ value: String,
        source: TranslationLanguage = .system
    ) -> Self {
        Self(storage: .dynamic(value, source))
    }

    public static func verbatim(_ value: String) -> Self {
        Self(storage: .verbatim(value), translationAllowed: false)
    }

    /// Returns the same value explicitly excluded from dynamic translation.
    public func noTranslation() -> Self {
        Self(storage: storage, translationAllowed: false)
    }

    public var sourceLanguage: TranslationLanguage? {
        guard case let .dynamic(_, language) = storage else { return nil }
        return language
    }

    public var rawValue: String {
        switch storage {
        case .localized(var resource):
            resource.locale = .autoupdatingCurrent
            return String(localized: resource)
        case let .dynamic(value, _), let .verbatim(value):
            return value
        }
    }

    func sourceText(hostSourceLanguage: TranslationLanguage) -> String {
        switch storage {
        case .localized(var resource):
            resource.locale = hostSourceLanguage.locale
            return String(localized: resource)
        case let .dynamic(value, _), let .verbatim(value):
            return value
        }
    }
}
