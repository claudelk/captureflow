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

        // Enable / Disable
        let toggleItem = NSMenuItem(
            title: pipeline.state == .running ? L10n.string("menu.disable") : L10n.string("menu.enable"),
            action: #selector(togglePipeline(_:)),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

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
        // Update toggle title
        if let toggleItem = menu.items.first {
            toggleItem.title = pipeline.state == .running ? L10n.string("menu.disable") : L10n.string("menu.enable")
        }
        // Update re-analyze availability
        if let reanalyzeItem = menu.item(withTag: 100) {
            reanalyzeItem.isEnabled = pipeline.lastDestinationURL != nil
        }
    }

    // MARK: - Actions

    @objc private func togglePipeline(_ sender: NSMenuItem) {
        if pipeline.state == .running {
            pipeline.stop()
            preferencesStore.isEnabled = false
        } else {
            pipeline.start()
            preferencesStore.isEnabled = true
        }
    }

    @objc private func reanalyzeLast(_ sender: NSMenuItem) {
        flashIcon()
        pipeline.reanalyzeLast()
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
        panel.allowedContentTypes = [.png, .jpeg]
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
