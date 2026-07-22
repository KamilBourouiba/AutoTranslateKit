import Foundation

/// Computes languages that are safe to select for the entire interface.
public enum GlobalLanguageSelection {
    /// Intersects translation support with the app bundle's shipped
    /// localizations. `Base` is represented by the development localization.
    public static func intersect(
        supportedLanguages: [TranslationLanguage],
        bundleLocalizations: [String],
        developmentLocalization: String? = nil
    ) -> [TranslationLanguage] {
        var localizationIDs = bundleLocalizations
        if bundleLocalizations.contains("Base"), let developmentLocalization {
            localizationIDs.append(developmentLocalization)
        }

        let localized = Set(
            localizationIDs
                .filter { $0 != "Base" }
                .map(TranslationLanguage.init(identifier:))
        )

        return Array(Set(supportedLanguages).intersection(localized)).sorted {
            $0.displayName().localizedStandardCompare($1.displayName()) == .orderedAscending
        }
    }

    public static func bundleLanguages(in bundle: Bundle = .main) -> [TranslationLanguage] {
        let identifiers = bundle.localizations.filter { $0 != "Base" }
        return Array(Set(identifiers.map(TranslationLanguage.init(identifier:)))).sorted {
            $0.rawValue < $1.rawValue
        }
    }
}
