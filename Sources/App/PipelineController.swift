import AppKit
import Foundation
import SmartScreenShotCore

/// Manages the screenshot rename pipeline lifecycle.
/// Wraps KeystrokeTap + ScreenshotWatcher + RenameEngine with start/stop controls.
final class PipelineController {

    enum State { case stopped, running }

    private(set) var state: State = .stopped

    private let store: CaptureContextStore
    private let namer: VisionOnlyNamer
    private let engine: RenameEngine
    private let preferencesStore: PreferencesStore
    private var watcher: ScreenshotWatcher?
    private var tap: KeystrokeTap?

    /// Most recent file detected by the watcher (original path before rename).
    private(set) var lastDetectedURL: URL?
    /// Destination path after the most recent rename.
    private(set) var lastDestinationURL: URL?

    init(preferencesStore: PreferencesStore) {
        self.preferencesStore = preferencesStore
        self.store = CaptureContextStore()
        self.namer = VisionOnlyNamer()
        self.engine = RenameEngine(namer: namer, store: store)
    }

    // MARK: - Lifecycle

    func start() {
        guard state == .stopped else { return }

        let screenshotFolder = preferencesStore.screenshotFolder
        watcher = ScreenshotWatcher(folderURL: screenshotFolder) { [weak self] url, detectedAt in
            guard let self else { return }
            self.lastDetectedURL = url
            Task {
                let dest = await self.engine.process(newFile: url, detectedAt: detectedAt)
                if let dest { self.lastDestinationURL = dest }
            }
        }
        watcher?.start()

        let keystrokeTap = KeystrokeTap(store: store)
        do {
            try keystrokeTap.start()
            self.tap = keystrokeTap
        } catch {
            print("[PipelineController] tap start failed: \(error.localizedDescription)")
        }

        state = .running
        print("[PipelineController] started")
    }

    func stop() {
        guard state == .running else { return }
        watcher?.stop()
        watcher = nil
        tap?.stop()
        tap = nil
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

    /// The screenshot folder being watched.
    var screenshotFolder: URL { preferencesStore.screenshotFolder }
}
