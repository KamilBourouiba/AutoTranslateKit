#if canImport(Translation)
import Foundation
import Translation

@available(iOS 18.0, macOS 15.0, *)
public extension TranslationLanguage {
    /// All languages currently reported as supported by Apple Translation.
    static func appleSupportedLanguages() async -> [TranslationLanguage] {
        let languages = await LanguageAvailability().supportedLanguages
        return Set(languages.map { TranslationLanguage(identifier: $0.minimalIdentifier) })
            .sorted {
                $0.displayName().localizedStandardCompare($1.displayName()) == .orderedAscending
            }
    }

    /// Languages suitable for a global UI selector: Apple Translation support
    /// intersected with localizations shipped by the app bundle.
    static func globallySelectableLanguages(
        in bundle: Bundle = .main
    ) async -> [TranslationLanguage] {
        GlobalLanguageSelection.intersect(
            supportedLanguages: await appleSupportedLanguages(),
            bundleLocalizations: bundle.localizations,
            developmentLocalization: bundle.developmentLocalization
        )
    }
}

@available(iOS 18.0, macOS 15.0, *)
public actor AppleTranslationProvider: TranslationProviding {
    private struct Work: Sendable {
        let request: TranslationRequest
        let continuation: CheckedContinuation<TranslationResult, any Error>
    }

    private let stream: AsyncStream<Work>
    private let continuation: AsyncStream<Work>.Continuation

    public init() {
        var captured: AsyncStream<Work>.Continuation?
        self.stream = AsyncStream { captured = $0 }
        self.continuation = captured!
    }

    public func run(session: TranslationSession) async {
        for await work in stream {
            do {
                let response = try await session.translate(work.request.text)
                work.continuation.resume(
                    returning: TranslationResult(
                        originalText: work.request.text,
                        translatedText: response.targetText,
                        sourceLanguage: work.request.sourceLanguage,
                        targetLanguage: work.request.targetLanguage,
                        provider: .appleTranslation
                    )
                )
            } catch {
                work.continuation.resume(throwing: error)
            }
        }
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try await withCheckedThrowingContinuation { resultContinuation in
            continuation.yield(
                Work(request: request, continuation: resultContinuation)
            )
        }
    }
}
#endif
