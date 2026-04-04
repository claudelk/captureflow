import AppKit
import SmartScreenShotCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Programmatic preferences window — no storyboard, no NIB.
final class PreferencesWindow: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let preferencesStore: PreferencesStore
    private let launchAgent = LaunchAtLogin()
    private var folderLabel: NSTextField?
    /// Called when the screenshot folder changes so the pipeline can restart.
    var onFolderChanged: (() -> Void)?
    #if !MAS
    /// Called when the hotkey enabled state changes so the pipeline can restart the monitor.
    var onHotkeyChanged: (() -> Void)?
    #endif

    init(preferencesStore: PreferencesStore) {
        self.preferencesStore = preferencesStore
        super.init()
    }

    func showWindow() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            activateApp()
            return
        }

        #if MAS
        let windowHeight: CGFloat = 280
        #else
        let windowHeight: CGFloat = 360
        #endif

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "SmartScreenShot Preferences"
        w.center()
        w.delegate = self
        w.isReleasedWhenClosed = false

        let content = NSView(frame: w.contentView!.bounds)
        content.autoresizingMask = [.width, .height]

        #if MAS
        var y: CGFloat = 235
        #else
        var y: CGFloat = 315
        #endif

        // --- Screenshot Folder ---
        content.addSubview(makeLabel("Save screenshots to:", at: y))

        let folderPath = NSTextField(labelWithString: preferencesStore.screenshotFolder.path)
        folderPath.frame = NSRect(x: 160, y: y, width: 200, height: 20)
        folderPath.font = .systemFont(ofSize: 11)
        folderPath.textColor = .secondaryLabelColor
        folderPath.lineBreakMode = .byTruncatingMiddle
        self.folderLabel = folderPath
        content.addSubview(folderPath)

        let chooseButton = NSButton(title: "Choose\u{2026}", target: self, action: #selector(chooseFolder(_:)))
        chooseButton.bezelStyle = .rounded
        chooseButton.frame = NSRect(x: 365, y: y - 4, width: 75, height: 28)
        content.addSubview(chooseButton)

        // Reset button — only shown when a custom folder is set
        let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetFolder(_:)))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 365, y: y - 30, width: 75, height: 24)
        resetButton.font = .systemFont(ofSize: 11)
        resetButton.isHidden = preferencesStore.screenshotFolderOverride == nil
        resetButton.tag = 200
        content.addSubview(resetButton)

        y -= 65

        // --- Naming Mode ---
        content.addSubview(makeLabel("Naming Mode:", at: y))

        let tierPopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 230, height: 26), pullsDown: false)
        tierPopup.addItems(withTitles: ["Standard"])
        tierPopup.target = self
        tierPopup.action = #selector(namerTierChanged(_:))

        // Tier 2: Enhanced (Apple Intelligence)
        let tier2Available = Self.isFoundationModelsAvailable()

        let tier2Title = tier2Available
            ? "Enhanced (Apple Intelligence)"
            : "Enhanced (Apple Intelligence) \u{2014} Unavailable"
        let tier2 = NSMenuItem(title: tier2Title, action: nil, keyEquivalent: "")
        tier2.isEnabled = tier2Available
        tierPopup.menu?.addItem(tier2)

        let tier3 = NSMenuItem(title: "Advanced (On-device AI) \u{2014} Coming Soon", action: nil, keyEquivalent: "")
        tier3.isEnabled = false
        tierPopup.menu?.addItem(tier3)

        // Select current tier — "auto" selects Enhanced if available
        let currentTier = preferencesStore.namerTier
        if tier2Available && (currentTier == "auto" || currentTier == "foundation-models") {
            tierPopup.selectItem(at: 1)
        } else {
            tierPopup.selectItem(at: 0)
        }
        content.addSubview(tierPopup)

        y -= 40

        // --- Group by App ---
        let groupByAppCheckbox = NSButton(
            checkboxWithTitle: "Group screenshots by frontmost app",
            target: self,
            action: #selector(groupByAppToggled(_:))
        )
        groupByAppCheckbox.frame.origin = NSPoint(x: 20, y: y)
        groupByAppCheckbox.state = preferencesStore.groupByApp ? .on : .off
        content.addSubview(groupByAppCheckbox)

        y -= 40

        // --- Launch at Login ---
        let launchCheckbox = NSButton(
            checkboxWithTitle: "Launch at login",
            target: self,
            action: #selector(launchAtLoginToggled(_:))
        )
        launchCheckbox.frame.origin = NSPoint(x: 20, y: y)
        launchCheckbox.state = preferencesStore.launchAtLogin ? .on : .off
        content.addSubview(launchCheckbox)

        #if !MAS
        y -= 40

        // --- Browser URL Capture (stubbed) ---
        let browserCheckbox = NSButton(
            checkboxWithTitle: "Capture browser URL in filename (experimental)",
            target: self,
            action: #selector(browserCaptureToggled(_:))
        )
        browserCheckbox.frame.origin = NSPoint(x: 20, y: y)
        browserCheckbox.state = preferencesStore.browserCaptureEnabled ? .on : .off
        browserCheckbox.isEnabled = false
        content.addSubview(browserCheckbox)

        y -= 40

        // --- Global Hotkey ---
        let hotkeyCheckbox = NSButton(
            checkboxWithTitle: "Global hotkey for rename",
            target: self,
            action: #selector(hotkeyToggled(_:))
        )
        hotkeyCheckbox.frame.origin = NSPoint(x: 20, y: y)
        hotkeyCheckbox.state = preferencesStore.hotkeyEnabled ? .on : .off
        content.addSubview(hotkeyCheckbox)

        let hotkeyLabel = makeLabel(
            preferencesStore.hotkeyDescription,
            at: y,
            size: 12,
            color: .secondaryLabelColor
        )
        hotkeyLabel.frame.origin.x = 230
        hotkeyLabel.frame.size.width = 120
        content.addSubview(hotkeyLabel)
        #endif

        // --- Version ---
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let versionLabel = makeLabel(
            "SmartScreenShot v\(version)",
            at: 15,
            size: 11,
            color: .tertiaryLabelColor
        )
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 0, y: 10, width: 460, height: 16)
        content.addSubview(versionLabel)

        w.contentView = content
        w.makeKeyAndOrderFront(nil)
        activateApp()
        self.window = w
    }

    // MARK: - Actions

    @objc private func chooseFolder(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose where screenshots will be saved and organized"
        panel.directoryURL = preferencesStore.screenshotFolder

        guard panel.runModal() == .OK, let url = panel.url else { return }

        preferencesStore.screenshotFolderOverride = url.path
        #if MAS
        preferencesStore.saveBookmark(for: url)
        #endif
        folderLabel?.stringValue = url.path

        // Show the Reset button
        if let resetButton = window?.contentView?.viewWithTag(200) as? NSButton {
            resetButton.isHidden = false
        }

        onFolderChanged?()
    }

    @objc private func resetFolder(_ sender: NSButton) {
        preferencesStore.screenshotFolderOverride = nil
        folderLabel?.stringValue = preferencesStore.screenshotFolder.path
        sender.isHidden = true
        onFolderChanged?()
    }

    @objc private func namerTierChanged(_ sender: NSPopUpButton) {
        let tiers = ["vision-only", "foundation-models", "fastvlm"]
        let index = sender.indexOfSelectedItem
        let tier = index < tiers.count ? tiers[index] : "vision-only"
        preferencesStore.namerTier = tier
        onFolderChanged?()  // Restart pipeline to pick up the new namer
    }

    @objc private func groupByAppToggled(_ sender: NSButton) {
        preferencesStore.groupByApp = sender.state == .on
        onFolderChanged?()  // Restart pipeline to pick up the new groupByApp setting
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        preferencesStore.launchAtLogin = enabled
        if enabled {
            launchAgent.install()
        } else {
            launchAgent.uninstall()
        }
    }

    #if !MAS
    @objc private func browserCaptureToggled(_ sender: NSButton) {
        preferencesStore.browserCaptureEnabled = sender.state == .on
    }

    @objc private func hotkeyToggled(_ sender: NSButton) {
        preferencesStore.hotkeyEnabled = sender.state == .on
        onHotkeyChanged?()
    }
    #endif

    // MARK: - Availability

    /// Check if Foundation Models (Apple Intelligence) is available at runtime.
    private static func isFoundationModelsAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    // MARK: - Helpers

    private func makeLabel(
        _ text: String,
        at y: CGFloat,
        size: CGFloat = 13,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 20, y: y, width: 140, height: 20)
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        return label
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Window is reused on next open
    }
}
