import AppKit
import CaptureFlowCore
import UserNotifications

@main
struct CaptureFlowApp {

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)  // No Dock icon

        // Build components
        let prefsStore = PreferencesStore()

        // --- First-launch setup ---
        let defaults = UserDefaults(suiteName: "com.captureflow.preferences")
        let firstLaunchDone = defaults?.bool(forKey: "firstLaunchDone") ?? false

        if !firstLaunchDone {
            defaults?.set(true, forKey: "firstLaunchDone")

            let alert = NSAlert()
            alert.messageText = L10n.string("alert.welcomeTitle")
            alert.informativeText = L10n.string("alert.welcomeBody")
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.string("alert.welcomeUseDefault"))
            alert.addButton(withTitle: L10n.string("alert.welcomeChooseFolder"))
            alert.icon = NSImage(named: NSImage.applicationIconName)

            let response = alert.runModal()

            if response == .alertSecondButtonReturn {
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
            }

            let folder = prefsStore.screenshotFolder
            _ = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        }

        // --- Permissions (first launch only) ---
        #if !MAS
        if !firstLaunchDone {
            // 1. Accessibility — needed for keystroke detection and capture shortcuts
            if !AXIsProcessTrusted() {
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

        // --- Start the app immediately ---
        let pipeline = PipelineController(preferencesStore: prefsStore)
        let statusBar = StatusBarController(pipeline: pipeline, preferencesStore: prefsStore)

        if prefsStore.isEnabled {
            pipeline.start()
        }

        // Pop open the menu so the user sees the app is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            statusBar.showMenu()
        }

        // Notify user the app is running
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "CaptureFlow"
            content.body = L10n.string("alert.appReady")
            let request = UNNotificationRequest(
                identifier: "appReady",
                content: content,
                trigger: nil
            )
            center.add(request)
        }

        print("CaptureFlow ready.")

        // --- Migration (runs in background, non-blocking) ---
        if !prefsStore.migrationDone {
            let langCode = L10n.activeLanguageCode
            let rootFolderName = PipelineController.resolveRootFolderName(preferencesStore: prefsStore, languageCode: langCode)
            let screenshotFolder = prefsStore.screenshotFolder
            let scanResult = MigrationEngine.scan(in: screenshotFolder, rootFolderName: rootFolderName)

            if !scanResult.isEmpty {
                let alert = NSAlert()
                alert.messageText = L10n.string("migration.title")
                alert.informativeText = String(
                    format: L10n.string("migration.body"),
                    scanResult.fileCount, scanResult.folderCount
                )
                alert.alertStyle = .informational
                alert.addButton(withTitle: L10n.string("migration.organize"))
                alert.addButton(withTitle: L10n.string("migration.skip"))
                alert.icon = NSImage(named: NSImage.applicationIconName)

                if alert.runModal() == .alertFirstButtonReturn {
                    let dateFormatter = PipelineController.resolveDateFormatter(preferencesStore: prefsStore)
                    let namer = PipelineController.createNamer(tier: prefsStore.namerTier, languageCode: langCode)

                    // Update menu bar icon to show migration in progress
                    DispatchQueue.main.async {
                        if let button = statusBar.statusButton {
                            button.image = NSImage(
                                systemSymbolName: "arrow.triangle.2.circlepath",
                                accessibilityDescription: L10n.string("menu.accessibilityWorking")
                            )
                        }
                    }

                    // Run migration in background
                    Task.detached {
                        let organized = await MigrationEngine.run(
                            scanResult: scanResult,
                            screenshotFolder: screenshotFolder,
                            rootFolderName: rootFolderName,
                            dateFormatter: dateFormatter,
                            separateSubfolders: prefsStore.separatePhotoVideo,
                            imagesFolderName: FolderPrefix.imagesFolderName(for: langCode),
                            videosFolderName: FolderPrefix.videosFolderName(for: langCode),
                            namer: namer,
                            progress: { completed, total in
                                print("[Migration] \(completed)/\(total)")
                            }
                        )
                        print("[Migration] Complete: \(organized) items organized")

                        DispatchQueue.main.async {
                            if let button = statusBar.statusButton {
                                button.image = NSImage(
                                    systemSymbolName: "camera.viewfinder",
                                    accessibilityDescription: L10n.string("menu.accessibility")
                                )
                            }
                        }

                        let content = UNMutableNotificationContent()
                        content.title = "CaptureFlow"
                        content.body = String(format: L10n.string("migration.complete"), organized)
                        let request = UNNotificationRequest(
                            identifier: "migrationComplete",
                            content: content,
                            trigger: nil
                        )
                        try? await center.add(request)
                    }
                }
            }

            prefsStore.migrationDone = true
        }

        withExtendedLifetime((statusBar, pipeline, prefsStore)) {
            app.run()
        }
    }
}
