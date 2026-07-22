#if canImport(SwiftUI)
import SwiftUI

private actor UnavailableBroker: TranslationBrokering {
    func translate(
        _ text: String,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        contentKind: TranslationContentKind
    ) async -> TranslationResult {
        TranslationResult(
            originalText: text,
            translatedText: text,
            sourceLanguage: sourceLanguage.resolved,
            targetLanguage: targetLanguage.resolved,
            wasTranslated: false,
            provider: .none
        )
    }

    func translate(
        _ values: [String],
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        contentKind: TranslationContentKind
    ) async -> [TranslationResult] {
        await values.asyncMap {
            await translate(
                $0,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                contentKind: contentKind
            )
        }
    }
}

private struct TranslationBrokerKey: EnvironmentKey {
    static let defaultValue: any TranslationBrokering = UnavailableBroker()
}

private struct TranslationSourceLanguageKey: EnvironmentKey {
    static let defaultValue = TranslationLanguage.system
}

private struct TranslationTargetLanguageKey: EnvironmentKey {
    static let defaultValue = TranslationLanguage.system
}

private struct TranslationEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    var autoTranslationBroker: any TranslationBrokering {
        get { self[TranslationBrokerKey.self] }
        set { self[TranslationBrokerKey.self] = newValue }
    }

    var autoTranslationSourceLanguage: TranslationLanguage {
        get { self[TranslationSourceLanguageKey.self] }
        set { self[TranslationSourceLanguageKey.self] = newValue }
    }

    var autoTranslationTargetLanguage: TranslationLanguage {
        get { self[TranslationTargetLanguageKey.self] }
        set { self[TranslationTargetLanguageKey.self] = newValue }
    }

    var autoTranslationEnabled: Bool {
        get { self[TranslationEnabledKey.self] }
        set { self[TranslationEnabledKey.self] = newValue }
    }
}

private struct TranslationTaskID: Hashable {
    let text: String
    let source: TranslationLanguage
    let target: TranslationLanguage
    let enabled: Bool
    let kind: TranslationContentKind
}

private struct TranslationBadgeInfo: Equatable {
    let provider: TranslationProviderKind
    let source: TranslationLanguage
    let target: TranslationLanguage
    let original: String?
}

private struct TranslationBadgePreferenceKey: PreferenceKey {
    static let defaultValue: [TranslationBadgeInfo] = []

    static func reduce(
        value: inout [TranslationBadgeInfo],
        nextValue: () -> [TranslationBadgeInfo]
    ) {
        value.append(contentsOf: nextValue())
    }
}

/// Displays a ``DisplayString``. Dynamic values use the host broker; localized
/// values continue through SwiftUI and the active String Catalog.
public struct TranslatedText: View {
    private let value: DisplayString
    private let contentKind: TranslationContentKind

    @Environment(\.autoTranslationBroker) private var broker
    @Environment(\.autoTranslationSourceLanguage) private var hostSource
    @Environment(\.autoTranslationTargetLanguage) private var target
    @Environment(\.autoTranslationEnabled) private var isEnabled
    @State private var result: TranslationResult?

    public init(
        _ value: DisplayString,
        contentKind: TranslationContentKind = .general
    ) {
        self.value = value
        self.contentKind = contentKind
    }

    public init(
        _ dynamicValue: String,
        sourceLanguage: TranslationLanguage = .system,
        contentKind: TranslationContentKind = .general
    ) {
        self.init(
            .dynamic(dynamicValue, source: sourceLanguage),
            contentKind: contentKind
        )
    }

    public init(localized resource: LocalizedStringResource) {
        self.init(.localized(resource))
    }

    public var body: some View {
        switch value.storage {
        case let .localized(resource):
            Text(resource)
                .preference(
                    key: TranslationBadgePreferenceKey.self,
                    value: catalogBadge
                )
        case let .dynamic(text, declaredSource):
            dynamicText(text, declaredSource: declaredSource)
        case let .verbatim(text):
            Text(verbatim: text)
        }
    }

    private func dynamicText(
        _ text: String,
        declaredSource: TranslationLanguage
    ) -> some View {
        let effectiveSource = declaredSource == .system ? hostSource : declaredSource
        return Text(verbatim: result?.translatedText ?? text)
            .preference(
                key: TranslationBadgePreferenceKey.self,
                value: dynamicBadge
            )
            .task(id: TranslationTaskID(
                text: text,
                source: effectiveSource,
                target: target,
                enabled: isEnabled && value.translationAllowed,
                kind: contentKind
            )) {
                result = nil
                guard isEnabled,
                      value.translationAllowed,
                      effectiveSource.resolved != target.resolved else {
                    return
                }
                result = await broker.translate(
                    text,
                    sourceLanguage: effectiveSource,
                    targetLanguage: target,
                    contentKind: contentKind
                )
            }
    }

    private var catalogBadge: [TranslationBadgeInfo] {
        guard isEnabled,
              value.translationAllowed,
              hostSource.resolved != target.resolved else {
            return []
        }
        return [TranslationBadgeInfo(
            provider: .catalog,
            source: hostSource.resolved,
            target: target.resolved,
            original: nil
        )]
    }

    private var dynamicBadge: [TranslationBadgeInfo] {
        guard let result, result.wasTranslated else { return [] }
        return [TranslationBadgeInfo(
            provider: result.provider,
            source: result.sourceLanguage,
            target: result.targetLanguage,
            original: result.originalText
        )]
    }
}

@available(*, deprecated, renamed: "TranslatedText")
public typealias AutoTranslatedText = TranslatedText

private struct TranslationLabelModifier: ViewModifier {
    @Environment(\.autoTranslationSourceLanguage) private var source
    @Environment(\.autoTranslationTargetLanguage) private var target
    @Environment(\.autoTranslationEnabled) private var isEnabled
    let enabled: Bool

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(TranslationBadgePreferenceKey.self) { values in
            if enabled, let info = preferredInfo(values) {
                TranslationBadge(info: info)
                    .alignmentGuide(.top) { $0[.top] + 8 }
                    .alignmentGuide(.trailing) { $0[.trailing] - 8 }
            }
        }
    }

    private func preferredInfo(_ values: [TranslationBadgeInfo]) -> TranslationBadgeInfo? {
        if let dynamic = values.last(where: { $0.provider != .catalog }) {
            return dynamic
        }
        if let catalog = values.last {
            return catalog
        }
        guard isEnabled, source.resolved != target.resolved else { return nil }
        return TranslationBadgeInfo(
            provider: .catalog,
            source: source.resolved,
            target: target.resolved,
            original: nil
        )
    }
}

private struct TranslationBadge: View {
    let info: TranslationBadgeInfo
    @State private var presentsDetails = false

    var body: some View {
        Button {
            presentsDetails = true
        } label: {
            Image(systemName: "character.bubble")
                .font(.caption2)
                .padding(5)
                .background(.thinMaterial, in: Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: accessibilityDescription))
        .accessibilityHint(Text("Shows translation details"))
        .popover(isPresented: $presentsDetails) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: providerDescription).font(.headline)
                if let original = info.original {
                    Text(verbatim: original).textSelection(.enabled)
                }
                Text(verbatim: "\(info.source.displayName()) → \(info.target.displayName())")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(idealWidth: 280)
            .accessibilityElement(children: .contain)
        }
    }

    private var providerDescription: String {
        info.provider == .catalog
            ? "Localized using String Catalog"
            : "Translated using \(info.provider.displayName)"
    }

    private var accessibilityDescription: String {
        "\(providerDescription), from \(info.source.displayName()) to \(info.target.displayName())"
    }
}

private struct NoTranslationModifier: ViewModifier {
    @Environment(\.autoTranslationSourceLanguage) private var source

    func body(content: Content) -> some View {
        content
            .environment(\.autoTranslationEnabled, false)
            .environment(\.locale, source.locale)
    }
}

private struct GlobalTranslationModifier: ViewModifier {
    let settings: TranslationSettings
    let sourceLanguage: TranslationLanguage
    let broker: any TranslationBrokering

    func body(content: Content) -> some View {
        let source = sourceLanguage.resolved
        let target = settings.targetLanguage.resolved
        content
            .environment(\.autoTranslationBroker, broker)
            .environment(\.autoTranslationSourceLanguage, source)
            .environment(\.autoTranslationTargetLanguage, target)
            .environment(\.autoTranslationEnabled, settings.isEnabled)
            .environment(\.locale, settings.isEnabled ? target.locale : source.locale)
    }
}

public extension View {
    /// Installs the source language, selected language, locale and dynamic
    /// translation broker for the complete subtree.
    func globalTranslation(
        settings: TranslationSettings,
        sourceLanguage: TranslationLanguage,
        broker: any TranslationBrokering
    ) -> some View {
        modifier(GlobalTranslationModifier(
            settings: settings,
            sourceLanguage: sourceLanguage,
            broker: broker
        ))
    }

    /// Disables dynamic translation and restores the source locale recursively.
    ///
    /// The source locale also affects locale-sensitive formatting (dates,
    /// numbers, measurements and similar values) in this subtree.
    func noTranslation() -> some View {
        modifier(NoTranslationModifier())
    }

    /// Adds an accessible provenance badge to any view.
    func translationLabel(_ isEnabled: Bool = true) -> some View {
        modifier(TranslationLabelModifier(enabled: isEnabled))
    }

    @available(*, deprecated, renamed: "globalTranslation(settings:sourceLanguage:broker:)")
    func autoTranslationHost(
        settings: TranslationSettings,
        sourceLanguage: TranslationLanguage,
        broker: any TranslationBrokering
    ) -> some View {
        globalTranslation(
            settings: settings,
            sourceLanguage: sourceLanguage,
            broker: broker
        )
    }
}

#if canImport(Translation)
import Translation

@available(iOS 18.0, macOS 15.0, *)
private struct AppleGlobalTranslationModifier: ViewModifier {
    let settings: TranslationSettings
    let sourceLanguage: TranslationLanguage
    let provider: AppleTranslationProvider
    let broker: TranslationBroker

    init(
        settings: TranslationSettings,
        sourceLanguage: TranslationLanguage,
        provider: AppleTranslationProvider,
        broker: TranslationBroker?,
        policy: TranslationExclusionPolicy
    ) {
        self.settings = settings
        self.sourceLanguage = sourceLanguage
        self.provider = provider
        self.broker = broker ?? TranslationBroker(provider: provider, policy: policy)
    }

    func body(content: Content) -> some View {
        content
            .globalTranslation(
                settings: settings,
                sourceLanguage: sourceLanguage,
                broker: broker
            )
            .translationTask(
                source: sourceLanguage.resolved.localeLanguage,
                target: settings.targetLanguage.resolved.localeLanguage
            ) { session in
                await provider.run(session: session)
            }
    }
}

@available(iOS 18.0, macOS 15.0, *)
public extension View {
    func globalTranslation(
        settings: TranslationSettings,
        sourceLanguage: TranslationLanguage,
        provider: AppleTranslationProvider,
        broker: TranslationBroker? = nil,
        policy: TranslationExclusionPolicy = .init()
    ) -> some View {
        modifier(AppleGlobalTranslationModifier(
            settings: settings,
            sourceLanguage: sourceLanguage,
            provider: provider,
            broker: broker,
            policy: policy
        ))
    }

    @available(*, deprecated, renamed: "globalTranslation(settings:sourceLanguage:provider:policy:)")
    func autoTranslationHost(
        settings: TranslationSettings,
        provider: AppleTranslationProvider,
        sourceLanguage: TranslationLanguage,
        policy: TranslationExclusionPolicy = .init()
    ) -> some View {
        globalTranslation(
            settings: settings,
            sourceLanguage: sourceLanguage,
            provider: provider,
            broker: nil,
            policy: policy
        )
    }
}
#endif

private extension Array {
    func asyncMap<T>(
        _ transform: (Element) async -> T
    ) async -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(await transform(element))
        }
        return values
    }
}
#endif
