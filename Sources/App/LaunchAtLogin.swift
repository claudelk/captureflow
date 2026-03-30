import Foundation

/// Manages a LaunchAgent plist for "launch at login" functionality.
/// Installs/uninstalls ~/Library/LaunchAgents/com.smartscreenshot.plist.
struct LaunchAtLogin {

    private let label = "com.smartscreenshot"
    private let plistURL: URL

    init() {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        self.plistURL = launchAgentsDir.appendingPathComponent("com.smartscreenshot.plist")
    }

    /// Install the LaunchAgent plist. Creates ~/Library/LaunchAgents/ if needed.
    func install() {
        let executablePath = Bundle.main.executablePath
            ?? ProcessInfo.processInfo.arguments.first
            ?? "/Applications/SmartScreenShot.app/Contents/MacOS/SmartScreenShot"

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]

        do {
            let dir = plistURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            print("[LaunchAtLogin] installed: \(plistURL.path)")
        } catch {
            print("[LaunchAtLogin] install failed: \(error.localizedDescription)")
        }
    }

    /// Remove the LaunchAgent plist and unload from launchd.
    func uninstall() {
        let unload = Process()
        unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        unload.arguments = ["bootout", "gui/\(getuid())", plistURL.path]
        try? unload.run()
        unload.waitUntilExit()

        try? FileManager.default.removeItem(at: plistURL)
        print("[LaunchAtLogin] uninstalled")
    }

    /// Whether the LaunchAgent plist currently exists on disk.
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }
}
