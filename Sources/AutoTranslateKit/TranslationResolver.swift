import Foundation

/// Input accepted by translated views and non-view resolvers.
public enum TranslationSource: Sendable {
    /// A runtime string. When `key` is provided it is used for catalog lookup.
    case string(key: String?, source: String)
    /// A resource preserving interpolation arguments, table and bundle information.
    case localizedResource(LocalizedStringResource)

    public static func text(_ source: String) -> Self {
        .string(key: nil, source: source)
    }

    public static func catalog(key: String, source: String) -> Self {
        .string(key: key, source: source)
    }

    public var originalText: String {
        text(in: .system)
    }

    /// Resolves the original value in a specific source language.
    public func text(in language: TranslationLanguage) -> String {
        switch self {
        case let .string(_, source):
            return source
        case .localizedResource(var resource):
            resource.locale = language.locale
            return String(localized: resource)
        }
    }

    fileprivate var identity: String {
        switch self {
        case let .string(key, source):
            "string|\(key ?? "")|\(source)"
        case let .localizedResource(resource):
            "resource|\(resource.key)|\(originalText)"
        }
    }

    fileprivate var prefersCatalog: Bool {
        switch self {
        case let .string(key, _):
            key != nil
        case .localizedResource:
            true
        }
    }
}

/// Resolves interface strings from an app or package string catalog.
public protocol TranslationCatalogProviding: Sendable {
    func translation(
        for source: TranslationSource,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage
    ) -> TranslationResult
}

/// Foundation-backed catalog resolver used by default for the nine core languages.
public struct FoundationTranslationCatalog: TranslationCatalogProviding {
    public init() {}

    public func translation(
        for source: TranslationSource,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage
    ) -> TranslationResult {
        let original = source.text(in: sourceLanguage)
        let translated: String

        switch source {
        case let .string(key, fallback):
            let lookupKey = key ?? fallback
            let localized = String(
                localized: String.LocalizationValue(lookupKey),
                locale: targetLanguage.locale
            )
            translated = localized == lookupKey && key != nil ? fallback : localized

        case .localizedResource(var resource):
            resource.locale = targetLanguage.locale
            translated = String(localized: resource)
        }

        return TranslationResult(
            originalText: original,
            translatedText: translated,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            wasTranslated: translated != original,
            provider: .catalog
        )
    }
}

/// Shared abstraction used by SwiftUI components and imperative string consumers.
public protocol TranslationResolving: Sendable {
    func resolve(
        _ source: TranslationSource,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        contentKind: TranslationContentKind
    ) async throws -> TranslationResult
}

/// Routes core languages to string catalogs and all other languages to the injected provider.
///
/// Results are cached and simultaneous identical requests are deduplicated.
public actor TranslationResolver: TranslationResolving {
    private struct CacheKey: Hashable, Sendable {
        let sourceIdentity: String
        let sourceLanguage: TranslationLanguage
        let targetLanguage: TranslationLanguage
        let contentKind: TranslationContentKind
    }

    private let provider: any TranslationProviding
    private let catalog: any TranslationCatalogProviding
    private let policy: TranslationExclusionPolicy
    private var cached: [CacheKey: TranslationResult] = [:]
    private var inFlight: [CacheKey: Task<TranslationResult, any Error>] = [:]

    public init(
        provider: any TranslationProviding,
        catalog: any TranslationCatalogProviding = FoundationTranslationCatalog(),
        policy: TranslationExclusionPolicy = .init()
    ) {
        self.provider = provider
        self.catalog = catalog
        self.policy = policy
    }

    public func resolve(
        _ source: TranslationSource,
        sourceLanguage: TranslationLanguage = .system,
        targetLanguage: TranslationLanguage,
        contentKind: TranslationContentKind = .general
    ) async throws -> TranslationResult {
        let resolvedTarget = targetLanguage.resolved
        let key = CacheKey(
            sourceIdentity: source.identity,
            sourceLanguage: sourceLanguage,
            targetLanguage: resolvedTarget,
            contentKind: contentKind
        )

        if let result = cached[key] {
            return result
        }
        if let task = inFlight[key] {
            return try await task.value
        }

        let request = TranslationRequest(
            text: source.text(in: sourceLanguage),
            sourceLanguage: sourceLanguage,
            targetLanguage: resolvedTarget,
            contentKind: contentKind
        )
        guard policy.shouldTranslate(request) else {
            return .excluded(request)
        }

        let provider = self.provider
        let catalog = self.catalog
        let prefersCatalog = source.prefersCatalog
        let task = Task<TranslationResult, any Error> {
            if prefersCatalog,
               TranslationLanguage.coreInterfaceLanguages.contains(resolvedTarget) {
                return catalog.translation(
                    for: source,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: resolvedTarget
                )
            }
            return try await provider.translate(request)
        }
        inFlight[key] = task

        do {
            let result = try await task.value
            cached[key] = result
            inFlight[key] = nil
            return result
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    /// Resolves a runtime string without constructing `TranslationSource` explicitly.
    public func resolve(
        _ source: String,
        sourceLanguage: TranslationLanguage = .system,
        targetLanguage: TranslationLanguage,
        contentKind: TranslationContentKind = .general
    ) async throws -> TranslationResult {
        try await resolve(
            .text(source),
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            contentKind: contentKind
        )
    }

    /// Resolves a localized resource for non-View values.
    public func resolve(
        localized resource: LocalizedStringResource,
        sourceLanguage: TranslationLanguage = .system,
        targetLanguage: TranslationLanguage,
        contentKind: TranslationContentKind = .general
    ) async throws -> TranslationResult {
        try await resolve(
            .localizedResource(resource),
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            contentKind: contentKind
        )
    }

    public func removeAll() {
        cached.removeAll()
    }

    public var count: Int {
        cached.count
    }
}
