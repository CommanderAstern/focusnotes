import AppKit
// The C header declares the immutable AX prompt key as a mutable global.
@preconcurrency import ApplicationServices
import CoreGraphics

public enum CapturePermission: Sendable {
    case accessibility
    case screenCapture
}

@MainActor
public enum CapturePermissions {
    public static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    public static func promptForAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static var screenCaptureAllowed: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    public static func requestScreenCapture() -> Bool { CGRequestScreenCaptureAccess() }

    /// Explicit user action only: opening Settings intentionally changes the frontmost app.
    @discardableResult
    public static func openSettings(for permission: CapturePermission) -> Bool {
        let pane: String
        switch permission {
        case .accessibility: pane = "Privacy_Accessibility"
        case .screenCapture: pane = "Privacy_ScreenCapture"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return false }
        return NSWorkspace.shared.open(url)
    }
}
