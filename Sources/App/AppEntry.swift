import AppKit

@main
struct SmartScreenShotApp {

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)  // No Dock icon

        // Check Accessibility — required for CGEventTap
        if !AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
            SmartScreenShot needs Accessibility access to detect \
            screenshot keystrokes (Cmd+Shift+3/4/5).

            Grant access in System Settings \u{203A} Privacy & Security \
            \u{203A} Accessibility, then relaunch.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Quit")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            app.terminate(nil)
            return
        }

        // Build components
        let prefsStore = PreferencesStore()
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
