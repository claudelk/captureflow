import CoreGraphics
import Foundation

/// Context captured at the exact moment a screenshot keystroke is pressed.
/// The `empty` singleton is used during CLI testing when no daemon context exists.
public struct CaptureContext: Sendable {
    public let appName: String
    public let appBundleID: String
    public let browserURL: URL?
    public let capturedAt: Date

    public init(
        appName: String,
        appBundleID: String,
        browserURL: URL?,
        capturedAt: Date
    ) {
        self.appName = appName
        self.appBundleID = appBundleID
        self.browserURL = browserURL
        self.capturedAt = capturedAt
    }

    public static let empty = CaptureContext(
        appName: "",
        appBundleID: "",
        browserURL: nil,
        capturedAt: Date()
    )
}

/// Protocol all naming tiers conform to.
/// Tier 1 — VisionOnlyNamer  (macOS 13+, ships in v1)
/// Tier 2 — FoundationModelsNamer (macOS 26+, Apple Intelligence)
/// Tier 3 — FastVLMNamer (Apple Silicon, opt-in, v2)
public protocol ImageNamer: Sendable {
    func name(image: CGImage, context: CaptureContext) async throws -> String
}
