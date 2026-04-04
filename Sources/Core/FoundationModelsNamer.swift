import CoreGraphics
import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Tier 2 namer: Vision OCR + Apple Intelligence on-device LLM.
///
/// Strategy:
///   1. Reuse VisionOnlyNamer.analyze() for OCR text + scene classification.
///   2. Feed the results to Foundation Models LLM with a naming prompt.
///   3. Use @Generable structured output to get a clean filename.
///   4. Fall back to Tier 1 slug if LLM is unavailable or fails.
///
/// Available on macOS 26+, Apple Silicon, with Apple Intelligence enabled.
@available(macOS 26.0, *)
public final class FoundationModelsNamer: ImageNamer {

    private let visionNamer = VisionOnlyNamer()

    public init() {}

    // MARK: - ImageNamer

    public func name(image: CGImage, context: CaptureContext) async throws -> String {
        // Step 1: Run Vision OCR + classification (same as Tier 1)
        let (ocrLines, classifications) = try await visionNamer.analyze(image: image)

        // Step 2: Check LLM availability — fall back to Tier 1 if not ready
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            print("[FoundationModelsNamer] LLM not available — falling back to Tier 1")
            return visionNamer.buildSlug(
                ocrLines: ocrLines,
                classifications: classifications,
                context: context
            )
        }

        // Step 3: Build prompt from OCR + classifications + context
        let prompt = buildPrompt(
            ocrLines: ocrLines,
            classifications: classifications,
            context: context
        )

        // Step 4: Generate name via LLM
        do {
            let session = LanguageModelSession(
                instructions: Instructions("""
                    You generate short, descriptive filenames for screenshots. \
                    Given OCR text, scene labels, and app context, produce a \
                    concise 2-5 word name that captures the MAIN TOPIC of the page. \
                    Use lowercase words. No file extension. No special characters. \
                    Prioritize the page title or main headline over body text, \
                    secondary UI elements, sidebars, or nested content within the page. \
                    If this is a web article, use the article title. \
                    If this is an app, describe the main screen or view shown.
                    """)
            )

            let response = try await session.respond(
                to: prompt,
                generating: ScreenshotName.self
            )

            let slug = SlugGenerator.slug(from: response.content.name)
            guard slug != "untitled" && !slug.isEmpty else {
                return visionNamer.buildSlug(
                    ocrLines: ocrLines,
                    classifications: classifications,
                    context: context
                )
            }
            return slug
        } catch {
            print("[FoundationModelsNamer] LLM failed: \(error.localizedDescription) — falling back to Tier 1")
            return visionNamer.buildSlug(
                ocrLines: ocrLines,
                classifications: classifications,
                context: context
            )
        }
    }

    // MARK: - Private

    private func buildPrompt(
        ocrLines: [(text: String, confidence: Float)],
        classifications: [(label: String, confidence: Float)],
        context: CaptureContext
    ) -> String {
        var parts: [String] = []

        // App context
        if !context.appName.isEmpty {
            parts.append("App: \(context.appName)")
        }

        // OCR lines: send the top lines, marking the highest-scored as likely headline
        let filtered = ocrLines
            .filter { $0.confidence > 0.3 }
            .sorted { SlugGenerator.meaningScore(for: $0.text) > SlugGenerator.meaningScore(for: $1.text) }

        if let first = filtered.first {
            parts.append("Likely headline/title: \(first.text)")
        }

        let otherLines = filtered.dropFirst().prefix(7).map { $0.text }
        if !otherLines.isEmpty {
            parts.append("Other text: \(otherLines.joined(separator: " | "))")
        }

        // Scene labels
        let labels = classifications
            .filter { !$0.label.hasPrefix("others_") }
            .map { $0.label.replacingOccurrences(of: "_", with: " ") }

        if !labels.isEmpty {
            parts.append("Scene: \(labels.joined(separator: ", "))")
        }

        if parts.isEmpty {
            return "A screenshot with no recognizable text or objects."
        }

        return parts.joined(separator: "\n")
    }
}

/// Structured output for the LLM — ensures a clean filename string.
@available(macOS 26.0, *)
@Generable
struct ScreenshotName {
    @Guide(description: "A concise 2-5 word descriptive name for the screenshot content, lowercase, no file extension, no special characters")
    var name: String
}

#endif
