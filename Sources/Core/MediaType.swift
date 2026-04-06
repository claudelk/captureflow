import Foundation

/// The type of captured media.
public enum MediaType: String, Sendable {
    case photo
    case video

    /// Detect media type from a file extension.
    public static func from(pathExtension ext: String) -> MediaType? {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg": return .photo
        case "mov", "mp4": return .video
        default: return nil
        }
    }
}

/// Output format for photos.
public enum PhotoFormat: String, Sendable {
    case png
    case jpeg

    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }
}

/// Output format for videos.
public enum VideoFormat: String, Sendable {
    case mov
    case mp4

    public var fileExtension: String { rawValue }
}
