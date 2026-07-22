public actor MockTranslationProvider: TranslationProviding {
    public typealias Handler = @Sendable (TranslationRequest) async throws -> TranslationResult

    private let handler: Handler
    private var requests: [TranslationRequest] = []

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public init(translations: [String: String]) {
        self.handler = { request in
            let translated = translations[request.text] ?? request.text
            return TranslationResult(
                originalText: request.text,
                translatedText: translated,
                sourceLanguage: request.sourceLanguage,
                targetLanguage: request.targetLanguage,
                wasTranslated: translated != request.text,
                provider: .custom
            )
        }
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        requests.append(request)
        return try await handler(request)
    }

    public var receivedRequests: [TranslationRequest] {
        requests
    }

    public var callCount: Int {
        requests.count
    }
}
