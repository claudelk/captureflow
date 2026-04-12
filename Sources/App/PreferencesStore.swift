import Foundation
import CaptureFlowCore

/// Persists user preferences via UserDefaults.
final class PreferencesStore {

    private let defaults: UserDefaults

    init(suiteName: String = "com.captureflow.preferences") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.namerTier: "auto",
            Keys.launchAtLogin: true,
            Keys.browserCaptureEnabled: false,
            Keys.hotkeyEnabled: false,
            Keys.hotkeyKeyCode: 1,         // "s" key
            Keys.hotkeyModifiers: "control,option",
            Keys.separatePhotoVideo: true,
        ])
    }

    // MARK: - Keys

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let namerTier = "namerTier"
        static let launchAtLogin = "launchAtLogin"
        static let browserCaptureEnabled = "browserCaptureEnabled"
        static let screenshotFolderOverride = "screenshotFolderOverride"
        static let groupByApp = "groupByApp"
        static let hotkeyEnabled = "hotkeyEnabled"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let screenshotFolderBookmark = "screenshotFolderBookmark"
        static let appLanguage = "appLanguage"
        static let useCustomFolderPrefix = "useCustomFolderPrefix"
        static let customFolderPrefix = "customFolderPrefix"
        static let separatePhotoVideo = "separatePhotoVideo"
        static let photoFormat = "photoFormat"
        static let videoFormat = "videoFormat"
        static let useCustomRootFolder = "useCustomRootFolder"
        static let customRootFolderName = "customRootFolderName"
        static let useCustomDateFormat = "useCustomDateFormat"
        static let customDateFormat = "customDateFormat"
        static let migrationDone = "migrationDone"
    }

    // MARK: - Properties

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    var namerTier: String {
        get { defaults.string(forKey: Keys.namerTier) ?? "auto" }
        set { defaults.set(newValue, forKey: Keys.namerTier) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    var browserCaptureEnabled: Bool {
        get { defaults.bool(forKey: Keys.browserCaptureEnabled) }
        set { defaults.set(newValue, forKey: Keys.browserCaptureEnabled) }
    }

    var groupByApp: Bool {
        get { defaults.bool(forKey: Keys.groupByApp) }
        set { defaults.set(newValue, forKey: Keys.groupByApp) }
    }

    // MARK: - Language & Folder Prefix

    var appLanguage: String {
        get { defaults.string(forKey: Keys.appLanguage) ?? "system" }
        set { defaults.set(newValue, forKey: Keys.appLanguage) }
    }

    var useCustomFolderPrefix: Bool {
        get { defaults.bool(forKey: Keys.useCustomFolderPrefix) }
        set { defaults.set(newValue, forKey: Keys.useCustomFolderPrefix) }
    }

    var customFolderPrefix: String {
        get { defaults.string(forKey: Keys.customFolderPrefix) ?? "" }
        set { defaults.set(newValue, forKey: Keys.customFolderPrefix) }
    }

    // MARK: - Media Organization & Format

    var separatePhotoVideo: Bool {
        get { defaults.bool(forKey: Keys.separatePhotoVideo) }
        set { defaults.set(newValue, forKey: Keys.separatePhotoVideo) }
    }

    var photoFormat: String {
        get { defaults.string(forKey: Keys.photoFormat) ?? "png" }
        set { defaults.set(newValue, forKey: Keys.photoFormat) }
    }

    var videoFormat: String {
        get { defaults.string(forKey: Keys.videoFormat) ?? "mov" }
        set { defaults.set(newValue, forKey: Keys.videoFormat) }
    }

    // MARK: - Root Folder & Date Format

    var useCustomRootFolder: Bool {
        get { defaults.bool(forKey: Keys.useCustomRootFolder) }
        set { defaults.set(newValue, forKey: Keys.useCustomRootFolder) }
    }

    var customRootFolderName: String {
        get { defaults.string(forKey: Keys.customRootFolderName) ?? "" }
        set { defaults.set(newValue, forKey: Keys.customRootFolderName) }
    }

    var useCustomDateFormat: Bool {
        get { defaults.bool(forKey: Keys.useCustomDateFormat) }
        set { defaults.set(newValue, forKey: Keys.useCustomDateFormat) }
    }

    var customDateFormat: String {
        get { defaults.string(forKey: Keys.customDateFormat) ?? "" }
        set { defaults.set(newValue, forKey: Keys.customDateFormat) }
    }

    var migrationDone: Bool {
        get { defaults.bool(forKey: Keys.migrationDone) }
        set { defaults.set(newValue, forKey: Keys.migrationDone) }
    }

    // MARK: - Hotkey

    var hotkeyEnabled: Bool {
        get { defaults.bool(forKey: Keys.hotkeyEnabled) }
        set { defaults.set(newValue, forKey: Keys.hotkeyEnabled) }
    }

    /// Virtual keyCode (e.g. 1 = "s", 0 = "a"). See Events.h for full list.
    var hotkeyKeyCode: Int {
        get { defaults.integer(forKey: Keys.hotkeyKeyCode) }
        set { defaults.set(newValue, forKey: Keys.hotkeyKeyCode) }
    }

    /// Comma-separated modifier names: "control", "option", "command", "shift".
    var hotkeyModifiers: String {
        get { defaults.string(forKey: Keys.hotkeyModifiers) ?? "control,option" }
        set { defaults.set(newValue, forKey: Keys.hotkeyModifiers) }
    }

    /// Human-readable hotkey description.
    var hotkeyDescription: String {
        var parts: [String] = []
        if hotkeyModifiers.contains("control") { parts.append("\u{2303}") }
        if hotkeyModifiers.contains("option") { parts.append("\u{2325}") }
        if hotkeyModifiers.contains("shift") { parts.append("\u{21E7}") }
        if hotkeyModifiers.contains("command") { parts.append("\u{2318}") }
        parts.append(keyCodeToString(hotkeyKeyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ code: Int) -> String {
        switch code {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 8: return "C"
        case 15: return "R"
        default: return "Key(\(code))"
        }
    }

    /// Custom screenshot folder override. When nil, falls back to macOS system preference.
    var screenshotFolderOverride: String? {
        get { defaults.string(forKey: Keys.screenshotFolderOverride) }
        set { defaults.set(newValue, forKey: Keys.screenshotFolderOverride) }
    }

    /// Resolved screenshot folder: custom override > macOS system pref > ~/Desktop.
    var screenshotFolder: URL {
        if let override = screenshotFolderOverride, !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        #if MAS
        // In sandbox, fall back to bookmarked folder or Desktop
        if let bookmarked = resolveBookmarkedFolder() {
            return bookmarked
        }
        #endif
        return ScreenshotPreferences.folder
    }

    // MARK: - Security-Scoped Bookmarks (MAS sandbox)

    /// Stored bookmark data for sandbox folder access persistence.
    var screenshotFolderBookmark: Data? {
        get { defaults.data(forKey: Keys.screenshotFolderBookmark) }
        set { defaults.set(newValue, forKey: Keys.screenshotFolderBookmark) }
    }

    /// Create and store a security-scoped bookmark from a user-selected URL.
    func saveBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            screenshotFolderBookmark = bookmark
            print("[PreferencesStore] saved security-scoped bookmark for \(url.path)")
        } catch {
            print("[PreferencesStore] bookmark save failed: \(error.localizedDescription)")
        }
    }

    /// Resolve a stored security-scoped bookmark. Returns nil if no bookmark exists.
    func resolveBookmarkedFolder() -> URL? {
        guard let bookmark = screenshotFolderBookmark else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // Re-save the bookmark to refresh it
                saveBookmark(for: url)
            }
            return url
        } catch {
            print("[PreferencesStore] bookmark resolve failed: \(error.localizedDescription)")
            return nil
        }
    }
}
