import XCTest
@testable import CaptureFlowCore

/// A mock namer that returns a predictable slug.
private struct MockNamer: ImageNamer {
    let slug: String
    func name(image: CGImage, context: CaptureContext) async throws -> String {
        return slug
    }
}

/// Deterministic date formatter for tests (always yyyy-MM-dd).
private func testDateFormatter() -> DateFormatter {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    return df
}

final class RenameEngineTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("captureflow-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Create a minimal 1x1 PNG file for testing.
    private func createTestPNG(named name: String = "Screenshot 2026-03-29 at 1.00.00 PM.png") -> URL {
        let url = tempDir.appendingPathComponent(name)
        // Minimal valid PNG: 1x1 white pixel
        let size = CGSize(width: 1, height: 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let image = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return url
    }

    /// Helper: extract path components relative to tempDir.
    /// e.g. tempDir/Screenshots/2026-04-07/images/test_12-00-00.png → ["Screenshots", "2026-04-07", "images", "test_12-00-00.png"]
    private func relativeComponents(of url: URL) -> [String] {
        let full = url.standardizedFileURL.path
        let base = tempDir.standardizedFileURL.path
        guard full.hasPrefix(base) else { return [] }
        let relative = String(full.dropFirst(base.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.components(separatedBy: "/")
    }

    // MARK: - Root Folder

    func testRootFolderIsCreated() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Screenshots", separateSubfolders: true,
            dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        let comps = relativeComponents(of: result!)
        XCTAssertEqual(comps[0], "Screenshots", "Root folder should be 'Screenshots'")
    }

    func testEmptyRootFolderFallsBackToLegacy() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "", dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertTrue(parentFolder.hasPrefix("screenshot_"), "Legacy mode: expected 'screenshot_' prefix, got: \(parentFolder)")
    }

    // MARK: - groupByApp Flag

    func testGroupByAppFalseUsesDateOnlyFolder() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test-content"), store: store,
            groupByApp: false, rootFolderName: "Screenshots",
            separateSubfolders: true, dateFormatter: testDateFormatter()
        )

        let now = Date()
        store.store(CaptureContext(
            appName: "Safari",
            appBundleID: "com.apple.Safari",
            browserURL: nil,
            capturedAt: now
        ))

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: now)

        XCTAssertNotNil(result)
        let comps = relativeComponents(of: result!)
        // Screenshots / YYYY-MM-DD / images / file.png
        XCTAssertEqual(comps[0], "Screenshots")
        XCTAssertFalse(comps[1].contains("safari"), "groupByApp=false should NOT include app name, got: \(comps[1])")
        XCTAssertEqual(comps[2], "images")
    }

    func testGroupByAppTrueUsesAppFolder() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test-content"), store: store,
            groupByApp: true, rootFolderName: "Screenshots",
            separateSubfolders: true, dateFormatter: testDateFormatter()
        )

        let now = Date()
        store.store(CaptureContext(
            appName: "Safari",
            appBundleID: "com.apple.Safari",
            browserURL: nil,
            capturedAt: now
        ))

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: now)

        XCTAssertNotNil(result)
        let comps = relativeComponents(of: result!)
        XCTAssertEqual(comps[0], "Screenshots")
        XCTAssertTrue(comps[1].hasPrefix("safari_"), "Expected 'safari_' prefix, got: \(comps[1])")
    }

    func testGroupByAppTrueWithEmptyContextUsesDateOnly() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test-content"), store: store,
            groupByApp: true, rootFolderName: "Screenshots",
            dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        let comps = relativeComponents(of: result!)
        XCTAssertEqual(comps[0], "Screenshots")
        // Empty context → no app slug, just date
        XCTAssertFalse(comps[1].contains("_") && !comps[1].hasPrefix("screenshot"), "Empty context with root folder should use date-only folder")
    }

    func testGroupByAppDefaultIsFalse() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test-content"), store: store,
            rootFolderName: "Screenshots", dateFormatter: testDateFormatter()
        )

        let now = Date()
        store.store(CaptureContext(
            appName: "Xcode",
            appBundleID: "com.apple.dt.Xcode",
            browserURL: nil,
            capturedAt: now
        ))

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: now)

        XCTAssertNotNil(result)
        let comps = relativeComponents(of: result!)
        XCTAssertFalse(comps[1].contains("xcode"), "Default groupByApp should be false")
    }

    // MARK: - processManual

    func testProcessManualUsesRootFolder() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "manual-test"), store: store,
            groupByApp: true, rootFolderName: "Screenshots",
            dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let result = await engine.processManual(file: testFile)

        XCTAssertNotNil(result)
        let comps = relativeComponents(of: result!)
        XCTAssertEqual(comps[0], "Screenshots")
    }

    func testCustomFolderPrefixLegacy() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            folderPrefix: "capture-d-ecran", rootFolderName: "",
            dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertTrue(parentFolder.hasPrefix("capture-d-ecran_"), "Expected 'capture-d-ecran_' prefix, got: \(parentFolder)")
    }

    func testProcessManualUsesCustomPrefix() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            folderPrefix: "mes-captures", rootFolderName: "",
            dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let result = await engine.processManual(file: testFile)

        XCTAssertNotNil(result)
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertTrue(parentFolder.hasPrefix("mes-captures_"), "Expected 'mes-captures_' prefix, got: \(parentFolder)")
    }

    // MARK: - Video Support

    func testVideoFileSkipsNamerAndRenames() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "should-not-use"), store: store,
            rootFolderName: "Screenshots", dateFormatter: testDateFormatter()
        )

        let movURL = tempDir.appendingPathComponent("Screen Recording 2026-04-06.mov")
        try! Data(count: 100).write(to: movURL)

        let result = await engine.process(newFile: movURL, detectedAt: Date())

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.lastPathComponent.contains("recording"), "Video should use 'recording' slug, got: \(result!.lastPathComponent)")
        XCTAssertEqual(result!.pathExtension, "mov")
    }

    func testVideoWithAppContextUsesAppName() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "ignored"), store: store,
            rootFolderName: "Screenshots", dateFormatter: testDateFormatter()
        )

        let now = Date()
        store.store(CaptureContext(
            appName: "Safari",
            appBundleID: "com.apple.Safari",
            browserURL: nil,
            capturedAt: now
        ))

        let movURL = tempDir.appendingPathComponent("Screen Recording 2026-04-06.mov")
        try! Data(count: 100).write(to: movURL)

        let result = await engine.process(newFile: movURL, detectedAt: now)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.lastPathComponent.contains("safari-recording"), "Expected 'safari-recording', got: \(result!.lastPathComponent)")
    }

    // MARK: - Subfolder Support

    func testSeparateSubfoldersPhoto() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Screenshots", separateSubfolders: true,
            dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertEqual(parentFolder, "images", "Photo should go in /images/ subfolder")
    }

    func testSeparateSubfoldersVideo() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Screenshots", separateSubfolders: true,
            dateFormatter: testDateFormatter()
        )

        let movURL = tempDir.appendingPathComponent("Screen Recording.mov")
        try! Data(count: 100).write(to: movURL)

        let result = await engine.process(newFile: movURL, detectedAt: Date())

        XCTAssertNotNil(result)
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertEqual(parentFolder, "videos", "Video should go in /videos/ subfolder")
    }

    func testNoSubfoldersWhenDisabled() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Screenshots", separateSubfolders: false,
            dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        let comps = relativeComponents(of: result!)
        // Screenshots / YYYY-MM-DD / file.png (no images/ subfolder)
        XCTAssertEqual(comps[0], "Screenshots")
        XCTAssertEqual(comps.count, 3, "Without subfolders, should be 3 components: root/date/file")
    }

    // MARK: - Format Conversion

    func testPhotoFormatJPEG() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Screenshots", dateFormatter: testDateFormatter(),
            photoFormat: .jpeg
        )

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.pathExtension, "jpg", "Should convert to JPEG")
    }

    func testGroupByAppWithSubfolders() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            groupByApp: true, rootFolderName: "Screenshots",
            separateSubfolders: true, dateFormatter: testDateFormatter()
        )

        let now = Date()
        store.store(CaptureContext(
            appName: "Safari",
            appBundleID: "com.apple.Safari",
            browserURL: nil,
            capturedAt: now
        ))

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: now)

        XCTAssertNotNil(result)
        let comps = relativeComponents(of: result!)
        // Screenshots / safari_YYYY-MM-DD / images / test_HH-mm-ss.png
        XCTAssertEqual(comps[0], "Screenshots")
        XCTAssertTrue(comps[1].hasPrefix("safari_"), "Expected safari_ prefix, got: \(comps[1])")
        XCTAssertEqual(comps[2], "images")
    }

    func testProcessManualNonexistentFile() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Screenshots", dateFormatter: testDateFormatter()
        )

        let fakeURL = tempDir.appendingPathComponent("nonexistent.png")
        let result = await engine.processManual(file: fakeURL)

        XCTAssertNil(result)
    }

    // MARK: - File Naming

    func testRenamedFileContainsContentSlug() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "my-cool-screenshot"), store: store,
            rootFolderName: "Screenshots", dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.lastPathComponent.hasPrefix("my-cool-screenshot"))
    }

    func testRenamedFileIsPNG() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Screenshots", dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.pathExtension, "png")
    }

    func testOriginalFileIsMovedNotCopied() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Screenshots", dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let originalPath = testFile.path

        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result!.path))
    }

    // MARK: - Debounce

    func testDebounceSkipsDuplicateFile() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Screenshots", dateFormatter: testDateFormatter()
        )

        let testFile = createTestPNG()
        let now = Date()

        let result1 = await engine.process(newFile: testFile, detectedAt: now)
        XCTAssertNotNil(result1)

        _ = createTestPNG() // same name, recreates the file
        let result2 = await engine.process(newFile: testFile, detectedAt: now)
        XCTAssertNil(result2)
    }

    // MARK: - Collision Handling

    func testCollisionHandling() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "same-name"), store: store,
            rootFolderName: "Screenshots", dateFormatter: testDateFormatter()
        )

        let file1 = createTestPNG(named: "Screenshot 1.png")
        let result1 = await engine.process(newFile: file1, detectedAt: Date())
        XCTAssertNotNil(result1)

        try? await Task.sleep(nanoseconds: 3_500_000_000)

        let file2 = createTestPNG(named: "Screenshot 2.png")
        let result2 = await engine.process(newFile: file2, detectedAt: Date())
        XCTAssertNotNil(result2)

        XCTAssertNotEqual(result1!.path, result2!.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result1!.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result2!.path))
    }

    // MARK: - Date Format

    func testLocaleDateFormatUsedInFolderName() async {
        let store = CaptureContextStore()
        let frenchFormatter = DateFormatter()
        frenchFormatter.dateFormat = "dd-MM-yyyy"
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Screenshots", dateFormatter: frenchFormatter
        )

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        let comps = relativeComponents(of: result!)
        // The date folder should be in dd-MM-yyyy format
        let dateFolder = comps[1]
        let parts = dateFolder.components(separatedBy: "-")
        XCTAssertEqual(parts.count, 3, "Date should have 3 parts: \(dateFolder)")
        // dd should be 01-31, MM should be 01-12
        XCTAssertTrue((Int(parts[0]) ?? 0) <= 31, "First part should be day")
    }

    func testSlashesInDateFormatAreSanitized() async {
        let store = CaptureContextStore()
        let slashFormatter = DateFormatter()
        slashFormatter.dateFormat = "MM/dd/yyyy"
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Screenshots", dateFormatter: slashFormatter
        )

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        let comps = relativeComponents(of: result!)
        let dateFolder = comps[1]
        XCTAssertFalse(dateFolder.contains("/"), "Slashes should be replaced with hyphens: \(dateFolder)")
        XCTAssertTrue(dateFolder.contains("-"), "Should contain hyphens: \(dateFolder)")
    }

    // MARK: - Localized Subfolder Names

    func testLocalizedSubfolderNames() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(
            namer: MockNamer(slug: "test"), store: store,
            rootFolderName: "Captures d\u{2019}\u{00E9}cran",
            separateSubfolders: true,
            imagesFolderName: "images",
            videosFolderName: "vid\u{00E9}os",
            dateFormatter: testDateFormatter()
        )

        let movURL = tempDir.appendingPathComponent("Screen Recording.mov")
        try! Data(count: 100).write(to: movURL)

        let result = await engine.process(newFile: movURL, detectedAt: Date())

        XCTAssertNotNil(result)
        let comps = relativeComponents(of: result!)
        XCTAssertEqual(comps[0], "Captures d\u{2019}\u{00E9}cran")
        XCTAssertEqual(comps[2], "vid\u{00E9}os")
    }
}
