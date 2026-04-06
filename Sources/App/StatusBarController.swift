import AppKit
import SmartScreenShotCore
import UniformTypeIdentifiers

/// Manages the NSStatusItem and its dropdown menu.
final class StatusBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let pipeline: PipelineController
    private let preferencesStore: PreferencesStore
    private var preferencesWindow: PreferencesWindow?

    init(pipeline: PipelineController, preferencesStore: PreferencesStore) {
        self.pipeline = pipeline
        self.preferencesStore = preferencesStore
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        setupButton()
        buildMenu()
        pipeline.onRenameCompleted = { [weak self] in
            self?.flashIcon()
        }
        blinkOnStartup()
    }

    // MARK: - Setup

    private func setupButton() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: L10n.string("menu.accessibility")
            )
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Capture Full Screen — ⇧⌘3
        let fullScreenItem = NSMenuItem(
            title: L10n.string("menu.captureFullScreen"),
            action: #selector(captureFullScreen(_:)),
            keyEquivalent: ""
        )
        fullScreenItem.target = self
        fullScreenItem.keyEquivalentModifierMask = [.shift, .command]
        fullScreenItem.keyEquivalent = "3"
        menu.addItem(fullScreenItem)

        // Capture Selected Area — ⇧⌘4
        let areaItem = NSMenuItem(
            title: L10n.string("menu.captureArea"),
            action: #selector(captureArea(_:)),
            keyEquivalent: ""
        )
        areaItem.target = self
        areaItem.keyEquivalentModifierMask = [.shift, .command]
        areaItem.keyEquivalent = "4"
        menu.addItem(areaItem)

        // Record Screen — ⇧⌘5
        let recordItem = NSMenuItem(
            title: L10n.string("menu.recordScreen"),
            action: #selector(recordScreen(_:)),
            keyEquivalent: ""
        )
        recordItem.target = self
        recordItem.keyEquivalentModifierMask = [.shift, .command]
        recordItem.keyEquivalent = "5"
        menu.addItem(recordItem)

        menu.addItem(.separator())

        // Re-analyze last
        let reanalyzeItem = NSMenuItem(
            title: L10n.string("menu.reanalyze"),
            action: #selector(reanalyzeLast(_:)),
            keyEquivalent: ""
        )
        reanalyzeItem.target = self
        reanalyzeItem.tag = 100
        menu.addItem(reanalyzeItem)

        // Batch rename
        let batchItem = NSMenuItem(
            title: L10n.string("menu.batchRename"),
            action: #selector(batchRename(_:)),
            keyEquivalent: ""
        )
        batchItem.target = self
        menu.addItem(batchItem)

        // Open folder
        let openFolderItem = NSMenuItem(
            title: L10n.string("menu.openFolder"),
            action: #selector(openFolder(_:)),
            keyEquivalent: ""
        )
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        menu.addItem(.separator())

        // Preferences
        let prefsItem = NSMenuItem(
            title: L10n.string("menu.preferences"),
            action: #selector(openPreferences(_:)),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: L10n.string("menu.quit"),
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Update re-analyze availability
        if let reanalyzeItem = menu.item(withTag: 100) {
            reanalyzeItem.isEnabled = pipeline.lastDestinationURL != nil
        }
    }

    // MARK: - Actions

    @objc private func captureFullScreen(_ sender: NSMenuItem) {
        statusItem.menu?.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x"] // silent full screen
            try? task.run()
        }
    }

    @objc private func captureArea(_ sender: NSMenuItem) {
        statusItem.menu?.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-ix"] // interactive selection, silent
            try? task.run()
        }
    }

    @objc private func recordScreen(_ sender: NSMenuItem) {
        statusItem.menu?.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-v"] // video recording mode
            try? task.run()
        }
    }

    @objc private func reanalyzeLast(_ sender: NSMenuItem) {
        flashIcon()
        pipeline.reanalyzeLast()
    }

    /// Blink the menu bar icon 3 times on startup so the user knows it's running.
    private func blinkOnStartup() {
        guard let button = statusItem.button else { return }
        let original = button.image
        var count = 0

        func blink() {
            guard count < 6 else { return } // 3 on + 3 off = 6 toggles
            count += 1
            button.image = (count % 2 == 1) ? nil : original
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { blink() }
        }
        blink()
    }

    /// Briefly flash the menu bar icon to indicate activity.
    private func flashIcon() {
        guard let button = statusItem.button else { return }
        let original = button.image

        button.image = NSImage(
            systemSymbolName: "camera.viewfinder.fill",
            accessibilityDescription: L10n.string("menu.accessibilityWorking")
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            button.image = original
        }
    }

    @objc private func batchRename(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .quickTimeMovie, .mpeg4Movie]
        panel.message = L10n.string("dialog.selectScreenshots")
        panel.prompt = L10n.string("dialog.rename")
        panel.directoryURL = pipeline.screenshotFolder

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let urls = panel.urls
        let langCode = L10n.activeLanguageCode
        let namer = PipelineController.createNamer(tier: preferencesStore.namerTier, languageCode: langCode)
        let prefix = PipelineController.resolvePrefix(preferencesStore: preferencesStore, languageCode: langCode)
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: namer, store: store, folderPrefix: prefix)

        Task {
            var succeeded = 0
            for url in urls {
                if let _ = await engine.processManual(file: url) {
                    succeeded += 1
                }
            }
            print("[BatchRename] Renamed \(succeeded)/\(urls.count) files")
        }
    }

    @objc private func openFolder(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(pipeline.screenshotFolder)
    }

    @objc private func openPreferences(_ sender: NSMenuItem) {
        if preferencesWindow == nil {
            let pw = PreferencesWindow(preferencesStore: preferencesStore)
            pw.onFolderChanged = { [weak self] in
                guard let self, self.pipeline.state == .running else { return }
                self.pipeline.stop()
                self.pipeline.start()
            }
            #if !MAS
            pw.onHotkeyChanged = { [weak self] in
                self?.pipeline.restartHotkeyMonitor()
            }
            #endif
            preferencesWindow = pw
        }
        preferencesWindow?.showWindow()
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}
