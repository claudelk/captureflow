import Vision
import CoreGraphics
import Foundation

/// Tier 1 namer: Apple Vision OCR + scene classification.
///
/// Strategy:
///   1. Run VNRecognizeTextRequest (accurate mode) — yields OCR lines with confidence scores.
///   2. Run VNClassifyImageRequest — yields scene/object labels.
///      Both requests are dispatched to the same VNImageRequestHandler.perform() call,
///      which runs them sequentially on the calling thread (not concurrently).
///   3. Pick the highest-scoring OCR line (filtering low-confidence and trivial strings).
///   4. If OCR yields nothing useful, fall back to the top classification label.
///   5. Ultimate fallback: "untitled".
///
/// Available on macOS 13+. Fully offline. No additional dependencies.
public final class VisionOnlyNamer: ImageNamer {

    public init() {}

    // MARK: - ImageNamer

    public func name(image: CGImage, context: CaptureContext) async throws -> String {
        let (ocrLines, classifications) = try await analyze(image: image)
        return buildSlug(ocrLines: ocrLines, classifications: classifications, context: context)
    }

    // MARK: - Analysis (public for CLI verbose mode)

    public func analyze(image: CGImage) async throws -> (
        ocrLines: [(text: String, confidence: Float)],
        classifications: [(label: String, confidence: Float)]
    ) {
        try await withCheckedThrowingContinuation { continuation in
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            var ocrLines: [(text: String, confidence: Float)] = []
            var classifications: [(label: String, confidence: Float)] = []

            // --- OCR ---
            let ocrRequest = VNRecognizeTextRequest { request, _ in
                ocrLines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { obs in
                        guard let top = obs.topCandidates(1).first else { return nil }
                        return (top.string, top.confidence)
                    }
            }
            ocrRequest.recognitionLevel = .accurate
            ocrRequest.usesLanguageCorrection = true
            // System-preferred languages, always include English as fallback
            let preferred = Array(Locale.preferredLanguages.prefix(3))
            ocrRequest.recognitionLanguages = preferred.contains("en-US") ? preferred : preferred + ["en-US"]

            // --- Scene / object classification ---
            let classifyRequest = VNClassifyImageRequest { request, _ in
                classifications = (request.results as? [VNClassificationObservation] ?? [])
                    .filter { $0.confidence > 0.1 }
                    .prefix(5)
                    .map { ($0.identifier, $0.confidence) }
            }

            do {
                try handler.perform([ocrRequest, classifyRequest])
                continuation.resume(returning: (ocrLines, classifications))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Slug building (public for CLI verbose mode)

    public func buildSlug(
        ocrLines: [(text: String, confidence: Float)],
        classifications: [(label: String, confidence: Float)],
        context: CaptureContext
    ) -> String {
        // Pick the highest-scoring OCR line above the confidence floor
        let bestOCR = ocrLines
            .filter { $0.confidence > 0.3 }
            .max { SlugGenerator.meaningScore(for: $0.text) < SlugGenerator.meaningScore(for: $1.text) }

        if let ocr = bestOCR, SlugGenerator.meaningScore(for: ocr.text) > 5 {
            return SlugGenerator.slug(from: ocr.text)
        }

        // Fallback: top classification label — skip Apple's catch-all "others_*" buckets
        if let cls = classifications.first(where: { !$0.label.hasPrefix("others_") && !$0.label.isEmpty }) {
            let label = cls.label.replacingOccurrences(of: "_", with: " ")
            return SlugGenerator.slug(from: label)
        }

        return "untitled"
    }
}
