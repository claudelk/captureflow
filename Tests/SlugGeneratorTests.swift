import XCTest
@testable import SmartScreenShotCore

final class SlugGeneratorTests: XCTestCase {

    // MARK: - slug(from:)

    func testBasicSlug() {
        XCTAssertEqual(SlugGenerator.slug(from: "Hello World"), "hello-world")
    }

    func testSlugRemovesSpecialCharacters() {
        XCTAssertEqual(
            SlugGenerator.slug(from: "Welcome to Settings — General"),
            "welcome-to-settings-general"
        )
    }

    func testSlugHandlesMultipleSpaces() {
        XCTAssertEqual(SlugGenerator.slug(from: "hello   world"), "hello-world")
    }

    func testSlugHandlesLeadingTrailingSpaces() {
        XCTAssertEqual(SlugGenerator.slug(from: "  hello world  "), "hello-world")
    }

    func testSlugHandlesNumbers() {
        XCTAssertEqual(SlugGenerator.slug(from: "Page 42 of 100"), "page-42-of-100")
    }

    func testSlugHandlesAllCaps() {
        XCTAssertEqual(SlugGenerator.slug(from: "HELLO WORLD"), "hello-world")
    }

    func testSlugHandlesMixedCase() {
        XCTAssertEqual(SlugGenerator.slug(from: "MacOS Ventura Settings"), "macos-ventura-settings")
    }

    func testSlugEmptyStringReturnsUntitled() {
        XCTAssertEqual(SlugGenerator.slug(from: ""), "untitled")
    }

    func testSlugOnlySpecialCharsReturnsUntitled() {
        XCTAssertEqual(SlugGenerator.slug(from: "!@#$%"), "untitled")
    }

    func testSlugTruncatesAtWordBoundary() {
        let long = "this is a very long string that should be truncated at a word boundary"
        let result = SlugGenerator.slug(from: long, maxLength: 30)
        XCTAssertLessThanOrEqual(result.count, 30)
        XCTAssertFalse(result.hasSuffix("-"))
    }

    func testSlugExactMaxLength() {
        let result = SlugGenerator.slug(from: "short", maxLength: 50)
        XCTAssertEqual(result, "short")
    }

    func testSlugCustomMaxLength() {
        // "hello-world-foo-bar" is 19 chars
        // maxLength 11 → prefix "hello-world" → last hyphen at 5 → "hello"
        let result = SlugGenerator.slug(from: "hello world foo bar", maxLength: 11)
        XCTAssertEqual(result, "hello")
        // maxLength 15 → prefix "hello-world-foo" → last hyphen at 11 → "hello-world"
        let result2 = SlugGenerator.slug(from: "hello world foo bar", maxLength: 15)
        XCTAssertEqual(result2, "hello-world")
        // maxLength 19 → full string fits
        let result3 = SlugGenerator.slug(from: "hello world foo bar", maxLength: 19)
        XCTAssertEqual(result3, "hello-world-foo-bar")
    }

    func testSlugUnicodeCharacters() {
        XCTAssertEqual(SlugGenerator.slug(from: "café résumé"), "caf-r-sum")
    }

    func testSlugCollapseMultipleHyphens() {
        XCTAssertEqual(SlugGenerator.slug(from: "hello---world"), "hello-world")
    }

    func testSlugAppNames() {
        XCTAssertEqual(SlugGenerator.slug(from: "Safari"), "safari")
        XCTAssertEqual(SlugGenerator.slug(from: "Visual Studio Code"), "visual-studio-code")
        XCTAssertEqual(SlugGenerator.slug(from: "Google Chrome"), "google-chrome")
        XCTAssertEqual(SlugGenerator.slug(from: "Xcode"), "xcode")
    }

    // MARK: - meaningScore(for:)

    func testMeaningScoreShortStringIsLow() {
        XCTAssertEqual(SlugGenerator.meaningScore(for: "OK"), 0)
        XCTAssertEqual(SlugGenerator.meaningScore(for: "Hi"), 0)
    }

    func testMeaningScoreEmptyStringIsZero() {
        XCTAssertEqual(SlugGenerator.meaningScore(for: ""), 0)
    }

    func testMeaningScoreNormalTextIsPositive() {
        let score = SlugGenerator.meaningScore(for: "Welcome to Safari Settings")
        XCTAssertGreaterThan(score, 0)
    }

    func testMeaningScoreAllCapsIsPenalized() {
        let normalScore = SlugGenerator.meaningScore(for: "Settings General")
        let capsScore = SlugGenerator.meaningScore(for: "SETTINGS GENERAL")
        XCTAssertGreaterThan(normalScore, capsScore)
    }

    func testMeaningScoreShortStringIsPenalized() {
        let shortScore = SlugGenerator.meaningScore(for: "File")
        let longScore = SlugGenerator.meaningScore(for: "File Manager Settings")
        XCTAssertGreaterThan(longScore, shortScore)
    }

    func testMeaningScoreLowAlphaRatioPenalized() {
        let alphaScore = SlugGenerator.meaningScore(for: "Hello World")
        let numScore = SlugGenerator.meaningScore(for: "12345 67890 abc")
        XCTAssertGreaterThan(alphaScore, numScore)
    }

    func testMeaningScoreTimestampLike() {
        let score = SlugGenerator.meaningScore(for: "2026-03-29 14:30:00")
        XCTAssertLessThan(score, SlugGenerator.meaningScore(for: "Safari Browser Window"))
    }
}
