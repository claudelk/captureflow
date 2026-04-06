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
    private let languageCode: String

    public init(languageCode: String = "en") {
        self.languageCode = languageCode
    }

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
            var instructions = """
                You generate short filenames for screenshots. Rules: \
                1. Output 2-5 lowercase words describing the MAIN TOPIC. \
                2. For web pages: use the page/article TITLE, not body paragraphs. \
                3. For apps: describe the main view or screen. \
                4. Ignore navigation bars, tab bars, sidebars, and small UI labels. \
                5. Ignore text inside nested phone mockups or embedded images. \
                6. No file extension, no special characters. \
                Example: a screenshot of an Apple Newsroom article about iPhones \
                should be named "apple-iphone-announcement", NOT after text \
                visible inside phone mockup images on the page.
                """

            // Add language directive for non-English
            if languageCode != "en" {
                let langName = ["fr": "French", "es": "Spanish", "pt": "Portuguese", "sw": "Swahili"][languageCode] ?? "English"
                instructions += " Generate the filename words in \(langName)."
            }

            let session = LanguageModelSession(
                instructions: Instructions(instructions)
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

        // Send ALL OCR lines in reading order (as returned by Vision).
        // Filter out very short fragments (nav items, single words) to prioritize content.
        let allLines = ocrLines
            .filter { $0.confidence > 0.3 && $0.text.count >= 3 }
            .map { $0.text }

        if !allLines.isEmpty {
            parts.append("All text on screen (top to bottom):\n\(allLines.joined(separator: "\n"))")
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
