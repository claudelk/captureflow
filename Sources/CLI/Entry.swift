import Foundation
import CoreGraphics
import ImageIO
import SmartScreenShotCore

@main
struct SmartScreenShotCLI {

    static func main() async {
        guard let args = parseArgs() else {
            printUsage()
            exit(1)
        }

        let resolvedPath = resolvePath(args.imagePath)

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            fputs("error: file not found — \(resolvedPath)\n", stderr)
            exit(1)
        }

        guard let image = loadCGImage(from: resolvedPath) else {
            fputs("error: could not load image at \(resolvedPath)\n", stderr)
            exit(1)
        }

        let namer = VisionOnlyNamer()

        do {
            if args.verbose {
                let (ocrLines, classifications) = try await namer.analyze(image: image)

                print("=== OCR Results (\(ocrLines.count) lines) ===")
                if ocrLines.isEmpty {
                    print("  (none)")
                } else {
                    for line in ocrLines.sorted(by: { $0.confidence > $1.confidence }).prefix(10) {
                        let score = SlugGenerator.meaningScore(for: line.text)
                        print("  [\(String(format: "%.2f", line.confidence))] score=\(score)  \"\(line.text)\"")
                    }
                }

                print("\n=== Classifications (\(classifications.count)) ===")
                if classifications.isEmpty {
                    print("  (none)")
                } else {
                    for cls in classifications {
                        print("  [\(String(format: "%.3f", cls.confidence))]  \(cls.label)")
                    }
                }
                print()

                let slug = namer.buildSlug(
                    ocrLines: ocrLines,
                    classifications: classifications,
                    context: .empty
                )
                print("=== Slug ===")
                print(slug)

            } else {
                let slug = try await namer.name(image: image, context: .empty)
                print(slug)
            }
        } catch {
            fputs("error analyzing image: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    // MARK: - Argument parsing

    private static func parseArgs() -> (imagePath: String, verbose: Bool)? {
        var args = CommandLine.arguments.dropFirst()
        var verbose = false
        var imagePath: String?

        while let arg = args.first {
            args = args.dropFirst()
            switch arg {
            case "--verbose", "-v":
                verbose = true
            case "--help", "-h":
                return nil
            default:
                if !arg.hasPrefix("-") { imagePath = arg }
            }
        }

        guard let path = imagePath else { return nil }
        return (path, verbose)
    }

    // MARK: - Path helpers

    private static func resolvePath(_ path: String) -> String {
        if path.hasPrefix("/") { return path }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2))).path
        }
        return FileManager.default.currentDirectoryPath + "/" + path
    }

    private static func loadCGImage(from path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image  = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return image
    }

    // MARK: - Usage

    private static func printUsage() {
        print("""
        Usage: sst <image-path> [--verbose]

        Analyzes a screenshot with Apple Vision OCR + scene classification
        and prints a kebab-case filename slug to stdout.

        Options:
          -v, --verbose    Print OCR lines, confidence scores, and classification labels
          -h, --help       Show this help

        Examples:
          sst screenshot.png
          sst ~/Desktop/screen.png --verbose
          sst /tmp/game.png -v
        """)
    }
}
