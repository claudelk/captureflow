import Foundation

/// Reads macOS screenshot preferences.
public enum ScreenshotPreferences {

    /// The folder where macOS saves screenshots.
    /// Source: `com.apple.screencapture` `location` pref.
    /// Fallback: `~/Desktop` when the pref is absent or empty.
    public static var folder: URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
    }
}
