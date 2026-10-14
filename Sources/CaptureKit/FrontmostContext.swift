import AppKit
import ApplicationServices

public struct FrontmostContext: Equatable, Sendable {
    public let appName: String?
    public let bundleIdentifier: String?
    public let processIdentifier: pid_t
    public let windowTitle: String?

    public init(appName: String?, bundleIdentifier: String?, processIdentifier: pid_t, windowTitle: String?) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.windowTitle = windowTitle
    }

    /// Call synchronously at hotkey entry, before scheduling capture work or opening any UI.
    /// A zero PID means that macOS did not report a frontmost application.
    @MainActor
    public static func capture() -> Self {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return Self(appName: nil, bundleIdentifier: nil, processIdentifier: 0, windowTitle: nil)
        }
        var title: String?
        if AXIsProcessTrusted() {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.2)
            var window: CFTypeRef?
            if AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &window) == .success,
               let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
                let element = unsafeDowncast(window, to: AXUIElement.self)
                AXUIElementSetMessagingTimeout(element, 0.2)
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success {
                    title = value as? String
                }
            }
        }
        return Self(appName: app.localizedName, bundleIdentifier: app.bundleIdentifier,
                    processIdentifier: app.processIdentifier, windowTitle: title)
    }
}
