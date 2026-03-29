import Foundation

/// Thread-safe ring buffer of CaptureContext snapshots.
///
/// Uses `NSLock` instead of `actor` so the CGEventTap callback can store
/// contexts **synchronously** from the main thread — eliminating the race
/// condition where an async `store()` hasn't completed by the time the
/// rename engine calls `nearest()`.
public final class CaptureContextStore: @unchecked Sendable {

    private struct Entry {
        let context: CaptureContext
        let storedAt: Date
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let expiryInterval: TimeInterval

    public init(expiryInterval: TimeInterval = 10) {
        self.expiryInterval = expiryInterval
    }

    /// Store a newly captured context. Prunes stale entries first.
    /// Safe to call synchronously from any thread (including C callbacks).
    public func store(_ context: CaptureContext) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        entries.removeAll { now.timeIntervalSince($0.storedAt) > expiryInterval }
        entries.append(Entry(context: context, storedAt: now))
    }

    /// Returns the context whose `capturedAt` is closest to `date`,
    /// provided the difference is within `window` seconds. Returns nil if no match.
    public func nearest(to date: Date, within window: TimeInterval = 5) -> CaptureContext? {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        return entries
            .filter { now.timeIntervalSince($0.storedAt) <= expiryInterval }
            .map { $0.context }
            .filter { abs($0.capturedAt.timeIntervalSince(date)) <= window }
            .min { abs($0.capturedAt.timeIntervalSince(date)) < abs($1.capturedAt.timeIntervalSince(date)) }
    }
}
