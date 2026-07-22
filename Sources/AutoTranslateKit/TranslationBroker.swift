import Foundation

/// Coordinates dynamic translation, including fallback, caching and request
/// deduplication. Static interface copy does not pass through this type.
public protocol TranslationBrokering: Sendable {
    func translate(
        _ text: String,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        contentKind: TranslationContentKind
    ) async -> TranslationResult

    func translate(
        _ values: [String],
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        contentKind: TranslationContentKind
    ) async -> [TranslationResult]
}

public actor TranslationBroker: TranslationBrokering {
    private let resolver: TranslationResolver

    public init(
        provider: any TranslationProviding,
        policy: TranslationExclusionPolicy = .init()
    ) {
        resolver = TranslationResolver(provider: provider, policy: policy)
    }

    public func translate(
        _ text: String,
        sourceLanguage: TranslationLanguage = .system,
        targetLanguage: TranslationLanguage,
        contentKind: TranslationContentKind = .general
    ) async -> TranslationResult {
        do {
            return try await resolver.resolve(
                text,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                contentKind: contentKind
            )
        } catch {
            return fallback(
                text,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            )
        }
    }

    public func translate(
        _ values: [String],
        sourceLanguage: TranslationLanguage = .system,
        targetLanguage: TranslationLanguage,
        contentKind: TranslationContentKind = .general
    ) async -> [TranslationResult] {
        await withTaskGroup(of: (Int, TranslationResult).self) { group in
            for (index, value) in values.enumerated() {
                group.addTask {
                    let result = await self.translate(
                        value,
                        sourceLanguage: sourceLanguage,
                        targetLanguage: targetLanguage,
                        contentKind: contentKind
                    )
                    return (index, result)
                }
            }

            var results = Array<TranslationResult?>(repeating: nil, count: values.count)
            for await (index, result) in group {
                results[index] = result
            }
            return results.enumerated().map { index, result in
                result ?? fallback(
                    values[index],
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                )
            }
        }
    }

    public func removeAllCachedTranslations() async {
        await resolver.removeAll()
    }
}

private func fallback(
    _ text: String,
    sourceLanguage: TranslationLanguage,
    targetLanguage: TranslationLanguage
) -> TranslationResult {
    TranslationResult(
        originalText: text,
        translatedText: text,
        sourceLanguage: sourceLanguage.resolved,
        targetLanguage: targetLanguage.resolved,
        wasTranslated: false,
        provider: .none
    )
}
