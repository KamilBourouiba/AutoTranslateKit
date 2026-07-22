import Foundation

public struct TranslationExclusionPolicy: Sendable {
    public var excludedKinds: Set<TranslationContentKind>
    public var excludedTerms: Set<String>
    public var excludesDetectedURLs: Bool

    public init(
        excludedKinds: Set<TranslationContentKind> = [.properName, .url, .userData],
        excludedTerms: Set<String> = [],
        excludesDetectedURLs: Bool = true
    ) {
        self.excludedKinds = excludedKinds
        self.excludedTerms = excludedTerms
        self.excludesDetectedURLs = excludesDetectedURLs
    }

    public func shouldTranslate(_ request: TranslationRequest) -> Bool {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              request.sourceLanguage == .system ||
                request.targetLanguage == .system ||
                request.sourceLanguage != request.targetLanguage,
              !excludedKinds.contains(request.contentKind),
              !excludedTerms.contains(text) else {
            return false
        }

        if excludesDetectedURLs,
           let url = URL(string: text),
           url.scheme != nil,
           url.host != nil {
            return false
        }

        return true
    }
}
