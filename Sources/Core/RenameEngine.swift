import CoreGraphics
import Foundation
import ImageIO

/// Orchestrates the full rename pipeline:
///   1. Match to a CaptureContext from the keystroke store (before sleeping)
///   2. Wait briefly for macOS to finish writing the file
///   3. Run VisionOnlyNamer to generate a content slug
///   4. Build {app-slug}_{YYYY-MM-DD}/{content-slug}_{HH-mm-ss}.png
///   5. Create folder if needed, move file
public actor RenameEngine {

    private let namer: any ImageNamer
    private let store: CaptureContextStore
    /// When true, folders are named after the frontmost app (e.g. `safari_2026-03-28`).
    /// When false (default), all screenshots go into `screenshot_2026-03-28`.
    private let groupByApp: Bool
    private let folderPrefix: String
    /// Paths processed in the last few seconds — prevents double-processing
    /// when FSEvents fires multiple times for the same file.
    private var recentlyProcessed: [String: Date] = [:]

    public init(namer: any ImageNamer, store: CaptureContextStore, groupByApp: Bool = false, folderPrefix: String = "screenshot") {
        self.namer = namer
        self.store = store
        self.groupByApp = groupByApp
        self.folderPrefix = folderPrefix
    }

    // MARK: - Public

    /// - Parameter detectedAt: timestamp from the FSEvents callback — use this for
    ///   context matching instead of `Date()`, which can be seconds later due to Task scheduling.
    @discardableResult
    public func process(newFile url: URL, detectedAt: Date) async -> URL? {
        let path = url.path

        // Debounce: skip if we processed this path in the last 3 seconds
        pruneRecent()
        guard recentlyProcessed[path] == nil else { return nil }
        recentlyProcessed[path] = Date()

        // Match context using the watcher's detection time — much closer to the keystroke
        // than Date() here, which can be delayed by several seconds of Task scheduling.
        let matched = store.nearest(to: detectedAt)
        let context = matched ?? .empty

        // Give macOS time to finish writing before we read the file
        try? await Task.sleep(nanoseconds: 500_000_000)   // 0.5 s

        guard FileManager.default.fileExists(atPath: path) else {
            print("[RenameEngine] file vanished before processing: \(url.lastPathComponent)")
            return nil
        }

        guard let image = loadCGImage(from: url) else {
            print("[RenameEngine] could not load image: \(url.lastPathComponent)")
            return nil
        }

        // Generate content slug via the active namer tier
        let contentSlug: String
        do {
            contentSlug = try await namer.name(image: image, context: context)
        } catch {
            print("[RenameEngine] naming failed — \(error.localizedDescription)")
            return nil
        }

        // Use context capturedAt for accurate timestamps; fall back to file creation date
        let fileDate = context.appName.isEmpty
                       ? creationDate(of: url)
                       : context.capturedAt

        // Build destination
        let appSlug    = (groupByApp && !context.appName.isEmpty)
                         ? SlugGenerator.slug(from: context.appName)
                         : folderPrefix
        let folderName = "\(appSlug)_\(dateString(from: fileDate))"
        let baseName   = "\(contentSlug)_\(timeString(from: fileDate))"

        let baseDir    = url.deletingLastPathComponent()
        let destFolder = baseDir.appendingPathComponent(folderName)
        var destFile   = destFolder.appendingPathComponent("\(baseName).png")

        // Avoid collisions (same app + same second + same slug)
        var counter = 1
        while FileManager.default.fileExists(atPath: destFile.path) {
            destFile = destFolder.appendingPathComponent("\(baseName)_\(counter).png")
            counter += 1
        }

        // Create folder and move
        do {
            try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: destFile)
            print("[RenameEngine] \(url.lastPathComponent)")
            print("           → \(folderName)/\(destFile.lastPathComponent)")
            return destFile
        } catch {
            print("[RenameEngine] move failed — \(error.localizedDescription)")
            return nil
        }
    }

    /// Manually rename a file that already exists on disk.
    /// Skips write-settle delay, debounce, and context lookup — always uses `.empty` context.
    /// Designed for batch rename (Finder Quick Action, CLI --rename, menu bar batch).
    @discardableResult
    public func processManual(file url: URL) async -> URL? {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            print("[RenameEngine] file not found: \(url.lastPathComponent)")
            return nil
        }

        guard let image = loadCGImage(from: url) else {
            print("[RenameEngine] could not load image: \(url.lastPathComponent)")
            return nil
        }

        let contentSlug: String
        do {
            contentSlug = try await namer.name(image: image, context: .empty)
        } catch {
            print("[RenameEngine] naming failed — \(error.localizedDescription)")
            return nil
        }

        let fileDate = creationDate(of: url)
        let folderName = "\(folderPrefix)_\(dateString(from: fileDate))"
        let baseName   = "\(contentSlug)_\(timeString(from: fileDate))"

        let baseDir    = url.deletingLastPathComponent()
        let destFolder = baseDir.appendingPathComponent(folderName)
        var destFile   = destFolder.appendingPathComponent("\(baseName).png")

        var counter = 1
        while FileManager.default.fileExists(atPath: destFile.path) {
            destFile = destFolder.appendingPathComponent("\(baseName)_\(counter).png")
            counter += 1
        }

        do {
            try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: destFile)
            print("[RenameEngine] \(url.lastPathComponent)")
            print("           → \(folderName)/\(destFile.lastPathComponent)")
            return destFile
        } catch {
            print("[RenameEngine] move failed — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    private func pruneRecent() {
        let cutoff = Date().addingTimeInterval(-3)
        recentlyProcessed = recentlyProcessed.filter { $0.value > cutoff }
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image  = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return image
    }

    private func creationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    private func dateString(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private func timeString(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d-%02d-%02d", c.hour!, c.minute!, c.second!)
    }
}
