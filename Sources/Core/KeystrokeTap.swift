import AppKit
import CoreGraphics
import Foundation

/// Listens for macOS screenshot keystrokes (Cmd+Shift+3/4/5) via a passive CGEventTap.
/// At each matching keystroke, snapshots the frontmost app and stores a CaptureContext.
///
/// Requires Accessibility permission: System Settings › Privacy & Security › Accessibility.
public final class KeystrokeTap {

    public enum TapError: Error, LocalizedError {
        case accessibilityNotGranted
        case failedToCreateTap

        public var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                return "Accessibility permission required — enable it in System Settings › Privacy & Security › Accessibility, then restart."
            case .failedToCreateTap:
                return "CGEventTapCreate returned nil — Accessibility permission may not be granted."
            }
        }
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let store: CaptureContextStore

    public init(store: CaptureContextStore) {
        self.store = store
    }

    deinit { stop() }

    // MARK: - Public

    public func start() throws {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                Unmanaged<KeystrokeTap>.fromOpaque(refcon)
                    .takeUnretainedValue()
                    .handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            throw AXIsProcessTrusted() ? TapError.failedToCreateTap : TapError.accessibilityNotGranted
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[KeystrokeTap] started — listening for Cmd+Shift+3/4/5")
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    // MARK: - Private

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard type == .keyDown else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags   = event.flags
        guard flags.contains(.maskCommand), flags.contains(.maskShift) else { return }

        // Screenshot key codes (standard US layout):
        //   Cmd+Shift+3  →  keyCode 20
        //   Cmd+Shift+4  →  keyCode 21
        //   Cmd+Shift+5  →  keyCode 23
        guard keyCode == 20 || keyCode == 21 || keyCode == 23 else { return }

        // Capture frontmost app immediately on this (main) thread — before focus shifts
        let app      = NSWorkspace.shared.frontmostApplication
        let appName  = app?.localizedName  ?? "screenshot"
        let bundleID = app?.bundleIdentifier ?? ""
        let now      = Date()

        print("[KeystrokeTap] screenshot keystroke — app: \(appName)")

        // Store synchronously — CaptureContextStore is lock-based, not an actor,
        // so this completes before the CGEventTap callback returns.
        store.store(CaptureContext(
            appName:     appName,
            appBundleID: bundleID,
            browserURL:  nil,       // browser URL capture: planned for Step 3
            capturedAt:  now
        ))
    }
}
