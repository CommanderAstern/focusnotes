import Foundation
import IOKit.ps
import os

@MainActor
final class PowerMonitor {
    private let onImagesAllowed: @MainActor () -> Void
    private let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "power")
    private var wasAllowed: Bool
    private var powerSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var stopped = false

    init(onImagesAllowed: @escaping @MainActor () -> Void) {
        self.onImagesAllowed = onImagesAllowed
        self.wasAllowed = SemanticIndexer.imagesAllowed

        if let source = IOPSNotificationCreateRunLoopSource(
            powerSourceChanged,
            Unmanaged.passUnretained(self).toOpaque()
        )?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        } else {
            logger.error("Could not monitor power source changes")
        }

        let center = NotificationCenter.default
        for name in [ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
            self.powerSource = nil
        }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    private func refresh() {
        guard !stopped else { return }
        let isAllowed = SemanticIndexer.imagesAllowed
        let resumed = !wasAllowed && isAllowed
        wasAllowed = isAllowed
        if resumed { onImagesAllowed() }
    }

    fileprivate func powerSourceDidChange() {
        refresh()
    }
}

private func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor [weak monitor] in monitor?.powerSourceDidChange() }
}
