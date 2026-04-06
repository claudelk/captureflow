import AppKit
import SmartScreenShotCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Programmatic preferences window — no storyboard, no NIB.
final class PreferencesWindow: NSObject, NSWindowDelegate, NSTextFieldDelegate {

    private var window: NSWindow?
    private let preferencesStore: PreferencesStore
    private let launchAgent = LaunchAtLogin()
    private var folderLabel: NSTextField?
    private var customPrefixField: NSTextField?
    /// Called when the screenshot folder changes so the pipeline can restart.
    var onFolderChanged: (() -> Void)?
    #if !MAS
    /// Called when the hotkey enabled state changes so the pipeline can restart the monitor.
    var onHotkeyChanged: (() -> Void)?
    #endif

    private static let supportEmail = "support@atalaku.studio"

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
        let windowHeight: CGFloat = 630
        #else
        let windowHeight: CGFloat = 710
        #endif

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = L10n.string("prefs.title")
        w.center()
        w.delegate = self
        w.isReleasedWhenClosed = false

        let content = NSView(frame: w.contentView!.bounds)
        content.autoresizingMask = [.width, .height]

        #if MAS
        var y: CGFloat = 585
        #else
        var y: CGFloat = 665
        #endif

        // --- Screenshot Folder ---
        content.addSubview(makeLabel(L10n.string("prefs.saveScreenshotsTo"), at: y))

        let folderPath = NSTextField(labelWithString: preferencesStore.screenshotFolder.path)
        folderPath.frame = NSRect(x: 160, y: y, width: 200, height: 20)
        folderPath.font = .systemFont(ofSize: 11)
        folderPath.textColor = .secondaryLabelColor
        folderPath.lineBreakMode = .byTruncatingMiddle
        self.folderLabel = folderPath
        content.addSubview(folderPath)

        let chooseButton = NSButton(title: L10n.string("prefs.choose"), target: self, action: #selector(chooseFolder(_:)))
        chooseButton.bezelStyle = .rounded
        chooseButton.frame = NSRect(x: 365, y: y - 4, width: 75, height: 28)
        content.addSubview(chooseButton)

        let resetButton = NSButton(title: L10n.string("prefs.reset"), target: self, action: #selector(resetFolder(_:)))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 365, y: y - 30, width: 75, height: 24)
        resetButton.font = .systemFont(ofSize: 11)
        resetButton.isHidden = preferencesStore.screenshotFolderOverride == nil
        resetButton.tag = 200
        content.addSubview(resetButton)

        y -= 65

        // --- Naming Mode ---
        content.addSubview(makeLabel(L10n.string("prefs.namingMode"), at: y))

        let tierPopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 230, height: 26), pullsDown: false)
        tierPopup.addItems(withTitles: [L10n.string("prefs.standard")])
        tierPopup.target = self
        tierPopup.action = #selector(namerTierChanged(_:))

        let tier2Available = Self.isFoundationModelsAvailable()
        let tier2Title = tier2Available
            ? L10n.string("prefs.enhanced")
            : L10n.string("prefs.enhancedUnavailable")
        let tier2 = NSMenuItem(title: tier2Title, action: nil, keyEquivalent: "")
        tier2.isEnabled = tier2Available
        tierPopup.menu?.addItem(tier2)

        let tier3 = NSMenuItem(title: L10n.string("prefs.advanced"), action: nil, keyEquivalent: "")
        tier3.isEnabled = false
        tierPopup.menu?.addItem(tier3)

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
            checkboxWithTitle: L10n.string("prefs.groupByApp"),
            target: self,
            action: #selector(groupByAppToggled(_:))
        )
        groupByAppCheckbox.frame.origin = NSPoint(x: 20, y: y)
        groupByAppCheckbox.state = preferencesStore.groupByApp ? .on : .off
        content.addSubview(groupByAppCheckbox)

        y -= 30

        // --- Separate Photos/Videos ---
        let separateCheckbox = NSButton(
            checkboxWithTitle: L10n.string("prefs.separatePhotoVideo"),
            target: self,
            action: #selector(separatePhotoVideoToggled(_:))
        )
        separateCheckbox.frame.origin = NSPoint(x: 20, y: y)
        separateCheckbox.state = preferencesStore.separatePhotoVideo ? .on : .off
        content.addSubview(separateCheckbox)

        y -= 35

        // --- Photo Format ---
        content.addSubview(makeLabel(L10n.string("prefs.photoFormat"), at: y))

        let photoPopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 180, height: 26), pullsDown: false)
        photoPopup.addItems(withTitles: [L10n.string("prefs.formatPNG"), L10n.string("prefs.formatJPEG")])
        photoPopup.target = self
        photoPopup.action = #selector(photoFormatChanged(_:))
        photoPopup.selectItem(at: preferencesStore.photoFormat == "jpeg" ? 1 : 0)
        photoPopup.toolTip = L10n.string("prefs.tooltipJPEG")
        content.addSubview(photoPopup)

        y -= 32

        // --- Video Format ---
        content.addSubview(makeLabel(L10n.string("prefs.videoFormat"), at: y))

        let videoPopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 180, height: 26), pullsDown: false)
        videoPopup.addItems(withTitles: [L10n.string("prefs.formatMOV"), L10n.string("prefs.formatMP4")])
        videoPopup.target = self
        videoPopup.action = #selector(videoFormatChanged(_:))
        videoPopup.selectItem(at: preferencesStore.videoFormat == "mp4" ? 1 : 0)
        videoPopup.toolTip = L10n.string("prefs.tooltipMP4")
        content.addSubview(videoPopup)

        y -= 40

        // --- Launch at Login ---
        let launchCheckbox = NSButton(
            checkboxWithTitle: L10n.string("prefs.launchAtLogin"),
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
            checkboxWithTitle: L10n.string("prefs.browserCapture"),
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
            checkboxWithTitle: L10n.string("prefs.globalHotkey"),
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

        y -= 45

        // --- Folder Prefix ---
        content.addSubview(makeLabel(L10n.string("prefs.folderPrefix"), at: y))

        let langCode = L10n.activeLanguageCode
        let defaultPrefix = FolderPrefix.prefix(for: langCode)

        let defaultRadio = NSButton(radioButtonWithTitle: "\(L10n.string("prefs.folderPrefixDefault")) (\(defaultPrefix)_YYYY-MM-DD)",
                                     target: self, action: #selector(folderPrefixChanged(_:)))
        defaultRadio.frame.origin = NSPoint(x: 160, y: y)
        defaultRadio.tag = 400
        defaultRadio.state = preferencesStore.useCustomFolderPrefix ? .off : .on
        content.addSubview(defaultRadio)

        y -= 25

        let customRadio = NSButton(radioButtonWithTitle: L10n.string("prefs.folderPrefixCustom"),
                                    target: self, action: #selector(folderPrefixChanged(_:)))
        customRadio.frame.origin = NSPoint(x: 160, y: y)
        customRadio.tag = 401
        customRadio.state = preferencesStore.useCustomFolderPrefix ? .on : .off
        content.addSubview(customRadio)

        let prefixField = NSTextField(frame: NSRect(x: 260, y: y - 2, width: 100, height: 22))
        prefixField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        prefixField.stringValue = preferencesStore.customFolderPrefix
        prefixField.placeholderString = "my-prefix"
        prefixField.isEnabled = preferencesStore.useCustomFolderPrefix
        prefixField.delegate = self
        prefixField.tag = 402
        self.customPrefixField = prefixField
        content.addSubview(prefixField)

        let suffixLabel = makeLabel("_YYYY-MM-DD", at: y, size: 11, color: .secondaryLabelColor)
        suffixLabel.frame.origin.x = 365
        suffixLabel.frame.size.width = 90
        content.addSubview(suffixLabel)

        y -= 40

        // --- Language ---
        content.addSubview(makeLabel(L10n.string("prefs.language"), at: y))

        let languageNames = ["System Default", "English", "Fran\u{00E7}ais", "Espa\u{00F1}ol", "Portugu\u{00EA}s", "Kiswahili"]
        let languageCodes = ["system", "en", "fr", "es", "pt", "sw"]

        let langPopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 200, height: 26), pullsDown: false)
        langPopup.addItems(withTitles: languageNames)
        langPopup.target = self
        langPopup.action = #selector(languageChanged(_:))

        let currentLang = preferencesStore.appLanguage
        if let idx = languageCodes.firstIndex(of: currentLang) {
            langPopup.selectItem(at: idx)
        } else {
            langPopup.selectItem(at: 0)
        }
        content.addSubview(langPopup)

        // --- Support & Feedback ---
        // Separator line
        let separator = NSBox()
        separator.boxType = .separator
        separator.frame = NSRect(x: 20, y: 75, width: 420, height: 1)
        content.addSubview(separator)

        let feedbackTitle = makeLabel("Support & Feedback", at: 55, size: 12, color: .labelColor)
        feedbackTitle.frame = NSRect(x: 20, y: 55, width: 420, height: 16)
        content.addSubview(feedbackTitle)

        let emailLabel = NSTextField(labelWithString: Self.supportEmail)
        emailLabel.frame = NSRect(x: 20, y: 35, width: 220, height: 16)
        emailLabel.font = .systemFont(ofSize: 11)
        emailLabel.textColor = .secondaryLabelColor
        emailLabel.isSelectable = true
        content.addSubview(emailLabel)

        let copyButton = NSButton(title: L10n.string("prefs.copyEmail"), target: self, action: #selector(copyEmail(_:)))
        copyButton.bezelStyle = .rounded
        copyButton.font = .systemFont(ofSize: 11)
        copyButton.frame = NSRect(x: 250, y: 32, width: 95, height: 24)
        copyButton.tag = 500
        content.addSubview(copyButton)

        let sendButton = NSButton(title: L10n.string("prefs.sendEmail"), target: self, action: #selector(sendEmail(_:)))
        sendButton.bezelStyle = .rounded
        sendButton.font = .systemFont(ofSize: 11)
        sendButton.frame = NSRect(x: 350, y: 32, width: 95, height: 24)
        content.addSubview(sendButton)

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
        panel.prompt = L10n.string("prefs.select")
        panel.message = L10n.string("prefs.chooseMessage")
        panel.directoryURL = preferencesStore.screenshotFolder

        guard panel.runModal() == .OK, let url = panel.url else { return }

        preferencesStore.screenshotFolderOverride = url.path
        #if MAS
        preferencesStore.saveBookmark(for: url)
        #endif
        folderLabel?.stringValue = url.path

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
        onFolderChanged?()
    }

    @objc private func groupByAppToggled(_ sender: NSButton) {
        preferencesStore.groupByApp = sender.state == .on
        onFolderChanged?()
    }

    @objc private func separatePhotoVideoToggled(_ sender: NSButton) {
        preferencesStore.separatePhotoVideo = sender.state == .on
        onFolderChanged?()
    }

    @objc private func photoFormatChanged(_ sender: NSPopUpButton) {
        preferencesStore.photoFormat = sender.indexOfSelectedItem == 1 ? "jpeg" : "png"
        onFolderChanged?()
    }

    @objc private func videoFormatChanged(_ sender: NSPopUpButton) {
        preferencesStore.videoFormat = sender.indexOfSelectedItem == 1 ? "mp4" : "mov"
        onFolderChanged?()
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let codes = ["system", "en", "fr", "es", "pt", "sw"]
        let index = sender.indexOfSelectedItem
        let code = index < codes.count ? codes[index] : "system"
        preferencesStore.appLanguage = code

        let alert = NSAlert()
        alert.messageText = L10n.string("alert.restartTitle")
        alert.informativeText = L10n.string("alert.restartBody")
        alert.addButton(withTitle: L10n.string("alert.restartNow"))
        alert.addButton(withTitle: L10n.string("alert.restartLater"))
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            let url = Bundle.main.bundleURL
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [url.path]
            try? task.run()
            NSApplication.shared.terminate(nil)
        }
    }

    @objc private func folderPrefixChanged(_ sender: NSButton) {
        let useCustom = sender.tag == 401
        preferencesStore.useCustomFolderPrefix = useCustom
        customPrefixField?.isEnabled = useCustom

        if let defaultRadio = window?.contentView?.viewWithTag(400) as? NSButton {
            defaultRadio.state = useCustom ? .off : .on
        }
        if let customRadio = window?.contentView?.viewWithTag(401) as? NSButton {
            customRadio.state = useCustom ? .on : .off
        }

        onFolderChanged?()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field.tag == 402 else { return }
        preferencesStore.customFolderPrefix = field.stringValue
        onFolderChanged?()  // Restart pipeline to use new prefix
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

    @objc private func copyEmail(_ sender: NSButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.supportEmail, forType: .string)
        sender.title = L10n.string("prefs.copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            sender.title = L10n.string("prefs.copyEmail")
        }
    }

    @objc private func sendEmail(_ sender: NSButton) {
        if let url = URL(string: "mailto:\(Self.supportEmail)?subject=SmartScreenShot%20Feedback") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Availability

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
