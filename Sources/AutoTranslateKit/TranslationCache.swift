public actor TranslationCache: TranslationProviding {
    private let provider: any TranslationProviding
    private let policy: TranslationExclusionPolicy
    private var cached: [TranslationRequest: TranslationResult] = [:]
    private var inFlight: [TranslationRequest: Task<TranslationResult, Error>] = [:]

    public init(
        provider: any TranslationProviding,
        policy: TranslationExclusionPolicy = .init()
    ) {
        self.provider = provider
        self.policy = policy
    }

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard policy.shouldTranslate(request) else {
            return .excluded(request)
        }

        if let result = cached[request] {
            return result
        }

        if let task = inFlight[request] {
            return try await task.value
        }

        let task = Task { try await provider.translate(request) }
        inFlight[request] = task

        do {
            let result = try await task.value
            cached[request] = result
            inFlight[request] = nil
            return result
        } catch {
            inFlight[request] = nil
            throw error
        }
    }

    public func removeAll() {
        cached.removeAll()
    }

    public var count: Int {
        cached.count
    }
}
