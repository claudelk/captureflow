import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

/// Orchestrates the full rename pipeline:
///   1. Match to a CaptureContext from the keystroke store (before sleeping)
///   2. Wait briefly for macOS to finish writing the file
///   3. For photos: run namer to generate a content slug
///      For videos: use app context or "recording" as slug
///   4. Build {app-slug}_{YYYY-MM-DD}/{subfolder?}/{content-slug}_{HH-mm-ss}.{ext}
///   5. Create folder if needed, move file, optionally convert format
public actor RenameEngine {

    private let namer: any ImageNamer
    private let store: CaptureContextStore
    private let groupByApp: Bool
    private let folderPrefix: String
    private let separateSubfolders: Bool
    private let photoFormat: PhotoFormat
    private let videoFormat: VideoFormat
    private var recentlyProcessed: [String: Date] = [:]

    public init(
        namer: any ImageNamer,
        store: CaptureContextStore,
        groupByApp: Bool = false,
        folderPrefix: String = "screenshot",
        separateSubfolders: Bool = false,
        photoFormat: PhotoFormat = .png,
        videoFormat: VideoFormat = .mov
    ) {
        self.namer = namer
        self.store = store
        self.groupByApp = groupByApp
        self.folderPrefix = folderPrefix
        self.separateSubfolders = separateSubfolders
        self.photoFormat = photoFormat
        self.videoFormat = videoFormat
    }

    // MARK: - Public

    @discardableResult
    public func process(newFile url: URL, detectedAt: Date) async -> URL? {
        let path = url.path

        // Debounce
        pruneRecent()
        guard recentlyProcessed[path] == nil else { return nil }
        recentlyProcessed[path] = Date()

        let matched = store.nearest(to: detectedAt)
        let context = matched ?? .empty
        let mediaType = MediaType.from(pathExtension: url.pathExtension) ?? .photo

        // Give macOS time to finish writing
        try? await Task.sleep(nanoseconds: 500_000_000)

        guard FileManager.default.fileExists(atPath: path) else {
            print("[RenameEngine] file vanished: \(url.lastPathComponent)")
            return nil
        }

        // Generate content slug — different path for photos vs videos
        let contentSlug: String
        switch mediaType {
        case .photo:
            guard let image = loadCGImage(from: url) else {
                print("[RenameEngine] could not load image: \(url.lastPathComponent)")
                return nil
            }
            do {
                contentSlug = try await namer.name(image: image, context: context)
            } catch {
                print("[RenameEngine] naming failed — \(error.localizedDescription)")
                return nil
            }
        case .video:
            // No OCR/LLM for videos — use app name or "recording"
            if !context.appName.isEmpty {
                contentSlug = SlugGenerator.slug(from: context.appName) + "-recording"
            } else {
                contentSlug = "recording"
            }
        }

        let fileDate = context.appName.isEmpty ? creationDate(of: url) : context.capturedAt

        // Build destination path
        let appSlug = (groupByApp && !context.appName.isEmpty)
            ? SlugGenerator.slug(from: context.appName)
            : folderPrefix
        let folderName = "\(appSlug)_\(dateString(from: fileDate))"
        let baseName = "\(contentSlug)_\(timeString(from: fileDate))"
        let ext = fileExtension(for: mediaType)

        let baseDir = url.deletingLastPathComponent()
        var destFolder = baseDir.appendingPathComponent(folderName)
        if separateSubfolders {
            destFolder = destFolder.appendingPathComponent(mediaType == .photo ? "photos" : "videos")
        }

        var destFile = destFolder.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while FileManager.default.fileExists(atPath: destFile.path) {
            destFile = destFolder.appendingPathComponent("\(baseName)_\(counter).\(ext)")
            counter += 1
        }

        // Create folder and move
        do {
            try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: destFile)
            let subPath = separateSubfolders
                ? "\(folderName)/\(mediaType == .photo ? "photos" : "videos")/\(destFile.lastPathComponent)"
                : "\(folderName)/\(destFile.lastPathComponent)"
            print("[RenameEngine] \(url.lastPathComponent)")
            print("           → \(subPath)")
        } catch {
            print("[RenameEngine] move failed — \(error.localizedDescription)")
            return nil
        }

        // Format conversion (after move)
        let finalFile = convertIfNeeded(file: destFile, mediaType: mediaType)
        return finalFile
    }

    /// Manually rename a file. Skips debounce, delay, and context lookup.
    @discardableResult
    public func processManual(file url: URL) async -> URL? {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            print("[RenameEngine] file not found: \(url.lastPathComponent)")
            return nil
        }

        let mediaType = MediaType.from(pathExtension: url.pathExtension) ?? .photo

        let contentSlug: String
        switch mediaType {
        case .photo:
            guard let image = loadCGImage(from: url) else {
                print("[RenameEngine] could not load image: \(url.lastPathComponent)")
                return nil
            }
            do {
                contentSlug = try await namer.name(image: image, context: .empty)
            } catch {
                print("[RenameEngine] naming failed — \(error.localizedDescription)")
                return nil
            }
        case .video:
            contentSlug = "recording"
        }

        let fileDate = creationDate(of: url)
        let folderName = "\(folderPrefix)_\(dateString(from: fileDate))"
        let baseName = "\(contentSlug)_\(timeString(from: fileDate))"
        let ext = fileExtension(for: mediaType)

        let baseDir = url.deletingLastPathComponent()
        var destFolder = baseDir.appendingPathComponent(folderName)
        if separateSubfolders {
            destFolder = destFolder.appendingPathComponent(mediaType == .photo ? "photos" : "videos")
        }

        var destFile = destFolder.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while FileManager.default.fileExists(atPath: destFile.path) {
            destFile = destFolder.appendingPathComponent("\(baseName)_\(counter).\(ext)")
            counter += 1
        }

        do {
            try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: destFile)
            print("[RenameEngine] \(url.lastPathComponent)")
            print("           → \(folderName)/\(destFile.lastPathComponent)")
        } catch {
            print("[RenameEngine] move failed — \(error.localizedDescription)")
            return nil
        }

        let finalFile = convertIfNeeded(file: destFile, mediaType: mediaType)
        return finalFile
    }

    // MARK: - Format Conversion

    private func fileExtension(for mediaType: MediaType) -> String {
        switch mediaType {
        case .photo: return photoFormat.fileExtension
        case .video: return videoFormat.fileExtension
        }
    }

    /// Convert format if needed. Returns the final file URL.
    private func convertIfNeeded(file url: URL, mediaType: MediaType) -> URL {
        switch mediaType {
        case .photo where photoFormat == .jpeg && url.pathExtension.lowercased() == "png":
            // Source was PNG, user wants JPEG — convert synchronously (fast for screenshots)
            if let converted = convertToJPEG(at: url) {
                return converted
            }
        case .video where videoFormat == .mp4 && url.pathExtension.lowercased() == "mov":
            // Source was MOV, user wants MP4 — convert in background (can be slow)
            convertToMP4(at: url)
            // Return the .mp4 URL (file will appear after conversion completes)
            return url.deletingPathExtension().appendingPathExtension("mp4")
        default:
            break
        }
        return url
    }

    private func convertToJPEG(at url: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let jpegURL = url.deletingPathExtension().appendingPathExtension("jpg")
        guard let dest = CGImageDestinationCreateWithURL(
            jpegURL as CFURL, "public.jpeg" as CFString, 1, nil
        ) else { return nil }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)

        guard CGImageDestinationFinalize(dest) else { return nil }

        // Remove original PNG
        try? FileManager.default.removeItem(at: url)
        print("[RenameEngine] converted to JPEG: \(jpegURL.lastPathComponent)")
        return jpegURL
    }

    private func convertToMP4(at movURL: URL) {
        Task.detached {
            let asset = AVAsset(url: movURL)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                print("[RenameEngine] MP4 conversion failed: could not create export session")
                return
            }
            let mp4URL = movURL.deletingPathExtension().appendingPathExtension("mp4")
            session.outputURL = mp4URL
            session.outputFileType = .mp4
            await session.export()
            if session.status == .completed {
                try? FileManager.default.removeItem(at: movURL)
                print("[RenameEngine] converted to MP4: \(mp4URL.lastPathComponent)")
            } else {
                print("[RenameEngine] MP4 conversion failed: \(session.error?.localizedDescription ?? "unknown")")
            }
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
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
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
