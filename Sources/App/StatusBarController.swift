import AppKit
import CaptureFlowCore
import UniformTypeIdentifiers

/// Manages the NSStatusItem and its dropdown menu.
final class StatusBarController: NSObject, NSMenuDelegate {

    let statusItem: NSStatusItem

    /// Public access to the status bar button for icon updates (e.g. migration progress).
    var statusButton: NSStatusBarButton? { statusItem.button }
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

        // How to Capture — submenu showing native shortcuts
        let captureSubmenu = NSMenu()

        let fullScreenHint = NSMenuItem(title: L10n.string("menu.hintFullScreen"), action: nil, keyEquivalent: "")
        fullScreenHint.keyEquivalentModifierMask = [.shift, .command]
        fullScreenHint.keyEquivalent = "3"
        fullScreenHint.isEnabled = false
        captureSubmenu.addItem(fullScreenHint)

        let areaHint = NSMenuItem(title: L10n.string("menu.hintArea"), action: nil, keyEquivalent: "")
        areaHint.keyEquivalentModifierMask = [.shift, .command]
        areaHint.keyEquivalent = "4"
        areaHint.isEnabled = false
        captureSubmenu.addItem(areaHint)

        let toolbarHint = NSMenuItem(title: L10n.string("menu.hintToolbar"), action: nil, keyEquivalent: "")
        toolbarHint.keyEquivalentModifierMask = [.shift, .command]
        toolbarHint.keyEquivalent = "5"
        toolbarHint.isEnabled = false
        captureSubmenu.addItem(toolbarHint)

        let captureParent = NSMenuItem(title: L10n.string("menu.howToCapture"), action: nil, keyEquivalent: "")
        captureParent.submenu = captureSubmenu
        menu.addItem(captureParent)

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

        // Organize existing screenshots
        let organizeItem = NSMenuItem(
            title: L10n.string("menu.organize"),
            action: #selector(organizeExisting(_:)),
            keyEquivalent: ""
        )
        organizeItem.target = self
        menu.addItem(organizeItem)

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

    /// Programmatically open the status bar menu.
    func showMenu() {
        statusItem.button?.performClick(nil)
    }

    // MARK: - Actions

    @objc private func reanalyzeLast(_ sender: NSMenuItem) {
        flashIcon()
        pipeline.reanalyzeLast()
    }

    /// Blink the menu bar icon 3 times on startup so the user knows it's running.
    private func blinkOnStartup() {
        guard let button = statusItem.button else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return }
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
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return }
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
        let rootFolder = PipelineController.resolveRootFolderName(preferencesStore: preferencesStore, languageCode: langCode)
        let dateFormatter = PipelineController.resolveDateFormatter(preferencesStore: preferencesStore)
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: namer, store: store, folderPrefix: prefix,
            rootFolderName: rootFolder, separateSubfolders: preferencesStore.separatePhotoVideo,
            imagesFolderName: FolderPrefix.imagesFolderName(for: langCode),
            videosFolderName: FolderPrefix.videosFolderName(for: langCode),
            dateFormatter: dateFormatter
        )

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

    @objc private func organizeExisting(_ sender: NSMenuItem) {
        let langCode = L10n.activeLanguageCode
        let rootFolderName = PipelineController.resolveRootFolderName(preferencesStore: preferencesStore, languageCode: langCode)
        let screenshotFolder = pipeline.screenshotFolder
        let scanResult = MigrationEngine.scan(in: screenshotFolder, rootFolderName: rootFolderName)

        guard !scanResult.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L10n.string("migration.title")
            alert.informativeText = L10n.string("migration.nothingFound")
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

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

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let dateFormatter = PipelineController.resolveDateFormatter(preferencesStore: preferencesStore)
        let namer = PipelineController.createNamer(tier: preferencesStore.namerTier, languageCode: langCode)

        Task {
            let organized = await MigrationEngine.run(
                scanResult: scanResult,
                screenshotFolder: screenshotFolder,
                rootFolderName: rootFolderName,
                dateFormatter: dateFormatter,
                separateSubfolders: preferencesStore.separatePhotoVideo,
                imagesFolderName: FolderPrefix.imagesFolderName(for: langCode),
                videosFolderName: FolderPrefix.videosFolderName(for: langCode),
                namer: namer,
                progress: { completed, total in
                    print("[Organize] \(completed)/\(total)")
                }
            )
            print("[Organize] Complete: \(organized) items organized")
        }
    }

    @objc private func openFolder(_ sender: NSMenuItem) {
        let langCode = L10n.activeLanguageCode
        let rootName = PipelineController.resolveRootFolderName(preferencesStore: preferencesStore, languageCode: langCode)
        let rootURL = pipeline.screenshotFolder.appendingPathComponent(rootName)
        // Open root folder if it exists, otherwise fall back to screenshot folder
        if FileManager.default.fileExists(atPath: rootURL.path) {
            NSWorkspace.shared.open(rootURL)
        } else {
            NSWorkspace.shared.open(pipeline.screenshotFolder)
        }
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
