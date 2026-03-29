import AppKit
import Foundation
import SmartScreenShotCore

@main
struct SmartScreenShotDaemon {

    static func main() {
        print("SmartScreenShot daemon starting...")

        // Check Accessibility — required for CGEventTap
        if !AXIsProcessTrusted() {
            fputs("""

            [!] Accessibility permission required.

                Opening System Settings › Privacy & Security › Accessibility
                Enable your terminal app, then re-run:

                    .build/debug/ssd

            """, stderr)
            // Open the Accessibility pane directly — avoids AXIsProcessTrustedWithOptions bridging issues
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
            try? open.run()
            exit(1)
        }

        // Read screenshot destination
        let screenshotFolder = ScreenshotPreferences.folder
        print("Screenshot folder: \(screenshotFolder.path)")

        // Build the pipeline
        let store  = CaptureContextStore()
        let namer  = VisionOnlyNamer()
        let engine = RenameEngine(namer: namer, store: store)

        // FSEvents watcher — fires when a new PNG lands in the screenshot folder
        let watcher = ScreenshotWatcher(folderURL: screenshotFolder) { url in
            Task { await engine.process(newFile: url) }
        }
        watcher.start()

        // CGEventTap — captures app context at the exact keystroke moment
        let tap = KeystrokeTap(store: store)
        do {
            try tap.start()
        } catch {
            fputs("[!] Event tap error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        print("""

        Ready. Take a screenshot (Cmd+Shift+3/4/5) to test.
        Press Ctrl+C to stop.
        """)

        // Keep the daemon alive — callbacks fire on the main RunLoop
        RunLoop.main.run()
    }
}
