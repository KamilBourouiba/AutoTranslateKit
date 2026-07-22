import Foundation

/// Identifies the engine that produced a translation.
public enum TranslationProviderKind: String, Codable, Hashable, Sendable {
    case appleTranslation
    case catalog
    case custom
    case none

    /// A user-facing provider name suitable for diagnostics and translation labels.
    public var displayName: String {
        switch self {
        case .appleTranslation: "Apple Translation"
        case .catalog: "String Catalog"
        case .custom: "Custom Provider"
        case .none: "Not Applicable"
        }
    }
}

public enum TranslationContentKind: String, Codable, Hashable, Sendable {
    case general
    case properName
    case url
    case userData
}

public struct TranslationRequest: Hashable, Codable, Sendable {
    public let text: String
    public let sourceLanguage: TranslationLanguage
    public let targetLanguage: TranslationLanguage
    public let contentKind: TranslationContentKind

    public init(
        text: String,
        sourceLanguage: TranslationLanguage = .system,
        targetLanguage: TranslationLanguage,
        contentKind: TranslationContentKind = .general
    ) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.contentKind = contentKind
    }
}

public struct TranslationResult: Equatable, Codable, Sendable {
    public let originalText: String
    public let translatedText: String
    public let sourceLanguage: TranslationLanguage
    public let targetLanguage: TranslationLanguage
    public let wasTranslated: Bool
    public let provider: TranslationProviderKind

    public init(
        originalText: String,
        translatedText: String,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        wasTranslated: Bool = true,
        provider: TranslationProviderKind = .appleTranslation
    ) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.wasTranslated = wasTranslated
        self.provider = provider
    }

    public static func excluded(_ request: TranslationRequest) -> Self {
        Self(
            originalText: request.text,
            translatedText: request.text,
            sourceLanguage: request.sourceLanguage,
            targetLanguage: request.targetLanguage,
            wasTranslated: false,
            provider: .none
        )
    }

    private enum CodingKeys: String, CodingKey {
        case originalText
        case translatedText
        case sourceLanguage
        case targetLanguage
        case wasTranslated
        case provider
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originalText = try container.decode(String.self, forKey: .originalText)
        translatedText = try container.decode(String.self, forKey: .translatedText)
        sourceLanguage = try container.decode(TranslationLanguage.self, forKey: .sourceLanguage)
        targetLanguage = try container.decode(TranslationLanguage.self, forKey: .targetLanguage)
        wasTranslated = try container.decode(Bool.self, forKey: .wasTranslated)
        provider = try container.decodeIfPresent(
            TranslationProviderKind.self,
            forKey: .provider
        ) ?? .appleTranslation
    }
}

public protocol TranslationProviding: Sendable {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

public enum TranslationProviderError: Error, Equatable, Sendable {
    case unavailable
    case noActiveAppleTranslationSession
}
