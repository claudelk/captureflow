import XCTest
@testable import SmartScreenShotCore

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
}
