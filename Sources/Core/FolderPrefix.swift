import Foundation

/// Maps language codes to localized folder names used throughout the app.
/// These are deterministic strings — NOT NSLocalizedString lookups.
public enum FolderPrefix {

    // MARK: - Legacy daily folder prefix (used for migration scanning & groupByApp)

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

    /// All known prefixes (for migration scanning).
    public static var allPrefixes: [String] { Array(defaults.values) }

    // MARK: - Root folder name (user-facing, proper capitalization)

    private static let rootFolderNames: [String: String] = [
        "en": "Screenshots",
        "fr": "Captures d\u{2019}\u{00E9}cran",
        "es": "Capturas de pantalla",
        "pt": "Capturas de tela",
        "sw": "Picha za skrini",
    ]

    /// Returns the localized root folder name (e.g. "Screenshots", "Captures d'écran").
    /// Falls back to English for unsupported languages.
    public static func rootFolderName(for languageCode: String) -> String {
        rootFolderNames[languageCode] ?? rootFolderNames["en"]!
    }

    // MARK: - Subfolder names (localized)

    private static let imagesFolderNames: [String: String] = [
        "en": "images",
        "fr": "images",
        "es": "im\u{00E1}genes",
        "pt": "imagens",
        "sw": "picha",
    ]

    private static let videosFolderNames: [String: String] = [
        "en": "videos",
        "fr": "vid\u{00E9}os",
        "es": "v\u{00ED}deos",
        "pt": "v\u{00ED}deos",
        "sw": "video",
    ]

    /// Returns the localized "images" subfolder name.
    public static func imagesFolderName(for languageCode: String) -> String {
        imagesFolderNames[languageCode] ?? imagesFolderNames["en"]!
    }

    /// Returns the localized "videos" subfolder name.
    public static func videosFolderName(for languageCode: String) -> String {
        videosFolderNames[languageCode] ?? videosFolderNames["en"]!
    }
}
