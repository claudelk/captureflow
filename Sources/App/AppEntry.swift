import AppKit
import UserNotifications

@main
struct SmartScreenShotApp {

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)  // No Dock icon

        // Build components
        let prefsStore = PreferencesStore()

        // --- First-launch setup ---
        let defaults = UserDefaults(suiteName: "com.smartscreenshot.preferences")
        let firstLaunchDone = defaults?.bool(forKey: "firstLaunchDone") ?? false

        if !firstLaunchDone {
            defaults?.set(true, forKey: "firstLaunchDone")

            // Explain what the app needs, then let the user pick a folder.
            // This triggers the macOS folder access dialog in context
            // (instead of a random popup later).
            let alert = NSAlert()
            alert.messageText = L10n.string("alert.welcomeTitle")
            alert.informativeText = L10n.string("alert.welcomeBody")
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.string("alert.welcomeUseDefault"))
            alert.addButton(withTitle: L10n.string("alert.welcomeChooseFolder"))
            alert.icon = NSImage(named: NSImage.applicationIconName)

            let response = alert.runModal()

            if response == .alertSecondButtonReturn {
                // User wants to pick a folder
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = false
                panel.allowsMultipleSelection = false
                panel.prompt = L10n.string("prefs.select")
                panel.message = L10n.string("alert.selectFolder")
                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")

                if panel.runModal() == .OK, let url = panel.url {
                    prefsStore.screenshotFolderOverride = url.path
                    #if MAS
                    prefsStore.saveBookmark(for: url)
                    #endif
                }
                // If cancelled, fall through to default Desktop
            }

            // For non-MAS: trigger Desktop access now by reading the folder,
            // so the system dialog appears in context (not randomly later).
            let folder = prefsStore.screenshotFolder
            _ = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        }

        #if !MAS
        // Accessibility (optional, one-time prompt)
        if !AXIsProcessTrusted() {
            let prompted = defaults?.bool(forKey: "accessibilityPromptShown") ?? false

            if !prompted {
                defaults?.set(true, forKey: "accessibilityPromptShown")

                let alert = NSAlert()
                alert.messageText = L10n.string("alert.accessibilityTitle")
                alert.informativeText = L10n.string("alert.accessibilityBody")
                alert.alertStyle = .informational
                alert.addButton(withTitle: L10n.string("alert.openSettings"))
                alert.addButton(withTitle: L10n.string("alert.continueWithout"))

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
            }
        }
        #endif

        let pipeline = PipelineController(preferencesStore: prefsStore)
        let statusBar = StatusBarController(pipeline: pipeline, preferencesStore: prefsStore)

        if prefsStore.isEnabled {
            pipeline.start()
        }

        // Notify user the app is running
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "SmartScreenShot"
            content.body = L10n.string("alert.appReady")
            let request = UNNotificationRequest(
                identifier: "appReady",
                content: content,
                trigger: nil
            )
            center.add(request)
        }

        print("SmartScreenShot ready.")

        withExtendedLifetime((statusBar, pipeline, prefsStore)) {
            app.run()
        }
    }
}
