import CoreServices
import Foundation

/// Watches the screenshot destination folder for newly created PNG files using FSEvents.
/// Only fires for direct children of the watched folder (not subfolders), so renamed/moved
/// files that land in app-slug subfolders are ignored automatically.
public final class ScreenshotWatcher {

    private var stream: FSEventStreamRef?
    private let folderURL: URL
    private let onNewFile: (URL, Date) -> Void

    /// - Parameter onNewFile: Called with (fileURL, detectionTime) when a new PNG appears.
    ///   `detectionTime` is captured in the FSEvents callback — much closer to the actual
    ///   keystroke than when the downstream Task eventually runs.
    public init(folderURL: URL, onNewFile: @escaping (URL, Date) -> Void) {
        self.folderURL = folderURL.standardizedFileURL
        self.onNewFile = onNewFile
    }

    deinit { stop() }

    // MARK: - Public

    public func start() {
        let paths = [folderURL.path] as CFArray
        var ctx   = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let createFlags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, numEvents, eventPaths, eventFlags, _ in
                guard let info else { return }
                let watcher   = Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()
                let pathArray = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]

                for i in 0..<numEvents {
                    let flags  = eventFlags[i]
                    let path   = pathArray[i]

                    // macOS writes screenshots as hidden temp files first (e.g. ".Screenshot …")
                    // then renames to the final name (removing the "." prefix).
                    // We catch the rename event for the final, non-hidden file.
                    let created = flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
                    let renamed = flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
                    let isFile  = flags & UInt32(kFSEventStreamEventFlagItemIsFile)  != 0
                    let isPNG   = path.lowercased().hasSuffix(".png")
                    guard (created || renamed) && isFile && isPNG else { continue }

                    let url      = URL(fileURLWithPath: path)
                    let fileName = url.lastPathComponent

                    // Skip hidden temp files (macOS prefixes with ".")
                    guard !fileName.hasPrefix(".") else { continue }

                    // Only process direct children — not files inside app-slug subfolders
                    let parent = url.deletingLastPathComponent().standardizedFileURL
                    guard parent == watcher.folderURL else { continue }

                    let detectedAt = Date()
                    print("[ScreenshotWatcher] new screenshot detected: \(fileName)")
                    watcher.onNewFile(url, detectedAt)
                }
            },
            &ctx,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,          // coalesce latency (seconds)
            createFlags
        ) else {
            print("[ScreenshotWatcher] failed to create FSEvent stream for: \(folderURL.path)")
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        print("[ScreenshotWatcher] watching: \(folderURL.path)")
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
