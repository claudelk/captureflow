import Foundation

/// Localization helper. Resolves strings based on the user's language preference
/// (or system default). Loads the appropriate `.lproj` bundle from the resource bundle.
enum L10n {

    private static let supportedLanguages = ["en", "fr", "es", "pt", "sw"]

    /// The resource bundle containing localization files.
    /// SPM's generated `Bundle.module` looks at `Bundle.main.bundleURL` (the .app root),
    /// but macOS .app bundles store resources in `Contents/Resources/`. When running from
    /// a manually assembled .app bundle, Bundle.module crashes because the resource bundle
    /// isn't at the root. This accessor checks `Contents/Resources/` first, then falls back
    /// to SPM's default resolution.
    private static let resourceBundle: Bundle = {
        let bundleName = "CaptureFlow_CaptureFlow"

        // 1. Standard .app location: Contents/Resources/
        if let resourceURL = Bundle.main.resourceURL {
            let appBundlePath = resourceURL.appendingPathComponent("\(bundleName).bundle").path
            if let bundle = Bundle(path: appBundlePath) {
                return bundle
            }
        }

        // 2. SPM default: next to the executable (works during `swift run`)
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle").path
        if let bundle = Bundle(path: mainPath) {
            return bundle
        }

        // 3. Fall back to Bundle.module (works during development builds)
        return Bundle.module
    }()

    /// Returns the localized string for the given key.
    static func string(_ key: String) -> String {
        activeBundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// The resolved language code: user override, system preferred, or "en".
    static var activeLanguageCode: String {
        let stored = UserDefaults(suiteName: "com.captureflow.preferences")?
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
        if let path = resourceBundle.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        // Fallback to English
        if let path = resourceBundle.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return resourceBundle
    }
}
