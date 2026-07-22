# AutoTranslateKit 2

AutoTranslateKit is a native-first translation architecture for SwiftUI.

“Translated by default” has two precise meanings:

1. Static interface copy uses SwiftUI’s native `LocalizedStringKey` /
   `LocalizedStringResource`, the app’s String Catalog, and the environment
   locale. Native literal APIs need no wrapper.
2. Runtime strings must be explicitly instrumented with `DisplayString` or
   `TranslatedText`. The `AutoTranslateGuard` plugin enforces that boundary.

## Requirements

- Swift 5.9+
- Xcode 16+
- iOS 18+ or macOS 15+ for Apple Translation

## Installation

Add the package and link the `AutoTranslateKit` library to the app target.
Version 2 follows semantic versioning:

```swift
.package(
    url: "https://github.com/KamilBourouiba/AutoTranslateKit.git",
    from: "2.0.0"
)
```

Add the `AutoTranslateGuard` build-tool plugin to every client target that
renders UI:

```swift
.target(
    name: "MyApp",
    dependencies: ["AutoTranslateKit"],
    plugins: [
        .plugin(
            name: "AutoTranslateGuard",
            package: "AutoTranslateKit"
        )
    ]
)
```

Xcode users can add the same plugin in the target’s Build Tool Plug-ins
section. SwiftPM cannot force a plugin onto a consuming target; adding the
guard is therefore a required integration step.

## Native static UI

Create String Catalog entries in every app localization, then install one
host at the root:

```swift
import AutoTranslateKit
import SwiftUI

@main
struct ExampleApp: App {
    @State private var settings = TranslationSettings(targetLanguage: .french)
    private let provider = AppleTranslationProvider()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Text("Settings")
                    Button("Save") { save() }
                    Label("Account", systemImage: "person")
                }
                .navigationTitle("Settings")
            }
            .globalTranslation(
                settings: settings,
                sourceLanguage: .english,
                provider: provider
            )
        }
    }
}
```

`Text("Settings")`, literal `Button`, `Label`, `Picker`, alerts, and literal
`navigationTitle` values are localized by SwiftUI and the String Catalog.
The host injects the source language, selected language, locale, and dynamic
translation broker.

## Global opt-out

```swift
BrandView().noTranslation()
```

`noTranslation()` applies recursively. It disables dynamic translation and
sets the subtree’s locale back to the source locale, so native catalog-backed
views also return to the source language. This intentionally changes all
locale-sensitive formatting in that subtree, including dates, numbers,
measurements, lists, and currencies.

For one value:

```swift
TranslatedText(DisplayString.dynamic(serverTitle, source: .english).noTranslation())
Text(verbatim: DisplayString.verbatim(productName).rawValue)
```

## Dynamic strings

Runtime strings cannot be intercepted through Apple’s public SwiftUI APIs.
Use an explicit value:

```swift
TranslatedText(.dynamic(model.title, source: .english))
TranslatedText(.localized("profile.title"))
TranslatedText(.verbatim(account.username))
```

`DisplayString` has three intents:

- `.localized(LocalizedStringResource)` — static/catalog-backed copy.
- `.dynamic(String, source:)` — runtime copy sent through the broker.
- `.verbatim(String)` — content that must never be translated.

`TranslationBroker` retains caching, concurrent request deduplication,
exclusion policy, exact provider provenance, original-text fallback, and batch
translation. `AppleTranslationProvider` is driven by SwiftUI’s
`TranslationSession`; custom providers implement `TranslationProviding`.

## Provenance badge

Apply `.translationLabel()` to any view:

```swift
Text("Settings")
    .translationLabel()

TranslatedText(.dynamic(message, source: .english))
    .translationLabel()
```

Native/catalog content reports **Localized using String Catalog**.
`TranslatedText` reports the exact Apple/custom provider. The accessible badge
appears only when the selected language differs from the source or a dynamic
result was actually translated.

## Choosing a global language

A global language must have both Apple dynamic-translation support and a
complete static app localization:

```swift
let choices = await TranslationLanguage.globallySelectableLanguages(in: .main)
```

For testable or non-Translation code, use:

```swift
GlobalLanguageSelection.intersect(
    supportedLanguages: appleLanguages,
    bundleLocalizations: Bundle.main.localizations,
    developmentLocalization: Bundle.main.developmentLocalization
)
```

Dynamic-only workflows may use every language returned by
`TranslationLanguage.appleSupportedLanguages()`. Do not offer those languages
as a whole-app selection unless the app also ships their String Catalog
localization.

## AutoTranslateGuard

The SwiftSyntax/SwiftParser build plugin fails with file/line diagnostics for
detectable raw runtime display points:

- `Text(variable)`, `Button(variable)`, and `Label(variable)`
- dynamic `navigationTitle`, `accessibilityLabel`, and alerts
- UIKit `.text` / `.title` assignments and `setTitle(variable, ...)`

It allows localizable literals (including literal interpolation),
`LocalizedStringResource`, `String(localized:)`, `DisplayString`,
`TranslatedText`, and expressions or lines marked `noTranslation` (the
`// autotranslate:ignore` marker is also recognized).

The build plugin never rewrites source. Run the command plugin explicitly for
safe, simple `Text(identifier)` rewrites:

```sh
swift package plugin --allow-writing-to-package-directory \
  autotranslate-guard --fix
```

Complex expressions are diagnostics only.

## Apple public-API limits

No public API can swizzle or inspect arbitrary SwiftUI text after construction.
A root environment locale localizes catalog-backed literals, but cannot turn a
runtime `String` into localizable static copy. Apple Translation also requires
a live `TranslationSession`; supported languages and downloaded assets vary by
OS, region, and device. AutoTranslateKit exposes these boundaries rather than
claiming transparent interception.

## Development

```sh
swift test
swift run AutoTranslateGuardScanner Tests/Fixtures
```

See [CONTRIBUTING.md](CONTRIBUTING.md). The project is available under the
[MIT License](LICENSE).
