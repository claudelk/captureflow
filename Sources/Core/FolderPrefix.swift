import Foundation

/// Maps language codes to localized "screenshot" folder prefix words.
/// These are deterministic slugs for folder names — NOT NSLocalizedString lookups.
public enum FolderPrefix {

    private static let defaults: [String: String] = [
        "en": "screenshot",
        "fr": "capture-d-ecran",
        "es": "captura-de-pantalla",
        "pt": "captura-de-tela",
        "sw": "picha-ya-skrini",
    ]

    /// Returns the localized folder prefix for the given language code.
    /// Falls back to "screenshot" for unsupported languages.
    public static func prefix(for languageCode: String) -> String {
        defaults[languageCode] ?? defaults["en"]!
    }
}
