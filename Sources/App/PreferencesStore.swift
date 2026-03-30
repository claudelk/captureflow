import Foundation
import SmartScreenShotCore

/// Persists user preferences via UserDefaults.
final class PreferencesStore {

    private let defaults: UserDefaults

    init(suiteName: String = "com.smartscreenshot.app") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.namerTier: "vision-only",
            Keys.launchAtLogin: false,
            Keys.browserCaptureEnabled: false,
        ])
    }

    // MARK: - Keys

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let namerTier = "namerTier"
        static let launchAtLogin = "launchAtLogin"
        static let browserCaptureEnabled = "browserCaptureEnabled"
        static let screenshotFolderOverride = "screenshotFolderOverride"
    }

    // MARK: - Properties

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.isEnabled) }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    var namerTier: String {
        get { defaults.string(forKey: Keys.namerTier) ?? "vision-only" }
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
        return ScreenshotPreferences.folder
    }
}
