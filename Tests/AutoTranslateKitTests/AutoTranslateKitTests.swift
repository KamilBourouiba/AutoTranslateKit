#if canImport(Testing)
import Testing
@testable import AutoTranslateKit

struct AutoTranslateKitTests {
    @Test
    func languageSelectionResolvesToSupportedLocales() {
        #expect(TranslationLanguage.system.resolved != .system)
        #expect(TranslationLanguage.system.resolved.localeLanguage != nil)
        #expect(TranslationLanguage.english.locale.identifier == "en")
        #expect(TranslationLanguage.french.locale.identifier == "fr")
        #expect(TranslationLanguage(identifier: "es-MX") == .spanish)
        #expect(
            TranslationLanguage(identifier: "zh-Hans")
                != TranslationLanguage(identifier: "zh-Hant")
        )
    }

    @Test
    func exclusionPolicyProtectsAnnotatedAndURLContent() {
        let policy = TranslationExclusionPolicy(excludedTerms: ["AutoTranslateKit"])

        #expect(!policy.shouldTranslate(request("Alice", kind: .properName)))
        #expect(!policy.shouldTranslate(request("https://example.com")))
        #expect(!policy.shouldTranslate(request("secret", kind: .userData)))
        #expect(!policy.shouldTranslate(request("AutoTranslateKit")))
        #expect(policy.shouldTranslate(request("Bonjour")))
    }

    @Test
    func cacheDeduplicatesConcurrentRequests() async throws {
        let provider = MockTranslationProvider { request in
            try await Task.sleep(nanoseconds: 20_000_000)
            return TranslationResult(
                originalText: request.text,
                translatedText: "Hello",
                sourceLanguage: request.sourceLanguage,
                targetLanguage: request.targetLanguage
            )
        }
        let cache = TranslationCache(provider: provider)
        let value = request("Bonjour")

        async let first = cache.translate(value)
        async let second = cache.translate(value)
        let results = try await [first, second]
        let callCount = await provider.callCount
        let cachedCount = await cache.count

        #expect(results.map(\.translatedText) == ["Hello", "Hello"])
        #expect(callCount == 1)
        #expect(cachedCount == 1)
    }

    @Test
    func excludedContentNeverCallsProvider() async throws {
        let provider = MockTranslationProvider(translations: ["Alice": "Alicia"])
        let cache = TranslationCache(provider: provider)

        let result = try await cache.translate(request("Alice", kind: .properName))
        let callCount = await provider.callCount

        #expect(result.translatedText == "Alice")
        #expect(!result.wasTranslated)
        #expect(callCount == 0)
    }

    @Test
    @MainActor
    func settingsPersistThroughInjectedStore() {
        let store = InMemoryTranslationSettingsStore()
        let settings = TranslationSettings(store: store, storageKey: "test")
        settings.isEnabled = false
        settings.targetLanguage = .french

        let restored = TranslationSettings(store: store, storageKey: "test")

        #expect(!restored.isEnabled)
        #expect(restored.targetLanguage == .french)
    }

    @Test
    func resolverUsesCatalogForCoreLanguagesAndProviderForOthers() async throws {
        let provider = MockTranslationProvider(translations: ["Bonjour": "مرحبا"])
        let resolver = TranslationResolver(
            provider: provider,
            catalog: StubCatalog()
        )

        let catalogResult = try await resolver.resolve(
            .catalog(key: "greeting", source: "Bonjour"),
            sourceLanguage: .french,
            targetLanguage: .english
        )
        let appleResult = try await resolver.resolve(
            "Bonjour",
            sourceLanguage: .french,
            targetLanguage: TranslationLanguage(identifier: "ar")
        )
        _ = try await resolver.resolve(
            "Bonjour",
            sourceLanguage: .french,
            targetLanguage: TranslationLanguage(identifier: "ar")
        )
        let callCount = await provider.callCount
        let cachedCount = await resolver.count

        #expect(catalogResult.translatedText == "Catalog: greeting")
        #expect(catalogResult.provider == .catalog)
        #expect(catalogResult.sourceLanguage == .french)
        #expect(catalogResult.targetLanguage == .english)
        #expect(catalogResult.wasTranslated)
        #expect(appleResult.translatedText == "مرحبا")
        #expect(appleResult.provider == .custom)
        #expect(callCount == 1)
        #expect(cachedCount == 2)
    }

    @Test
    func runtimeStringUsesProviderForCoreLanguage() async throws {
        let provider = MockTranslationProvider(translations: ["Bonjour": "Hello"])
        let resolver = TranslationResolver(
            provider: provider,
            catalog: StubCatalog()
        )

        let result = try await resolver.resolve(
            "Bonjour",
            sourceLanguage: .french,
            targetLanguage: .english
        )
        let callCount = await provider.callCount

        #expect(result.translatedText == "Hello")
        #expect(result.provider == .custom)
        #expect(callCount == 1)
    }

    @Test
    func localizedResourceExposesImmediateSourceValue() {
        let source: TranslationSource = .localizedResource("Immediate title")
        #expect(source.text(in: .english) == "Immediate title")
    }

    @Test
    func resolverPreservesExclusionsBeforeRouting() async throws {
        let provider = MockTranslationProvider(translations: ["Alice": "أليس"])
        let resolver = TranslationResolver(provider: provider, catalog: StubCatalog())

        let result = try await resolver.resolve(
            "Alice",
            sourceLanguage: .english,
            targetLanguage: TranslationLanguage(identifier: "ar"),
            contentKind: .properName
        )
        let callCount = await provider.callCount

        #expect(result.translatedText == "Alice")
        #expect(result.provider == .none)
        #expect(!result.wasTranslated)
        #expect(callCount == 0)
    }

    @Test
    func languagePresentationIncludesReadableCodesAndFlag() {
        #expect(TranslationLanguage.french.regionCode == "FR")
        #expect(TranslationLanguage.french.flagEmoji == "🇫🇷")
        #expect(TranslationLanguage.french.displayCode == "fr · FR")
        #expect(!TranslationLanguage.french.displayName().isEmpty)
    }

    @Test
    func globalLanguagesAreLimitedToShippedCatalogs() {
        let values = GlobalLanguageSelection.intersect(
            supportedLanguages: [.english, .french, .german],
            bundleLocalizations: ["Base", "fr"],
            developmentLocalization: "en"
        )

        #expect(Set(values) == [.english, .french])
    }

    @Test
    func displayStringMakesTranslationIntentExplicit() {
        let dynamic = DisplayString.dynamic("Server value", source: .english)
        let excluded = dynamic.noTranslation()
        let verbatim = DisplayString.verbatim("AutoTranslateKit")

        #expect(dynamic.sourceLanguage == .english)
        #expect(dynamic.rawValue == "Server value")
        #expect(excluded.rawValue == "Server value")
        #expect(verbatim.rawValue == "AutoTranslateKit")
    }

    @Test
    func brokerBatchesAndDeduplicatesDynamicValues() async {
        let provider = MockTranslationProvider(translations: ["Hello": "Bonjour"])
        let broker = TranslationBroker(provider: provider)

        let results = await broker.translate(
            ["Hello", "Hello"],
            sourceLanguage: .english,
            targetLanguage: .french
        )
        let callCount = await provider.callCount

        #expect(results.map(\.translatedText) == ["Bonjour", "Bonjour"])
        #expect(callCount == 1)
    }

    private func request(
        _ text: String,
        kind: TranslationContentKind = .general
    ) -> TranslationRequest {
        TranslationRequest(
            text: text,
            sourceLanguage: .french,
            targetLanguage: .english,
            contentKind: kind
        )
    }
}

private struct StubCatalog: TranslationCatalogProviding {
    func translation(
        for source: TranslationSource,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage
    ) -> TranslationResult {
        let key: String
        switch source {
        case let .string(catalogKey, _):
            key = catalogKey ?? source.originalText
        case let .localizedResource(resource):
            key = resource.key
        }

        return TranslationResult(
            originalText: source.originalText,
            translatedText: "Catalog: \(key)",
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            provider: .catalog
        )
    }
}
#endif
