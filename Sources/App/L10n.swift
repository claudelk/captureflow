import Foundation

/// Localization helper. Resolves strings based on the user's language preference
/// (or system default). Loads the appropriate `.lproj` bundle from `Bundle.module`.
enum L10n {

    private static let supportedLanguages = ["en", "fr", "es", "pt", "sw"]

    /// Returns the localized string for the given key.
    static func string(_ key: String) -> String {
        activeBundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// The resolved language code: user override → system preferred → "en".
    static var activeLanguageCode: String {
        let stored = UserDefaults(suiteName: "com.smartscreenshot.preferences")?
            .string(forKey: "appLanguage") ?? "system"

        if stored != "system" && supportedLanguages.contains(stored) {
            return stored
        }

        // Pick first supported language from system preferences
        let preferred = Locale.preferredLanguages
            .compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        return preferred.first(where: { supportedLanguages.contains($0) }) ?? "en"
    }

    /// The active localization bundle.
    private static var activeBundle: Bundle {
        let code = activeLanguageCode
        if let path = Bundle.module.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        // Fallback to English
        if let path = Bundle.module.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return Bundle.module
    }
}
