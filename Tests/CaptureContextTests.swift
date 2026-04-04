import XCTest
@testable import SmartScreenShotCore

final class CaptureContextTests: XCTestCase {

    func testEmptyContextHasEmptyFields() {
        let empty = CaptureContext.empty
        XCTAssertTrue(empty.appName.isEmpty)
        XCTAssertTrue(empty.appBundleID.isEmpty)
        XCTAssertNil(empty.browserURL)
    }

    func testContextInitialization() {
        let now = Date()
        let url = URL(string: "https://example.com")!
        let ctx = CaptureContext(
            appName: "Safari",
            appBundleID: "com.apple.Safari",
            browserURL: url,
            capturedAt: now
        )
        XCTAssertEqual(ctx.appName, "Safari")
        XCTAssertEqual(ctx.appBundleID, "com.apple.Safari")
        XCTAssertEqual(ctx.browserURL, url)
        XCTAssertEqual(ctx.capturedAt, now)
    }

    func testContextWithNilBrowserURL() {
        let ctx = CaptureContext(
            appName: "Xcode",
            appBundleID: "com.apple.dt.Xcode",
            browserURL: nil,
            capturedAt: Date()
        )
        XCTAssertNil(ctx.browserURL)
    }
}
