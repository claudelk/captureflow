import XCTest
@testable import SmartScreenShotCore

final class CaptureContextStoreTests: XCTestCase {

    // MARK: - Basic Store/Retrieve

    func testStoreAndRetrieve() {
        let store = CaptureContextStore()
        let now = Date()
        let ctx = CaptureContext(
            appName: "Safari",
            appBundleID: "com.apple.Safari",
            browserURL: nil,
            capturedAt: now
        )
        store.store(ctx)
        XCTAssertEqual(store.count, 1)

        let matched = store.nearest(to: now)
        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.appName, "Safari")
    }

    func testNearestConsumesEntry() {
        let store = CaptureContextStore()
        let now = Date()
        let ctx = CaptureContext(
            appName: "Safari",
            appBundleID: "com.apple.Safari",
            browserURL: nil,
            capturedAt: now
        )
        store.store(ctx)

        // First call consumes it
        let first = store.nearest(to: now)
        XCTAssertNotNil(first)

        // Second call returns nil — entry was consumed
        let second = store.nearest(to: now)
        XCTAssertNil(second)
    }

    func testEmptyStoreReturnsNil() {
        let store = CaptureContextStore()
        XCTAssertNil(store.nearest(to: Date()))
    }

    func testCountAfterStore() {
        let store = CaptureContextStore()
        XCTAssertEqual(store.count, 0)

        store.store(CaptureContext(
            appName: "A", appBundleID: "", browserURL: nil, capturedAt: Date()
        ))
        XCTAssertEqual(store.count, 1)

        store.store(CaptureContext(
            appName: "B", appBundleID: "", browserURL: nil, capturedAt: Date()
        ))
        XCTAssertEqual(store.count, 2)
    }

    // MARK: - Nearest Matching

    func testNearestFindsClosest() {
        let store = CaptureContextStore()
        let base = Date()

        let ctx1 = CaptureContext(
            appName: "App1",
            appBundleID: "",
            browserURL: nil,
            capturedAt: base.addingTimeInterval(-10)
        )
        let ctx2 = CaptureContext(
            appName: "App2",
            appBundleID: "",
            browserURL: nil,
            capturedAt: base.addingTimeInterval(-2)
        )
        let ctx3 = CaptureContext(
            appName: "App3",
            appBundleID: "",
            browserURL: nil,
            capturedAt: base.addingTimeInterval(-20)
        )

        store.store(ctx1)
        store.store(ctx2)
        store.store(ctx3)

        // Nearest to `base` should be ctx2 (2s ago)
        let matched = store.nearest(to: base)
        XCTAssertEqual(matched?.appName, "App2")
    }

    func testNearestOutsideWindowReturnsNil() {
        let store = CaptureContextStore()
        let now = Date()
        let ctx = CaptureContext(
            appName: "OldApp",
            appBundleID: "",
            browserURL: nil,
            capturedAt: now.addingTimeInterval(-120) // 2 minutes ago
        )
        store.store(ctx)

        // Default window is 60s — 120s ago should not match
        let matched = store.nearest(to: now)
        XCTAssertNil(matched)
    }

    func testNearestCustomWindow() {
        let store = CaptureContextStore()
        let now = Date()
        let ctx = CaptureContext(
            appName: "App",
            appBundleID: "",
            browserURL: nil,
            capturedAt: now.addingTimeInterval(-5)
        )
        store.store(ctx)

        // 3s window should not match 5s ago
        XCTAssertNil(store.nearest(to: now, within: 3))
    }

    func testNearestCustomWindowMatches() {
        let store = CaptureContextStore()
        let now = Date()
        let ctx = CaptureContext(
            appName: "App",
            appBundleID: "",
            browserURL: nil,
            capturedAt: now.addingTimeInterval(-5)
        )
        store.store(ctx)

        // 10s window should match 5s ago
        let matched = store.nearest(to: now, within: 10)
        XCTAssertNotNil(matched)
    }

    // MARK: - Expiry

    func testExpiredEntriesPruned() {
        // 1s expiry for fast testing
        let store = CaptureContextStore(expiryInterval: 1)
        let ctx = CaptureContext(
            appName: "Old",
            appBundleID: "",
            browserURL: nil,
            capturedAt: Date()
        )
        store.store(ctx)
        XCTAssertEqual(store.count, 1)

        // Wait for expiry
        Thread.sleep(forTimeInterval: 1.5)

        // Storing a new entry should prune the expired one
        store.store(CaptureContext(
            appName: "New",
            appBundleID: "",
            browserURL: nil,
            capturedAt: Date()
        ))
        XCTAssertEqual(store.count, 1)
    }

    // MARK: - Thread Safety

    func testConcurrentAccess() {
        let store = CaptureContextStore()
        let iterations = 100
        let expectation = XCTestExpectation(description: "concurrent access")
        expectation.expectedFulfillmentCount = iterations * 2

        for i in 0..<iterations {
            DispatchQueue.global().async {
                store.store(CaptureContext(
                    appName: "App\(i)",
                    appBundleID: "",
                    browserURL: nil,
                    capturedAt: Date()
                ))
                expectation.fulfill()
            }
            DispatchQueue.global().async {
                _ = store.nearest(to: Date())
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5)
        // If we get here without crashing, thread safety is working
    }
}
