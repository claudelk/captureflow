import AppKit

@main
struct SmartScreenShotApp {

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)  // No Dock icon

        #if !MAS
        // Accessibility is needed for CGEventTap (keystroke detection).
        // If not granted, the app still works — just without keystroke context.
        // Show the prompt only once per install; after that, silently continue.
        if !AXIsProcessTrusted() {
            let defaults = UserDefaults(suiteName: "com.smartscreenshot.preferences")
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
        // Continue running — pipeline will skip KeystrokeTap if it fails
        #endif

        // Build components
        let prefsStore = PreferencesStore()

        #if MAS
        // First-launch: ask user to select screenshot folder for sandbox access
        if prefsStore.screenshotFolderBookmark == nil && prefsStore.screenshotFolderOverride == nil {
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
                prefsStore.saveBookmark(for: url)
            } else {
                // User cancelled — use Desktop as fallback, they can change later
                let desktop = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                prefsStore.screenshotFolderOverride = desktop.path
                prefsStore.saveBookmark(for: desktop)
            }
        }
        #endif

        let pipeline = PipelineController(preferencesStore: prefsStore)
        let statusBar = StatusBarController(pipeline: pipeline, preferencesStore: prefsStore)

        // Start the pipeline if enabled (default: true on first launch)
        if prefsStore.isEnabled {
            pipeline.start()
        }

        print("SmartScreenShot ready.")

        // Keep strong references alive for the app lifetime
        withExtendedLifetime((statusBar, pipeline, prefsStore)) {
            app.run()
        }
    }
}
