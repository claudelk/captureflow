import XCTest
@testable import SmartScreenShotCore

/// A mock namer that returns a predictable slug.
private struct MockNamer: ImageNamer {
    let slug: String
    func name(image: CGImage, context: CaptureContext) async throws -> String {
        return slug
    }
}

final class RenameEngineTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("smartscreenshot-tests-\(UUID().uuidString)")
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

    // MARK: - groupByApp Flag

    func testGroupByAppFalseUsesScreenshotFolder() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "test-content"), store: store, groupByApp: false)

        // Store a context with an app name
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
        // Folder should be "screenshot_YYYY-MM-DD", NOT "safari_YYYY-MM-DD"
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertTrue(parentFolder.hasPrefix("screenshot_"), "Expected 'screenshot_' prefix, got: \(parentFolder)")
        XCTAssertFalse(parentFolder.hasPrefix("safari_"), "Should NOT use app name when groupByApp is false")
    }

    func testGroupByAppTrueUsesAppFolder() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "test-content"), store: store, groupByApp: true)

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
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertTrue(parentFolder.hasPrefix("safari_"), "Expected 'safari_' prefix, got: \(parentFolder)")
    }

    func testGroupByAppTrueWithEmptyContextUsesScreenshot() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "test-content"), store: store, groupByApp: true)

        // No context stored — will use .empty
        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertTrue(parentFolder.hasPrefix("screenshot_"), "Empty context should default to 'screenshot_'")
    }

    func testGroupByAppDefaultIsFalse() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "test-content"), store: store)

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
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertTrue(parentFolder.hasPrefix("screenshot_"), "Default groupByApp should be false")
    }

    // MARK: - processManual

    func testProcessManualAlwaysUsesScreenshotFolder() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "manual-test"), store: store, groupByApp: true)

        let testFile = createTestPNG()
        let result = await engine.processManual(file: testFile)

        XCTAssertNotNil(result)
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertTrue(parentFolder.hasPrefix("screenshot_"), "processManual should always use 'screenshot_'")
    }

    func testCustomFolderPrefix() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "test"), store: store, folderPrefix: "capture-d-ecran")

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertTrue(parentFolder.hasPrefix("capture-d-ecran_"), "Expected 'capture-d-ecran_' prefix, got: \(parentFolder)")
    }

    func testProcessManualUsesCustomPrefix() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "test"), store: store, folderPrefix: "mes-captures")

        let testFile = createTestPNG()
        let result = await engine.processManual(file: testFile)

        XCTAssertNotNil(result)
        let parentFolder = result!.deletingLastPathComponent().lastPathComponent
        XCTAssertTrue(parentFolder.hasPrefix("mes-captures_"), "Expected 'mes-captures_' prefix, got: \(parentFolder)")
    }

    func testProcessManualNonexistentFile() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "test"), store: store)

        let fakeURL = tempDir.appendingPathComponent("nonexistent.png")
        let result = await engine.processManual(file: fakeURL)

        XCTAssertNil(result)
    }

    // MARK: - File Naming

    func testRenamedFileContainsContentSlug() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "my-cool-screenshot"), store: store)

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.lastPathComponent.hasPrefix("my-cool-screenshot"))
    }

    func testRenamedFileIsPNG() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "test"), store: store)

        let testFile = createTestPNG()
        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.pathExtension, "png")
    }

    func testOriginalFileIsMovedNotCopied() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "test"), store: store)

        let testFile = createTestPNG()
        let originalPath = testFile.path

        let result = await engine.process(newFile: testFile, detectedAt: Date())

        XCTAssertNotNil(result)
        // Original file should no longer exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalPath))
        // Destination should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: result!.path))
    }

    // MARK: - Debounce

    func testDebounceSkipsDuplicateFile() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "test"), store: store)

        let testFile = createTestPNG()
        let now = Date()

        // First call succeeds
        let result1 = await engine.process(newFile: testFile, detectedAt: now)
        XCTAssertNotNil(result1)

        // Create another file at the same path (simulating double FSEvents)
        _ = createTestPNG() // same name, recreates the file
        let result2 = await engine.process(newFile: testFile, detectedAt: now)
        // Should be nil — debounced
        XCTAssertNil(result2)
    }

    // MARK: - Collision Handling

    func testCollisionHandling() async {
        let store = CaptureContextStore()
        let engine = RenameEngine(namer: MockNamer(slug: "same-name"), store: store)

        // Process two different files that produce the same slug
        let file1 = createTestPNG(named: "Screenshot 1.png")
        let result1 = await engine.process(newFile: file1, detectedAt: Date())
        XCTAssertNotNil(result1)

        // Wait past the debounce window
        try? await Task.sleep(nanoseconds: 3_500_000_000)

        let file2 = createTestPNG(named: "Screenshot 2.png")
        let result2 = await engine.process(newFile: file2, detectedAt: Date())
        XCTAssertNotNil(result2)

        // Both should exist at different paths
        XCTAssertNotEqual(result1!.path, result2!.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result1!.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result2!.path))
    }
}
