import XCTest
@testable import CaptureFlowCore

final class MigrationEngineTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("captureflow-migration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func createFile(named name: String, content: Data = Data(count: 100)) {
        try! content.write(to: tempDir.appendingPathComponent(name))
    }

    private func createFolder(named name: String) {
        try! FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(name),
            withIntermediateDirectories: true
        )
    }

    private func testDateFormatter() -> DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }

    // MARK: - Scan

    func testScanFindsAppleDefaultPNGs() {
        createFile(named: "Screenshot 2026-04-05 at 1.30.45 PM.png")
        createFile(named: "Screenshot 2026-04-06 at 2.15.00 PM.png")
        createFile(named: "random-file.png") // Should NOT be found

        let result = MigrationEngine.scan(in: tempDir, rootFolderName: "Screenshots")
        XCTAssertEqual(result.fileCount, 2)
    }

    func testScanFindsAppleDefaultMOVs() {
        createFile(named: "Screen Recording 2026-04-05 at 1.30.45 PM.mov")

        let result = MigrationEngine.scan(in: tempDir, rootFolderName: "Screenshots")
        XCTAssertEqual(result.fileCount, 1)
    }

    func testScanFindsFrenchScreenshots() {
        createFile(named: "Capture d\u{2019}\u{00E9}cran 2026-04-05 \u{00E0} 13.30.45.png")

        let result = MigrationEngine.scan(in: tempDir, rootFolderName: "Screenshots")
        XCTAssertEqual(result.fileCount, 1)
    }

    func testScanFindsExistingDailyFolders() {
        createFolder(named: "screenshot_2026-04-05")
        createFolder(named: "screenshot_2026-04-06")
        createFolder(named: "capture-d-ecran_2026-04-07")
        createFolder(named: "random-folder") // Should NOT be found

        let result = MigrationEngine.scan(in: tempDir, rootFolderName: "Screenshots")
        XCTAssertEqual(result.folderCount, 3)
    }

    func testScanIgnoresFilesInsideRootFolder() {
        createFolder(named: "Screenshots")
        let rootFolder = tempDir.appendingPathComponent("Screenshots")
        try! Data(count: 100).write(to: rootFolder.appendingPathComponent("Screenshot 2026-04-05 at 1.00.00 PM.png"))

        // Also create a file at the top level that should be found
        createFile(named: "Screenshot 2026-04-06 at 2.00.00 PM.png")

        let result = MigrationEngine.scan(in: tempDir, rootFolderName: "Screenshots")
        XCTAssertEqual(result.fileCount, 1, "Should only find the top-level file, not the one inside Screenshots/")
    }

    // MARK: - Extract Date

    func testExtractDateFromAppleFilename() {
        let date = MigrationEngine.extractDate(from: "Screenshot 2026-04-05 at 1.30.45 PM.png")
        XCTAssertNotNil(date)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 5)
    }

    func testExtractDateFromFrenchFilename() {
        let date = MigrationEngine.extractDate(from: "Capture d\u{2019}\u{00E9}cran 2026-04-07 \u{00E0} 13.30.45.png")
        XCTAssertNotNil(date)
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 7)
    }

    func testExtractDateReturnsNilForUnknownFormat() {
        let date = MigrationEngine.extractDate(from: "random-file.png")
        XCTAssertNil(date)
    }

    // MARK: - Run Migration

    func testMigrationMovesFilesIntoCorrectDateFolder() async {
        createFile(named: "Screenshot 2026-04-05 at 1.30.45 PM.png")

        let scanResult = MigrationEngine.scan(in: tempDir, rootFolderName: "Screenshots")
        _ = await MigrationEngine.run(
            scanResult: scanResult,
            screenshotFolder: tempDir,
            rootFolderName: "Screenshots",
            dateFormatter: testDateFormatter(),
            separateSubfolders: false,
            imagesFolderName: "images",
            videosFolderName: "videos",
            namer: nil,
            progress: { _, _ in }
        )

        // Check the file landed in Screenshots/2026-04-05/
        let dateFolder = tempDir.appendingPathComponent("Screenshots/2026-04-05")
        let contents = try? FileManager.default.contentsOfDirectory(at: dateFolder, includingPropertiesForKeys: nil)
        XCTAssertNotNil(contents)
        XCTAssertFalse(contents!.isEmpty, "File should be in Screenshots/2026-04-05/")

        // Original should be gone
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("Screenshot 2026-04-05 at 1.30.45 PM.png").path
        ))
    }

    func testMigrationSplitsPhotosAndVideos() async {
        createFile(named: "Screenshot 2026-04-05 at 1.30.45 PM.png")
        createFile(named: "Screen Recording 2026-04-05 at 2.00.00 PM.mov")

        let scanResult = MigrationEngine.scan(in: tempDir, rootFolderName: "Screenshots")
        _ = await MigrationEngine.run(
            scanResult: scanResult,
            screenshotFolder: tempDir,
            rootFolderName: "Screenshots",
            dateFormatter: testDateFormatter(),
            separateSubfolders: true,
            imagesFolderName: "images",
            videosFolderName: "videos",
            namer: nil,
            progress: { _, _ in }
        )

        let imagesFolder = tempDir.appendingPathComponent("Screenshots/2026-04-05/images")
        let videosFolder = tempDir.appendingPathComponent("Screenshots/2026-04-05/videos")
        let imageContents = try? FileManager.default.contentsOfDirectory(at: imagesFolder, includingPropertiesForKeys: nil)
        let videoContents = try? FileManager.default.contentsOfDirectory(at: videosFolder, includingPropertiesForKeys: nil)
        XCTAssertEqual(imageContents?.count, 1, "One PNG should be in images/")
        XCTAssertEqual(videoContents?.count, 1, "One MOV should be in videos/")
    }

    func testMigrationMovesExistingFoldersIntoRoot() async {
        createFolder(named: "screenshot_2026-04-05")
        let oldFolder = tempDir.appendingPathComponent("screenshot_2026-04-05")
        try! Data(count: 100).write(to: oldFolder.appendingPathComponent("test.png"))

        let scanResult = MigrationEngine.scan(in: tempDir, rootFolderName: "Screenshots")
        _ = await MigrationEngine.run(
            scanResult: scanResult,
            screenshotFolder: tempDir,
            rootFolderName: "Screenshots",
            dateFormatter: testDateFormatter(),
            separateSubfolders: false,
            imagesFolderName: "images",
            videosFolderName: "videos",
            namer: nil,
            progress: { _, _ in }
        )

        // Old folder should be gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFolder.path))
        // New folder should exist
        let newFolder = tempDir.appendingPathComponent("Screenshots/2026-04-05")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFolder.path))
    }

    func testMigrationRetroactivelySplitsSubfolders() async {
        createFolder(named: "screenshot_2026-04-05")
        let oldFolder = tempDir.appendingPathComponent("screenshot_2026-04-05")
        try! Data(count: 100).write(to: oldFolder.appendingPathComponent("test.png"))
        try! Data(count: 100).write(to: oldFolder.appendingPathComponent("recording.mov"))

        let scanResult = MigrationEngine.scan(in: tempDir, rootFolderName: "Screenshots")
        _ = await MigrationEngine.run(
            scanResult: scanResult,
            screenshotFolder: tempDir,
            rootFolderName: "Screenshots",
            dateFormatter: testDateFormatter(),
            separateSubfolders: true,
            imagesFolderName: "images",
            videosFolderName: "videos",
            namer: nil,
            progress: { _, _ in }
        )

        let imagesFolder = tempDir.appendingPathComponent("Screenshots/2026-04-05/images")
        let videosFolder = tempDir.appendingPathComponent("Screenshots/2026-04-05/videos")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesFolder.appendingPathComponent("test.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: videosFolder.appendingPathComponent("recording.mov").path))
    }

    func testMigrationHandlesMultipleLocalePrefixes() async {
        createFolder(named: "screenshot_2026-04-05")
        createFolder(named: "capture-d-ecran_2026-04-06")

        let scanResult = MigrationEngine.scan(in: tempDir, rootFolderName: "Screenshots")
        XCTAssertEqual(scanResult.folderCount, 2)

        _ = await MigrationEngine.run(
            scanResult: scanResult,
            screenshotFolder: tempDir,
            rootFolderName: "Screenshots",
            dateFormatter: testDateFormatter(),
            separateSubfolders: false,
            imagesFolderName: "images",
            videosFolderName: "videos",
            namer: nil,
            progress: { _, _ in }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Screenshots/2026-04-05").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Screenshots/2026-04-06").path))
    }
}
