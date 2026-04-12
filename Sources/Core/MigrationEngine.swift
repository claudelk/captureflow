import CoreGraphics
import Foundation
import ImageIO

/// Scans for existing Apple-default-named screenshots and legacy CaptureFlow folders,
/// then organizes them into the new root folder structure.
public final class MigrationEngine {

    /// Result of scanning a folder for migratable items.
    public struct ScanResult {
        public let files: [URL]
        public let folders: [URL]
        public var fileCount: Int { files.count }
        public var folderCount: Int { folders.count }
        public var isEmpty: Bool { files.isEmpty && folders.isEmpty }
    }

    // Apple screenshot filename patterns per locale
    // EN: "Screenshot 2026-04-07 at 1.30.45 PM.png"
    // FR: "Capture d'écran 2026-04-07 à 13.30.45.png"
    // ES: "Captura de pantalla 2026-04-07 a las 13.30.45.png"
    // PT: "Captura de Tela 2026-04-07 às 13.30.45.png"
    // EN video: "Screen Recording 2026-04-07 at 1.30.45 PM.mov"
    // FR video: "Enregistrement de l'écran 2026-04-07 à 13.30.45.mov"
    private static let screenshotPrefixes = [
        "Screenshot ",
        "Capture d\u{2019}\u{00E9}cran ",
        "Capture d'écran ",
        "Captura de pantalla ",
        "Captura de Tela ",
        "Captura de tela ",
    ]

    private static let recordingPrefixes = [
        "Screen Recording ",
        "Enregistrement de l\u{2019}\u{00E9}cran ",
        "Enregistrement de l'écran ",
        "Grabaci\u{00F3}n de pantalla ",
        "Grava\u{00E7}\u{00E3}o de Tela ",
        "Grava\u{00E7}\u{00E3}o de tela ",
    ]

    // Date extraction pattern: YYYY-MM-DD somewhere in the filename
    private static let datePattern = try! NSRegularExpression(
        pattern: #"(\d{4}-\d{2}-\d{2})"#
    )

    // MARK: - Scan

    /// Scan a folder for Apple-default-named files and legacy CaptureFlow daily folders.
    public static func scan(in folder: URL, rootFolderName: String) -> ScanResult {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ScanResult(files: [], folders: [])
        }

        var files: [URL] = []
        var folders: [URL] = []

        let knownPrefixes = FolderPrefix.allPrefixes

        for item in contents {
            let name = item.lastPathComponent

            // Skip the root folder itself
            if name == rootFolderName { continue }

            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDir {
                // Check for legacy daily folders: {prefix}_{YYYY-MM-DD}
                for prefix in knownPrefixes {
                    if name.hasPrefix("\(prefix)_") {
                        folders.append(item)
                        break
                    }
                }
            } else {
                // Check for Apple-default screenshot/recording filenames
                let ext = item.pathExtension.lowercased()
                guard ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "mov" || ext == "mp4" else { continue }

                let isScreenshot = screenshotPrefixes.contains { name.hasPrefix($0) }
                let isRecording = recordingPrefixes.contains { name.hasPrefix($0) }

                if isScreenshot || isRecording {
                    files.append(item)
                }
            }
        }

        return ScanResult(files: files, folders: folders)
    }

    // MARK: - Run Migration

    /// Organize files and folders into the new root folder structure.
    /// - Parameters:
    ///   - scanResult: The result of a prior `scan()` call
    ///   - screenshotFolder: The base screenshot folder (e.g. ~/Desktop)
    ///   - rootFolderName: Name of the root folder (e.g. "Screenshots")
    ///   - dateFormatter: Formatter for daily folder names
    ///   - separateSubfolders: Whether to create images/videos subfolders
    ///   - imagesFolderName: Localized images subfolder name
    ///   - videosFolderName: Localized videos subfolder name
    ///   - namer: Optional namer for AI-based renaming of photos
    ///   - progress: Callback with (completed, total) counts
    public static func run(
        scanResult: ScanResult,
        screenshotFolder: URL,
        rootFolderName: String,
        dateFormatter: DateFormatter,
        separateSubfolders: Bool,
        imagesFolderName: String,
        videosFolderName: String,
        namer: (any ImageNamer)?,
        progress: @escaping (Int, Int) -> Void
    ) async -> Int {
        let fm = FileManager.default
        let rootFolder = screenshotFolder.appendingPathComponent(rootFolderName)

        // Ensure root folder exists
        try? fm.createDirectory(at: rootFolder, withIntermediateDirectories: true)

        let total = scanResult.fileCount + scanResult.folderCount
        var completed = 0

        // --- Migrate individual files ---
        for fileURL in scanResult.files {
            let fileDate = extractDate(from: fileURL.lastPathComponent) ?? creationDate(of: fileURL)
            let datePart = sanitizedDateString(from: fileDate, formatter: dateFormatter)
            let mediaType = MediaType.from(pathExtension: fileURL.pathExtension) ?? .photo

            // Generate content slug
            let contentSlug: String
            if mediaType == .photo, let namer {
                if let image = loadCGImage(from: fileURL) {
                    contentSlug = (try? await namer.name(image: image, context: .empty)) ?? "screenshot"
                } else {
                    contentSlug = "screenshot"
                }
            } else if mediaType == .video {
                contentSlug = "recording"
            } else {
                contentSlug = "screenshot"
            }

            let timeStr = timeString(from: fileDate)
            let baseName = "\(contentSlug)_\(timeStr)"
            let ext = fileURL.pathExtension

            var destFolder = rootFolder.appendingPathComponent(datePart)
            if separateSubfolders {
                destFolder = destFolder.appendingPathComponent(
                    mediaType == .photo ? imagesFolderName : videosFolderName
                )
            }

            try? fm.createDirectory(at: destFolder, withIntermediateDirectories: true)

            var destFile = destFolder.appendingPathComponent("\(baseName).\(ext)")
            var counter = 1
            while fm.fileExists(atPath: destFile.path) {
                destFile = destFolder.appendingPathComponent("\(baseName)_\(counter).\(ext)")
                counter += 1
            }

            do {
                try fm.moveItem(at: fileURL, to: destFile)
                print("[Migration] \(fileURL.lastPathComponent) → \(rootFolderName)/\(datePart)/\(destFile.lastPathComponent)")
            } catch {
                print("[Migration] failed to move \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }

            completed += 1
            progress(completed, total)
        }

        // --- Migrate existing legacy daily folders ---
        for folderURL in scanResult.folders {
            let folderName = folderURL.lastPathComponent

            // Extract date from folder name (strip prefix)
            let datePart: String
            if let underscoreIdx = folderName.firstIndex(of: "_") {
                let dateSubstring = folderName[folderName.index(after: underscoreIdx)...]
                // Re-format the date if possible
                let legacyFormatter = DateFormatter()
                legacyFormatter.dateFormat = "yyyy-MM-dd"
                if let parsed = legacyFormatter.date(from: String(dateSubstring)) {
                    datePart = sanitizedDateString(from: parsed, formatter: dateFormatter)
                } else {
                    datePart = String(dateSubstring)
                }
            } else {
                datePart = folderName
            }

            let destFolder = rootFolder.appendingPathComponent(datePart)

            if fm.fileExists(atPath: destFolder.path) {
                // Merge contents
                if let items = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
                    for item in items {
                        let target = destFolder.appendingPathComponent(item.lastPathComponent)
                        try? fm.moveItem(at: item, to: target)
                    }
                    try? fm.removeItem(at: folderURL)
                }
            } else {
                try? fm.moveItem(at: folderURL, to: destFolder)
            }

            // Retroactively split into images/videos subfolders if enabled
            if separateSubfolders {
                splitSubfolders(
                    in: destFolder,
                    imagesFolderName: imagesFolderName,
                    videosFolderName: videosFolderName
                )
            }

            completed += 1
            progress(completed, total)
            print("[Migration] folder \(folderName) → \(rootFolderName)/\(datePart)/")
        }

        return completed
    }

    // MARK: - Helpers

    /// Extract a date from an Apple-default filename.
    static func extractDate(from filename: String) -> Date? {
        let range = NSRange(filename.startIndex..., in: filename)
        guard let match = datePattern.firstMatch(in: filename, range: range),
              let dateRange = Range(match.range(at: 1), in: filename) else {
            return nil
        }
        let dateStr = String(filename[dateRange])
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateStr)
    }

    private static func creationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    private static func sanitizedDateString(from date: Date, formatter: DateFormatter) -> String {
        formatter.string(from: date)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    private static func timeString(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d-%02d-%02d", c.hour!, c.minute!, c.second!)
    }

    private static func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return image
    }

    /// Retroactively sort files in a folder into images/ and videos/ subfolders.
    private static func splitSubfolders(
        in folder: URL,
        imagesFolderName: String,
        videosFolderName: String
    ) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { continue } // Skip existing subdirectories

            guard let mediaType = MediaType.from(pathExtension: item.pathExtension) else { continue }
            let subfolderName = mediaType == .photo ? imagesFolderName : videosFolderName
            let subfolder = folder.appendingPathComponent(subfolderName)

            try? fm.createDirectory(at: subfolder, withIntermediateDirectories: true)

            let dest = subfolder.appendingPathComponent(item.lastPathComponent)
            try? fm.moveItem(at: item, to: dest)
        }
    }
}
