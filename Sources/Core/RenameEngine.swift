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
    /// Paths processed in the last few seconds — prevents double-processing
    /// when FSEvents fires multiple times for the same file.
    private var recentlyProcessed: [String: Date] = [:]

    public init(namer: any ImageNamer, store: CaptureContextStore) {
        self.namer = namer
        self.store = store
    }

    // MARK: - Public

    public func process(newFile url: URL) async {
        let path = url.path

        // Debounce: skip if we processed this path in the last 3 seconds
        pruneRecent()
        guard recentlyProcessed[path] == nil else { return }
        recentlyProcessed[path] = Date()

        // Match context NOW — before sleeping — so the 5 s match window isn't
        // eaten up by our write-settle delay. store.nearest() is synchronous (lock-based).
        let eventTime = Date()
        let context   = store.nearest(to: eventTime) ?? .empty

        // Give macOS time to finish writing before we read the file
        try? await Task.sleep(nanoseconds: 500_000_000)   // 0.5 s

        guard FileManager.default.fileExists(atPath: path) else {
            print("[RenameEngine] file vanished before processing: \(url.lastPathComponent)")
            return
        }

        guard let image = loadCGImage(from: url) else {
            print("[RenameEngine] could not load image: \(url.lastPathComponent)")
            return
        }

        // Generate content slug via the active namer tier
        let contentSlug: String
        do {
            contentSlug = try await namer.name(image: image, context: context)
        } catch {
            print("[RenameEngine] naming failed — \(error.localizedDescription)")
            return
        }

        // Use context capturedAt for accurate timestamps; fall back to file creation date
        let fileDate = context.appName.isEmpty
                       ? creationDate(of: url)
                       : context.capturedAt

        // Build destination
        let appSlug    = context.appName.isEmpty
                         ? "screenshot"
                         : SlugGenerator.slug(from: context.appName)
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
        } catch {
            print("[RenameEngine] move failed — \(error.localizedDescription)")
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
