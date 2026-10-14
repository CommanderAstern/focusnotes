import CoreServices
import Foundation

public struct VaultChange: Sendable, Equatable {
    public let notesChanged: Set<String>
    public let assetsChanged: Set<String>
    public let needsFullSync: Bool

    public init(notesChanged: Set<String>, assetsChanged: Set<String>, needsFullSync: Bool) {
        self.notesChanged = notesChanged
        self.assetsChanged = assetsChanged
        self.needsFullSync = needsFullSync
    }
}

/// Watches vault changes. Consumers can skip unchanged files using index fingerprints.
public final class VaultWatcher: @unchecked Sendable {
    private let vault: Vault
    private let latency: TimeInterval
    private let onChange: @Sendable (VaultChange) -> Void
    private let queue = DispatchQueue(label: "vault-watcher")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var stream: FSEventStreamRef?

    public init(
        vault: Vault,
        latency: TimeInterval = 1.0,
        onChange: @escaping @Sendable (VaultChange) -> Void
    ) {
        self.vault = vault
        self.latency = max(0, latency)
        self.onChange = onChange
        queue.setSpecific(key: queueKey, value: true)
    }

    deinit {
        stop()
    }

    /// A failed stream creation/start leaves this false, allowing callers to fall back to sync.
    public var isRunning: Bool {
        var running = false
        performOnQueue { running = self.stream != nil }
        return running
    }

    public func start() {
        performOnQueue {
            guard self.stream == nil else { return }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let paths = [self.vault.root.path] as CFArray
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                vaultWatcherCallback,
                &context,
                paths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                self.latency,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
            ) else {
                return
            }

            FSEventStreamSetDispatchQueue(stream, self.queue)
            guard FSEventStreamStart(stream) else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                return
            }
            self.stream = stream
        }
    }

    public func stop() {
        performOnQueue {
            guard let stream = self.stream else { return }
            self.stream = nil
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func performOnQueue(_ operation: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            operation()
        } else {
            queue.sync(execute: operation)
        }
    }

    fileprivate func handle(_ events: [(path: String, flags: FSEventStreamEventFlags)]) {
        guard stream != nil else { return }

        var notesChanged = Set<String>()
        var assetsChanged = Set<String>()
        var needsFullSync = false

        for event in events {
            let flags = event.flags
            if hasFlag(flags, kFSEventStreamEventFlagMustScanSubDirs)
                || hasFlag(flags, kFSEventStreamEventFlagRootChanged)
                || hasFlag(flags, kFSEventStreamEventFlagUserDropped)
                || hasFlag(flags, kFSEventStreamEventFlagKernelDropped) {
                needsFullSync = true
            }

            guard let relativePath = vault.relativePath(of: URL(fileURLWithPath: event.path)) else {
                continue
            }
            let components = relativePath.split(separator: "/").map(String.init)
            guard let name = components.last else { continue }

            if components.count == 1,
               (name == Vault.sessionsDirectoryName || name == Vault.assetsDirectoryName),
               hasFlag(flags, kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemRemoved) {
                needsFullSync = true
            }

            guard isReportablePath(components) else {
                continue
            }

            if components.count == 1, isMarkdown(name), !isDirectory(flags) {
                notesChanged.insert(relativePath)
            } else if components.count == 2,
                      components[0] == Vault.sessionsDirectoryName,
                      isMarkdown(name),
                      !isDirectory(flags) {
                notesChanged.insert(relativePath)
            } else if components.count >= 2, components[0] == Vault.assetsDirectoryName {
                assetsChanged.insert(relativePath)
            }
        }

        guard needsFullSync || !notesChanged.isEmpty || !assetsChanged.isEmpty else { return }
        onChange(VaultChange(
            notesChanged: notesChanged,
            assetsChanged: assetsChanged,
            needsFullSync: needsFullSync
        ))
    }

    private func isReportablePath(_ components: [String]) -> Bool {
        guard !components.isEmpty,
              !components.contains(where: { $0.hasPrefix(".") }),
              let name = components.last,
              !name.hasPrefix(".~"),
              !name.hasPrefix("~$"),
              name != ".DS_Store",
              !name.lowercased().hasSuffix(".swp"),
              !name.lowercased().hasSuffix(".icloud") else {
            return false
        }

        if components.count == 1 {
            return isMarkdown(name)
        }
        if components.count == 2, components[0] == Vault.sessionsDirectoryName {
            return isMarkdown(name)
        }
        return components.count >= 2 && components[0] == Vault.assetsDirectoryName
    }

    private func isMarkdown(_ name: String) -> Bool {
        URL(fileURLWithPath: name).pathExtension.lowercased() == "md"
    }

    private func isDirectory(_ flags: FSEventStreamEventFlags) -> Bool {
        hasFlag(flags, kFSEventStreamEventFlagItemIsDir)
    }

    private func hasFlag(_ flags: FSEventStreamEventFlags, _ flag: Int) -> Bool {
        flags & FSEventStreamEventFlags(flag) != 0
    }

}

private let vaultWatcherCallback: FSEventStreamCallback = { _, clientInfo, eventCount, eventPaths, eventFlags, _ in
    guard let clientInfo else { return }
    let watcher = Unmanaged<VaultWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
    let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
    var events: [(path: String, flags: FSEventStreamEventFlags)] = []
    events.reserveCapacity(eventCount)
    for index in 0..<eventCount {
        guard let path = paths[index] else { continue }
        events.append((String(cString: path), eventFlags[index]))
    }
    watcher.handle(events)
}
