import XCTest
@testable import CaptureFlowCore

final class FolderPrefixTests: XCTestCase {

    func testEnglishPrefix() {
        XCTAssertEqual(FolderPrefix.prefix(for: "en"), "screenshot")
    }

    func testFrenchPrefix() {
        XCTAssertEqual(FolderPrefix.prefix(for: "fr"), "capture-d-ecran")
    }

    func testSpanishPrefix() {
        XCTAssertEqual(FolderPrefix.prefix(for: "es"), "captura-de-pantalla")
    }

    func testPortuguesePrefix() {
        XCTAssertEqual(FolderPrefix.prefix(for: "pt"), "captura-de-tela")
    }

    func testSwahiliPrefix() {
        XCTAssertEqual(FolderPrefix.prefix(for: "sw"), "picha-ya-skrini")
    }

    func testUnknownLanguageFallsBackToEnglish() {
        XCTAssertEqual(FolderPrefix.prefix(for: "de"), "screenshot")
        XCTAssertEqual(FolderPrefix.prefix(for: "ja"), "screenshot")
        XCTAssertEqual(FolderPrefix.prefix(for: "zh"), "screenshot")
        XCTAssertEqual(FolderPrefix.prefix(for: ""), "screenshot")
    }

    func testPrefixesAreValidSlugs() {
        let codes = ["en", "fr", "es", "pt", "sw"]
        for code in codes {
            let prefix = FolderPrefix.prefix(for: code)
            // Should be lowercase, no spaces, no special chars besides hyphens
            XCTAssertEqual(prefix, prefix.lowercased(), "Prefix for \(code) should be lowercase")
            XCTAssertFalse(prefix.contains(" "), "Prefix for \(code) should not contain spaces")
            XCTAssertFalse(prefix.isEmpty, "Prefix for \(code) should not be empty")
            // Should only contain a-z, 0-9, and hyphens
            let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "-"))
            XCTAssertTrue(prefix.unicodeScalars.allSatisfy { allowed.contains($0) },
                          "Prefix for \(code) contains invalid characters: \(prefix)")
        }
    }

    // MARK: - Root Folder Names

    func testEnglishRootFolderName() {
        XCTAssertEqual(FolderPrefix.rootFolderName(for: "en"), "Screenshots")
    }

    func testFrenchRootFolderName() {
        XCTAssertEqual(FolderPrefix.rootFolderName(for: "fr"), "Captures d\u{2019}\u{00E9}cran")
    }

    func testSpanishRootFolderName() {
        XCTAssertEqual(FolderPrefix.rootFolderName(for: "es"), "Capturas de pantalla")
    }

    func testPortugueseRootFolderName() {
        XCTAssertEqual(FolderPrefix.rootFolderName(for: "pt"), "Capturas de tela")
    }

    func testSwahiliRootFolderName() {
        XCTAssertEqual(FolderPrefix.rootFolderName(for: "sw"), "Picha za skrini")
    }

    func testUnknownLanguageRootFolderFallsBack() {
        XCTAssertEqual(FolderPrefix.rootFolderName(for: "de"), "Screenshots")
        XCTAssertEqual(FolderPrefix.rootFolderName(for: ""), "Screenshots")
    }

    func testRootFolderNamesAreNonEmpty() {
        let codes = ["en", "fr", "es", "pt", "sw"]
        for code in codes {
            let name = FolderPrefix.rootFolderName(for: code)
            XCTAssertFalse(name.isEmpty, "Root folder name for \(code) should not be empty")
        }
    }

    // MARK: - Subfolder Names

    func testEnglishSubfolderNames() {
        XCTAssertEqual(FolderPrefix.imagesFolderName(for: "en"), "images")
        XCTAssertEqual(FolderPrefix.videosFolderName(for: "en"), "videos")
    }

    func testFrenchSubfolderNames() {
        XCTAssertEqual(FolderPrefix.imagesFolderName(for: "fr"), "images")
        XCTAssertEqual(FolderPrefix.videosFolderName(for: "fr"), "vid\u{00E9}os")
    }

    func testSpanishSubfolderNames() {
        XCTAssertEqual(FolderPrefix.imagesFolderName(for: "es"), "im\u{00E1}genes")
        XCTAssertEqual(FolderPrefix.videosFolderName(for: "es"), "v\u{00ED}deos")
    }

    func testUnknownLanguageSubfolderFallsBack() {
        XCTAssertEqual(FolderPrefix.imagesFolderName(for: "de"), "images")
        XCTAssertEqual(FolderPrefix.videosFolderName(for: "de"), "videos")
    }
}
