import AppKit
import CaptureFlowCore
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
        let windowHeight: CGFloat = 720
        #else
        let windowHeight: CGFloat = 845
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
        var y: CGFloat = 675
        #else
        var y: CGFloat = 800
        #endif

        // --- Screenshot Folder ---
        content.addSubview(makeLabel(L10n.string("prefs.saveScreenshotsTo"), at: y))

        let folderPath = NSTextField(labelWithString: preferencesStore.screenshotFolder.path)
        folderPath.frame = NSRect(x: 160, y: y, width: 200, height: 20)
        folderPath.font = .systemFont(ofSize: 11)
        folderPath.textColor = .secondaryLabelColor
        folderPath.lineBreakMode = .byTruncatingMiddle
        folderPath.setAccessibilityLabel(L10n.string("prefs.saveScreenshotsTo"))
        self.folderLabel = folderPath
        content.addSubview(folderPath)

        let chooseButton = NSButton(title: L10n.string("prefs.choose"), target: self, action: #selector(chooseFolder(_:)))
        chooseButton.bezelStyle = .rounded
        chooseButton.frame = NSRect(x: 365, y: y - 4, width: 75, height: 28)
        chooseButton.setAccessibilityLabel(L10n.string("prefs.choose"))
        content.addSubview(chooseButton)

        let resetButton = NSButton(title: L10n.string("prefs.reset"), target: self, action: #selector(resetFolder(_:)))
        resetButton.bezelStyle = .rounded
        resetButton.frame = NSRect(x: 365, y: y - 30, width: 75, height: 24)
        resetButton.font = .systemFont(ofSize: 11)
        resetButton.isHidden = preferencesStore.screenshotFolderOverride == nil
        resetButton.tag = 200
        resetButton.setAccessibilityLabel(L10n.string("prefs.reset"))
        content.addSubview(resetButton)

        y -= 65

        // --- Naming Mode ---
        content.addSubview(makeLabel(L10n.string("prefs.namingMode"), at: y))

        let tierPopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 230, height: 26), pullsDown: false)
        tierPopup.addItems(withTitles: [L10n.string("prefs.standard")])
        tierPopup.target = self
        tierPopup.action = #selector(namerTierChanged(_:))
        tierPopup.setAccessibilityLabel(L10n.string("prefs.namingMode"))

        let tier2Available = Self.isFoundationModelsAvailable()
        let tier2Title = tier2Available
            ? L10n.string("prefs.enhanced")
            : L10n.string("prefs.enhancedUnavailable")
        let tier2 = NSMenuItem(title: tier2Title, action: nil, keyEquivalent: "")
        tier2.isEnabled = tier2Available
        tierPopup.menu?.addItem(tier2)

        let tier3 = NSMenuItem(title: L10n.string("prefs.advanced"), action: nil, keyEquivalent: "")
        tier3.isEnabled = false
        tier3.attributedTitle = NSAttributedString(
            string: L10n.string("prefs.advanced"),
            attributes: [.foregroundColor: NSColor.tertiaryLabelColor]
        )
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
        photoPopup.setAccessibilityLabel(L10n.string("prefs.photoFormat"))
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
        videoPopup.setAccessibilityLabel(L10n.string("prefs.videoFormat"))
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

        // --- Root Folder ---
        content.addSubview(makeLabel(L10n.string("prefs.rootFolder"), at: y))

        let langCode = L10n.activeLanguageCode
        let defaultRootName = FolderPrefix.rootFolderName(for: langCode)

        let rootDefaultRadio = NSButton(radioButtonWithTitle: "\(L10n.string("prefs.rootFolderDefault")) (\(defaultRootName))",
                                         target: self, action: #selector(rootFolderChanged(_:)))
        rootDefaultRadio.frame.origin = NSPoint(x: 160, y: y)
        rootDefaultRadio.tag = 400
        rootDefaultRadio.state = preferencesStore.useCustomRootFolder ? .off : .on
        content.addSubview(rootDefaultRadio)

        y -= 25

        let rootCustomRadio = NSButton(radioButtonWithTitle: L10n.string("prefs.rootFolderCustom"),
                                        target: self, action: #selector(rootFolderChanged(_:)))
        rootCustomRadio.frame.origin = NSPoint(x: 160, y: y)
        rootCustomRadio.tag = 401
        rootCustomRadio.state = preferencesStore.useCustomRootFolder ? .on : .off
        content.addSubview(rootCustomRadio)

        let rootField = NSTextField(frame: NSRect(x: 280, y: y - 2, width: 120, height: 22))
        rootField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        rootField.stringValue = preferencesStore.customRootFolderName
        rootField.placeholderString = defaultRootName
        rootField.isEnabled = preferencesStore.useCustomRootFolder
        rootField.delegate = self
        rootField.tag = 402
        rootField.setAccessibilityLabel(L10n.string("prefs.rootFolderCustom"))
        self.customPrefixField = rootField
        content.addSubview(rootField)

        y -= 35

        // --- Date Format ---
        content.addSubview(makeLabel(L10n.string("prefs.dateFormat"), at: y))

        let sampleFormatter = DateFormatter()
        sampleFormatter.dateStyle = .short
        sampleFormatter.timeStyle = .none
        let sampleDate = sampleFormatter.string(from: Date())

        let dateDefaultRadio = NSButton(radioButtonWithTitle: "\(L10n.string("prefs.dateFormatDefault")) (\(sampleDate))",
                                         target: self, action: #selector(dateFormatChanged(_:)))
        dateDefaultRadio.frame.origin = NSPoint(x: 160, y: y)
        dateDefaultRadio.tag = 410
        dateDefaultRadio.state = preferencesStore.useCustomDateFormat ? .off : .on
        content.addSubview(dateDefaultRadio)

        y -= 25

        let dateCustomRadio = NSButton(radioButtonWithTitle: L10n.string("prefs.dateFormatCustom"),
                                        target: self, action: #selector(dateFormatChanged(_:)))
        dateCustomRadio.frame.origin = NSPoint(x: 160, y: y)
        dateCustomRadio.tag = 411
        dateCustomRadio.state = preferencesStore.useCustomDateFormat ? .on : .off
        content.addSubview(dateCustomRadio)

        let dateField = NSTextField(frame: NSRect(x: 280, y: y - 2, width: 120, height: 22))
        dateField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        dateField.stringValue = preferencesStore.customDateFormat
        dateField.placeholderString = "yyyy-MM-dd"
        dateField.isEnabled = preferencesStore.useCustomDateFormat
        dateField.delegate = self
        dateField.tag = 412
        dateField.setAccessibilityLabel(L10n.string("prefs.dateFormatCustom"))
        content.addSubview(dateField)

        y -= 35

        // --- Preview ---
        let previewFormatter: DateFormatter = {
            let df = DateFormatter()
            if preferencesStore.useCustomDateFormat, !preferencesStore.customDateFormat.isEmpty {
                df.dateFormat = preferencesStore.customDateFormat
            } else {
                df.dateStyle = .short
                df.timeStyle = .none
            }
            return df
        }()
        let previewDate = previewFormatter.string(from: Date())
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let rootName = preferencesStore.useCustomRootFolder && !preferencesStore.customRootFolderName.isEmpty
            ? preferencesStore.customRootFolderName
            : defaultRootName
        let imagesName = FolderPrefix.imagesFolderName(for: langCode)
        let previewText = "\(rootName) / \(previewDate) / \(imagesName) /"
        let previewLabel = makeLabel(previewText, at: y, size: 11, color: .secondaryLabelColor)
        previewLabel.frame = NSRect(x: 20, y: y, width: 420, height: 16)
        previewLabel.tag = 420
        content.addSubview(previewLabel)

        y -= 30

        // --- Language ---
        content.addSubview(makeLabel(L10n.string("prefs.language"), at: y))

        let languageNames = ["System Default", "English", "Fran\u{00E7}ais", "Espa\u{00F1}ol", "Portugu\u{00EA}s", "Kiswahili"]
        let languageCodes = ["system", "en", "fr", "es", "pt", "sw"]

        let langPopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 200, height: 26), pullsDown: false)
        langPopup.addItems(withTitles: languageNames)
        langPopup.target = self
        langPopup.action = #selector(languageChanged(_:))
        langPopup.setAccessibilityLabel(L10n.string("prefs.language"))

        let currentLang = preferencesStore.appLanguage
        if let idx = languageCodes.firstIndex(of: currentLang) {
            langPopup.selectItem(at: idx)
        } else {
            langPopup.selectItem(at: 0)
        }
        content.addSubview(langPopup)

        #if !MAS
        y -= 40

        // --- Permissions ---
        content.addSubview(makeLabel(L10n.string("prefs.permissions"), at: y))

        let accessStatus = AXIsProcessTrusted() ? "\u{2705}" : "\u{274C}"
        let accessButton = NSButton(
            title: "\(accessStatus) \(L10n.string("prefs.grantAccessibility"))",
            target: self, action: #selector(openAccessibilitySettings(_:))
        )
        accessButton.bezelStyle = .rounded
        accessButton.frame = NSRect(x: 160, y: y - 4, width: 260, height: 28)
        accessButton.setAccessibilityLabel(L10n.string("prefs.grantAccessibility"))
        content.addSubview(accessButton)

        #endif

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
            "CaptureFlow v\(version)",
            at: 15,
            size: 11,
            color: .tertiaryLabelColor
        )
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 0, y: 10, width: 460, height: 16)
        content.addSubview(versionLabel)

        // --- Keyboard navigation (Tab order) ---
        w.initialFirstResponder = chooseButton
        chooseButton.nextKeyView = tierPopup
        tierPopup.nextKeyView = groupByAppCheckbox
        groupByAppCheckbox.nextKeyView = separateCheckbox
        separateCheckbox.nextKeyView = photoPopup
        photoPopup.nextKeyView = videoPopup
        videoPopup.nextKeyView = launchCheckbox
        #if !MAS
        launchCheckbox.nextKeyView = browserCheckbox
        browserCheckbox.nextKeyView = hotkeyCheckbox
        hotkeyCheckbox.nextKeyView = rootDefaultRadio
        #else
        launchCheckbox.nextKeyView = rootDefaultRadio
        #endif
        rootDefaultRadio.nextKeyView = rootCustomRadio
        rootCustomRadio.nextKeyView = rootField
        rootField.nextKeyView = dateDefaultRadio
        dateDefaultRadio.nextKeyView = dateCustomRadio
        dateCustomRadio.nextKeyView = dateField
        dateField.nextKeyView = langPopup
        langPopup.nextKeyView = copyButton
        copyButton.nextKeyView = sendButton
        sendButton.nextKeyView = chooseButton

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

    #if !MAS
    @objc private func openAccessibilitySettings(_ sender: NSButton) {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    #endif

    @objc private func rootFolderChanged(_ sender: NSButton) {
        let useCustom = sender.tag == 401
        preferencesStore.useCustomRootFolder = useCustom
        customPrefixField?.isEnabled = useCustom

        if let defaultRadio = window?.contentView?.viewWithTag(400) as? NSButton {
            defaultRadio.state = useCustom ? .off : .on
        }
        if let customRadio = window?.contentView?.viewWithTag(401) as? NSButton {
            customRadio.state = useCustom ? .on : .off
        }

        onFolderChanged?()
    }

    @objc private func dateFormatChanged(_ sender: NSButton) {
        let useCustom = sender.tag == 411
        preferencesStore.useCustomDateFormat = useCustom

        if let dateField = window?.contentView?.viewWithTag(412) as? NSTextField {
            dateField.isEnabled = useCustom
        }
        if let defaultRadio = window?.contentView?.viewWithTag(410) as? NSButton {
            defaultRadio.state = useCustom ? .off : .on
        }
        if let customRadio = window?.contentView?.viewWithTag(411) as? NSButton {
            customRadio.state = useCustom ? .on : .off
        }

        onFolderChanged?()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        switch field.tag {
        case 402:
            preferencesStore.customRootFolderName = field.stringValue
            onFolderChanged?()
        case 412:
            preferencesStore.customDateFormat = field.stringValue
            onFolderChanged?()
        default:
            break
        }
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
        if let url = URL(string: "mailto:\(Self.supportEmail)?subject=CaptureFlow%20Feedback") {
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
