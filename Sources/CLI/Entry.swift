import Foundation
import CoreGraphics
import ImageIO
import CaptureFlowCore

@main
struct CaptureFlowCLI {

    static func main() async {
        let parsed = parseArgs()

        switch parsed {
        case .help:
            printUsage()
            exit(0)

        case .invalid:
            printUsage()
            exit(1)

        case .rename(let paths):
            await runRename(paths: paths)

        case .analyze(let path, let verbose):
            await runAnalyze(path: path, verbose: verbose)
        }
    }

    // MARK: - Modes

    private static func runAnalyze(path: String, verbose: Bool) async {
        let resolvedPath = resolvePath(path)

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
            if verbose {
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

    private static func runRename(paths: [String]) async {
        let namer = VisionOnlyNamer()
        let store = CaptureContextStore()
        // Read preferences directly from UserDefaults for consistent behavior with the app
        let defaults = UserDefaults(suiteName: "com.captureflow.preferences")
        let langCode: String = {
            let stored = defaults?.string(forKey: "appLanguage") ?? "system"
            if stored != "system" { return stored }
            return Locale.preferredLanguages.first
                .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        }()
        let useCustomRoot = defaults?.bool(forKey: "useCustomRootFolder") ?? false
        let customRootName = defaults?.string(forKey: "customRootFolderName") ?? ""
        let rootFolder = (useCustomRoot && !customRootName.isEmpty)
            ? customRootName
            : FolderPrefix.rootFolderName(for: langCode)
        let separatePhotoVideo = defaults?.object(forKey: "separatePhotoVideo") != nil
            ? (defaults?.bool(forKey: "separatePhotoVideo") ?? true)
            : true
        let dateFormatter: DateFormatter = {
            let df = DateFormatter()
            let useCustom = defaults?.bool(forKey: "useCustomDateFormat") ?? false
            let customFormat = defaults?.string(forKey: "customDateFormat") ?? ""
            if useCustom && !customFormat.isEmpty {
                df.dateFormat = customFormat
            } else {
                df.dateStyle = .short
                df.timeStyle = .none
            }
            return df
        }()
        let engine = RenameEngine(
            namer: namer, store: store,
            rootFolderName: rootFolder,
            separateSubfolders: separatePhotoVideo,
            imagesFolderName: FolderPrefix.imagesFolderName(for: langCode),
            videosFolderName: FolderPrefix.videosFolderName(for: langCode),
            dateFormatter: dateFormatter
        )

        var succeeded = 0
        var failed = 0

        for path in paths {
            let resolved = resolvePath(path)
            let url = URL(fileURLWithPath: resolved)

            guard FileManager.default.fileExists(atPath: resolved) else {
                fputs("skip: file not found — \(path)\n", stderr)
                failed += 1
                continue
            }

            if let dest = await engine.processManual(file: url) {
                succeeded += 1
                _ = dest  // Output already printed by RenameEngine
            } else {
                failed += 1
            }
        }

        if paths.count > 1 {
            print("\nRenamed \(succeeded)/\(paths.count) files" +
                  (failed > 0 ? " (\(failed) failed)" : ""))
        }
    }

    // MARK: - Argument parsing

    private enum ParsedArgs {
        case analyze(path: String, verbose: Bool)
        case rename(paths: [String])
        case help
        case invalid
    }

    private static func parseArgs() -> ParsedArgs {
        let args = Array(CommandLine.arguments.dropFirst())
        var verbose = false
        var renameMode = false
        var paths: [String] = []

        for arg in args {
            switch arg {
            case "--verbose", "-v":
                verbose = true
            case "--help", "-h":
                return .help
            case "--rename", "-r":
                renameMode = true
            default:
                if !arg.hasPrefix("-") { paths.append(arg) }
            }
        }

        if renameMode {
            guard !paths.isEmpty else { return .invalid }
            return .rename(paths: paths)
        }

        guard let path = paths.first else { return .invalid }
        return .analyze(path: path, verbose: verbose)
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
               sst --rename <file1> [file2] ...

        Analyzes a screenshot with Apple Vision OCR + scene classification
        and prints a kebab-case filename slug to stdout.

        Modes:
          (default)        Print slug only (pipe-friendly)
          -r, --rename     Rename files in place into screenshot_{date}/ folders

        Options:
          -v, --verbose    Print OCR lines, confidence scores, and classification labels
          -h, --help       Show this help

        Examples:
          sst screenshot.png
          sst ~/Desktop/screen.png --verbose
          sst --rename screenshot1.png screenshot2.png
          sst --rename ~/Desktop/Screenshot*.png
        """)
    }
}
