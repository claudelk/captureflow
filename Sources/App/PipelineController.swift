import AppKit
import Foundation
import SmartScreenShotCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Manages the screenshot rename pipeline lifecycle.
/// Wraps KeystrokeTap + ScreenshotWatcher + RenameEngine with start/stop controls.
final class PipelineController {

    enum State { case stopped, running }

    private(set) var state: State = .stopped

    private let store: CaptureContextStore
    private let namer: any ImageNamer
    private let engine: RenameEngine
    private let preferencesStore: PreferencesStore
    private var watcher: ScreenshotWatcher?
    #if !MAS
    private var tap: KeystrokeTap?
    private var hotkeyMonitor: GlobalHotkeyMonitor?
    #endif

    /// Most recent file detected by the watcher (original path before rename).
    private(set) var lastDetectedURL: URL?
    /// Destination path after the most recent rename.
    private(set) var lastDestinationURL: URL?
    /// Called on the main thread after a successful rename (for UI feedback).
    var onRenameCompleted: (() -> Void)?

    init(preferencesStore: PreferencesStore) {
        self.preferencesStore = preferencesStore
        self.store = CaptureContextStore()
        self.namer = Self.createNamer(tier: preferencesStore.namerTier)
        self.engine = RenameEngine(namer: namer, store: store, groupByApp: preferencesStore.groupByApp)
    }

    /// Factory: creates the best available namer.
    /// "auto" (default): picks the best available tier.
    /// "vision-only": forces Standard (Tier 1).
    /// "foundation-models": forces Enhanced (Tier 2), falls back if unavailable.
    static func createNamer(tier: String) -> any ImageNamer {
        let wantsLLM = (tier == "auto" || tier == "foundation-models")
        #if canImport(FoundationModels)
        if wantsLLM, #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            return FoundationModelsNamer()
        }
        #endif
        return VisionOnlyNamer()
    }

    // MARK: - Lifecycle

    func start() {
        guard state == .stopped else { return }

        let screenshotFolder = preferencesStore.screenshotFolder

        #if MAS
        // Resolve security-scoped bookmark for sandbox folder access
        if let bookmarkedURL = preferencesStore.resolveBookmarkedFolder() {
            _ = bookmarkedURL.startAccessingSecurityScopedResource()
        }
        #endif

        watcher = ScreenshotWatcher(folderURL: screenshotFolder) { [weak self] url, detectedAt in
            guard let self else { return }
            self.lastDetectedURL = url

            #if MAS
            // Sandbox fallback: capture frontmost app when FSEvents fires.
            // Runs ~0.3-1s after keystroke — frontmost app is usually still correct.
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                let ctx = CaptureContext(
                    appName: frontApp.localizedName ?? "screenshot",
                    appBundleID: frontApp.bundleIdentifier ?? "",
                    browserURL: nil,
                    capturedAt: detectedAt
                )
                self.store.store(ctx)
            }
            #endif

            Task {
                let dest = await self.engine.process(newFile: url, detectedAt: detectedAt)
                if let dest {
                    self.lastDestinationURL = dest
                    DispatchQueue.main.async { self.onRenameCompleted?() }
                }
            }
        }
        watcher?.start()

        #if !MAS
        let keystrokeTap = KeystrokeTap(store: store)
        do {
            try keystrokeTap.start()
            self.tap = keystrokeTap
        } catch {
            print("[PipelineController] tap start failed: \(error.localizedDescription)")
        }

        startHotkeyMonitor()
        #endif

        state = .running
        print("[PipelineController] started")
    }

    func stop() {
        guard state == .running else { return }
        watcher?.stop()
        watcher = nil
        #if !MAS
        tap?.stop()
        tap = nil
        hotkeyMonitor?.stop()
        hotkeyMonitor = nil
        #endif
        state = .stopped
        print("[PipelineController] stopped")
    }

    // MARK: - Actions

    /// Re-run the namer on the most recently renamed file.
    func reanalyzeLast() {
        guard let url = lastDestinationURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        Task {
            let dest = await engine.process(newFile: url, detectedAt: Date())
            if let dest { lastDestinationURL = dest }
        }
    }

    #if !MAS
    /// Restart the global hotkey monitor (e.g. after preferences change).
    func restartHotkeyMonitor() {
        hotkeyMonitor?.stop()
        hotkeyMonitor = nil
        if state == .running {
            startHotkeyMonitor()
        }
    }
    #endif

    /// The screenshot folder being watched.
    var screenshotFolder: URL { preferencesStore.screenshotFolder }

    // MARK: - Private

    #if !MAS
    private func startHotkeyMonitor() {
        let monitor = GlobalHotkeyMonitor(
            preferencesStore: preferencesStore,
            engine: engine,
            screenshotFolder: { [weak self] in
                self?.preferencesStore.screenshotFolder ?? URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
            }
        )
        monitor.start()
        self.hotkeyMonitor = monitor
    }
    #endif
}
