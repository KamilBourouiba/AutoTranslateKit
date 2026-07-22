import Foundation

/// A normalized language identifier used throughout AutoTranslateKit.
public struct TranslationLanguage: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        if rawValue == "system" {
            self.rawValue = rawValue
        } else {
            self.rawValue = Locale.Language(identifier: rawValue).languageCode?.identifier
                ?? rawValue
        }
    }

    public init(identifier: String) {
        self.init(rawValue: identifier)
    }

    public static let system = Self(rawValue: "system")
    public static let english = Self(rawValue: "en")
    public static let french = Self(rawValue: "fr")
    public static let spanish = Self(rawValue: "es")
    public static let german = Self(rawValue: "de")
    public static let italian = Self(rawValue: "it")
    public static let portuguese = Self(rawValue: "pt")
    public static let dutch = Self(rawValue: "nl")
    public static let japanese = Self(rawValue: "ja")
    public static let korean = Self(rawValue: "ko")
    public static let coreInterfaceLanguages: [Self] = [
        .english, .french, .spanish, .german, .italian,
        .portuguese, .dutch, .japanese, .korean
    ]

    public var localeLanguage: Locale.Language? {
        self == .system ? nil : Locale.Language(identifier: rawValue)
    }

    /// Resolves `.system` to the device's preferred language.
    public var resolved: TranslationLanguage {
        guard self == .system else { return self }
        let identifier = Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier
        return Self(identifier: identifier)
    }

    public var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    /// Localized, human-readable language name.
    public func displayName(in displayLocale: Locale = .autoupdatingCurrent) -> String {
        let language = resolved
        return displayLocale.localizedString(forLanguageCode: language.rawValue)
            ?? language.rawValue.uppercased()
    }

    /// Representative region inferred by Foundation (for example `FR` for French).
    public var regionCode: String? {
        let identifier = resolved.localeLanguage?.maximalIdentifier
        guard let identifier else { return nil }
        return Locale(identifier: identifier).region?.identifier
    }

    /// Emoji flag for the representative region, when one can be inferred.
    public var flagEmoji: String {
        guard let regionCode, regionCode.count == 2 else { return "🌐" }
        let scalars = regionCode.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127_397 + $0.value)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Readable language and representative region code.
    public var displayCode: String {
        guard let regionCode else { return resolved.rawValue }
        return "\(resolved.rawValue) · \(regionCode)"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
