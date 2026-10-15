import Darwin
import Foundation

/// O_APPEND protects existing bytes even when independent writers share a note.
enum NoteFile {
    private static let attempts = 4

    /// Inbox is app-managed: migrate legacy broad modes without following a
    /// symlink or changing a hard-linked file outside the vault.
    static func prepareInbox(_ data: Data, in root: URL) throws {
        let directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw posixError() }
        defer { close(directory) }
        var created = true
        var descriptor = openat(directory, Vault.inboxFileName, O_RDWR | O_APPEND | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if descriptor < 0, errno == EEXIST {
            created = false
            descriptor = openat(directory, Vault.inboxFileName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw posixError() }
        try withLockedDescriptor(descriptor) {
            var attributes = stat()
            guard fstat(descriptor, &attributes) == 0 else { throw posixError() }
            guard attributes.st_mode & S_IFMT == S_IFREG, attributes.st_uid == getuid(), attributes.st_nlink == 1 else {
                throw POSIXError(.EPERM)
            }
            let privateMode = attributes.st_mode & 0o700
            if attributes.st_mode & 0o7777 != privateMode {
                guard fchmod(descriptor, privateMode) == 0 else { throw posixError() }
            }
            if created { try writeAll(data, to: descriptor) }
            // The directory descriptor anchors both open operations. A rename or
            // replacement during preparation must not be reported as success.
            var current = stat()
            guard fstatat(directory, Vault.inboxFileName, &current, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
            guard current.st_dev == attributes.st_dev, current.st_ino == attributes.st_ino,
                  try isCurrent(directory, at: root) else { throw POSIXError(.EAGAIN) }
        }
    }

    /// Advisory state owned by the serial NoteWriter actor, never shared between
    /// writers. Every lookup still occurs under the inode's append lock.
    struct AppendCache {
        private var entries: [String: AppendState] = [:]
        private var order: [String] = []
        private(set) var fullScans = 0
        static let fileLimit = 8
        static let markerLimit = 50_000
        static let sourceByteLimit = 65_536

        var fileCount: Int { entries.count }

        mutating func take(_ path: String, matching fingerprint: Fingerprint) -> AppendState? {
            order.removeAll { $0 == path }
            guard let state = entries.removeValue(forKey: path), state.fingerprint == fingerprint else { return nil }
            return state
        }

        mutating func recordScan() { fullScans += 1 }

        mutating func store(_ state: AppendState, at path: String) {
            guard state.markerCount <= Self.markerLimit,
                  state.source.retainedByteCount <= Self.sourceByteLimit else { return }
            while order.count >= Self.fileLimit { entries.removeValue(forKey: order.removeFirst()) }
            while entries.values.reduce(state.markerCount, { $0 + $1.markerCount }) > Self.markerLimit,
                  !order.isEmpty { entries.removeValue(forKey: order.removeFirst()) }
            entries[path] = state
            order.append(path)
        }
    }

    struct Fingerprint: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modified: timespec
        let changed: timespec

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.device == rhs.device && lhs.inode == rhs.inode && lhs.size == rhs.size &&
                lhs.modified.tv_sec == rhs.modified.tv_sec && lhs.modified.tv_nsec == rhs.modified.tv_nsec &&
                lhs.changed.tv_sec == rhs.changed.tv_sec && lhs.changed.tv_nsec == rhs.changed.tv_nsec
        }
    }

    struct AppendState {
        var fingerprint: Fingerprint
        var markers: [String: [UInt64]] = [:]
        var markerCount = 0
        var source = NoteParser.SourceHeadingState()

        mutating func consume(_ data: Data, at offset: UInt64, calendar: Calendar) {
            // UUID prefixes also locate legacy markers and interrupted metadata.
            // A candidate is only accepted after its entire requested block is read.
            for prefix in ["<!-- capture:", "<!-- note:", "<!-- subheading:"] {
                let needle = Data(prefix.utf8)
                var start = data.startIndex
                while start < data.endIndex,
                      let range = data.range(of: needle, in: start..<data.endIndex) {
                    let end = range.upperBound + 36
                    if end <= data.endIndex {
                        let identity = String(decoding: data[range.lowerBound..<end], as: UTF8.self)
                        if UUID(uuidString: String(identity.suffix(36))) != nil {
                            markers[identity, default: []].append(offset + UInt64(range.lowerBound))
                            markerCount += 1
                            if markerCount > AppendCache.markerLimit { break }
                        }
                    }
                    start = range.upperBound
                }
            }
            source.consume(String(decoding: data, as: UTF8.self), calendar: calendar)
        }
    }

    static func create(_ data: Data, at url: URL) throws {
        for _ in 0..<attempts {
            let descriptor = open(url.path, O_RDWR | O_APPEND | O_CREAT | O_EXCL, 0o600)
            guard descriptor >= 0 else {
                if errno == EEXIST { return }
                throw posixError()
            }
            let current = try withLockedDescriptor(descriptor) {
                var attributes = stat()
                guard fstat(descriptor, &attributes) == 0 else { throw posixError() }
                if attributes.st_size == 0 { try writeAll(data, to: descriptor) }
                return try isCurrent(descriptor, at: url)
            }
            if current { return }
        }
        throw POSIXError(.EAGAIN)
    }

    static func append(block: String, header: String, to url: URL, cache: inout AppendCache, identityPrefix: String,
                       unlessMarkerExists marker: String? = nil,
                       savedNoteMarker: String? = nil, sourceHeading: String? = nil, equivalentBlocks: [String] = [], calendar: Calendar = .current,
                       beforeWrite: (@Sendable (URL) -> Void)? = nil,
                       afterWrite: (@Sendable (URL) -> Void)? = nil) throws {
        if savedNoteMarker != nil { try createCompleteNote(Data((header + block).utf8), at: url) }
        let blockData = Data(block.utf8)
        for attempt in 0..<attempts {
            var descriptor = open(url.path, O_RDWR | O_APPEND | O_CREAT | O_EXCL, 0o600)
            if descriptor < 0, errno == EEXIST { descriptor = open(url.path, O_RDWR | O_APPEND) }
            if descriptor < 0, errno == ENOENT { continue }
            guard descriptor >= 0 else { throw posixError() }
            let current = try withLockedDescriptor(descriptor) {
                // Inspect the locked inode, rather than a path an editor may have replaced.
                let reader = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
                let initial = try fingerprint(descriptor)
                let end = UInt64(initial.size)
                var state = cache.take(url.path, matching: initial)
                var contents: Data?
                var emittedBlock = block
                if marker != nil || sourceHeading != nil || attempt > 0 {
                    if state == nil {
                        try reader.seek(toOffset: 0)
                        let data = try reader.readToEnd() ?? Data()
                        contents = data
                        cache.recordScan()
                        var scanned = AppendState(fingerprint: initial)
                        scanned.consume(data, at: 0, calendar: calendar)
                        if scanned.markerCount <= AppendCache.markerLimit,
                           scanned.source.retainedByteCount <= AppendCache.sourceByteLimit { state = scanned }
                    }
                    let alreadySaved: Bool
                    if let state {
                        alreadySaved = try matches(state: state, identity: identityPrefix, savedNoteMarker: savedNoteMarker,
                                                   blocks: [blockData] + equivalentBlocks.map { Data($0.utf8) }, descriptor: descriptor)
                    } else {
                        let contents = contents ?? Data()
                        alreadySaved = (savedNoteMarker.map { contents.range(of: Data($0.utf8)) != nil } ?? false) ||
                            contents.range(of: blockData) != nil || equivalentBlocks.contains { contents.range(of: Data($0.utf8)) != nil }
                    }
                    // An independently created note keeps its identity even when
                    // the user has subsequently edited its body in another app.
                    // A marker alone can be left by a short write. Only a whole block is saved.
                    if alreadySaved {
                        let current = try isCurrent(descriptor, at: url)
                        guard current, try fingerprint(descriptor) == initial else { return false }
                        if let state { cache.store(state, at: url.path) }
                        return true
                    }
                    if let sourceHeading {
                        let needsHeading = state?.source.needsHeading(sourceHeading, calendar: calendar) ??
                            NoteParser.needsSourceHeading(sourceHeading, contents: String(decoding: contents ?? Data(), as: UTF8.self), calendar: calendar)
                        if needsHeading { emittedBlock = "### \(sourceHeading)\n" + block }
                    }
                }
                let prefix: String
                if end == 0 { prefix = header }
                else {
                    try reader.seek(toOffset: end - min(2, end))
                    let tail = try reader.read(upToCount: 2) ?? Data()
                    prefix = tail.suffix(2) == Data([10, 10]) ? "" : (tail.last == 10 ? "\n" : "\n\n")
                }
                let appended = Data((prefix + emittedBlock).utf8)
                // Non-cooperating external editors can change the inode despite
                // flock. Recompute both replay and source decisions on mutation.
                beforeWrite?(url)
                guard try fingerprint(descriptor) == initial else { return false }
                try writeAll(appended, to: descriptor)
                let written = try fingerprint(descriptor)
                afterWrite?(url)
                let current = try isCurrent(descriptor, at: url)
                if current, var state, written.size == initial.size + off_t(appended.count),
                   try fingerprint(descriptor) == written {
                    state.consume(appended, at: end, calendar: calendar)
                    state.fingerprint = written
                    cache.store(state, at: url.path)
                }
                return current
            }
            if current { return }
            // A replacement or detected in-place edit invalidated our view. Retry
            // from current bytes, including editors that copied our append forward.
        }
        throw POSIXError(.EAGAIN)
    }

    private static func fingerprint(_ descriptor: Int32) throws -> Fingerprint {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else { throw posixError() }
        return Fingerprint(device: value.st_dev, inode: value.st_ino, size: value.st_size,
                           modified: value.st_mtimespec, changed: value.st_ctimespec)
    }

    private static func matches(state: AppendState, identity: String, savedNoteMarker: String?, blocks: [Data], descriptor: Int32) throws -> Bool {
        let identityData = Data(identity.utf8)
        for offset in state.markers[identity] ?? [] {
            if let savedNoteMarker, try equals(Data(savedNoteMarker.utf8), at: offset, descriptor: descriptor) { return true }
            for block in blocks {
                guard let marker = block.range(of: identityData), offset >= UInt64(marker.lowerBound) else { continue }
                if try equals(block, at: offset - UInt64(marker.lowerBound), descriptor: descriptor) { return true }
            }
        }
        return false
    }

    private static func equals(_ expected: Data, at offset: UInt64, descriptor: Int32) throws -> Bool {
        var actual = Data(count: expected.count)
        let count = try actual.withUnsafeMutableBytes { bytes -> Int in
            guard let base = bytes.baseAddress else { return 0 }
            var readCount = 0
            while readCount < bytes.count {
                let result = pread(descriptor, base.advanced(by: readCount), bytes.count - readCount, off_t(offset) + off_t(readCount))
                if result < 0, errno == EINTR { continue }
                guard result >= 0 else { throw posixError() }
                if result == 0 { break }
                readCount += result
            }
            return readCount
        }
        return count == expected.count && actual == expected
    }

    /// Publish a new root note only after its entire header/body has been written
    /// under the lock. Thus a crash cannot expose a saved marker with a short body.
    /// link() installs without replacing a file that appeared since title routing.
    private static func createCompleteNote(_ data: Data, at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { return }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".note-\(UUID().uuidString).pending")
        let descriptor = open(temporary.path, O_RDWR | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { unlink(temporary.path) }
        try withLockedDescriptor(descriptor) {
            try writeAll(data, to: descriptor)
            guard link(temporary.path, url.path) == 0 || errno == EEXIST else { throw posixError() }
        }
    }

    private static func withLockedDescriptor<T>(_ descriptor: Int32, operation: () throws -> T) throws -> T {
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw posixError() }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private static func isCurrent(_ descriptor: Int32, at url: URL) throws -> Bool {
        var opened = stat()
        var current = stat()
        guard fstat(descriptor, &opened) == 0 else { throw posixError() }
        guard stat(url.path, &current) == 0 else {
            if errno == ENOENT { return false }
            throw posixError()
        }
        return opened.st_dev == current.st_dev && opened.st_ino == current.st_ino
    }

    private static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: written), bytes.count - written)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                written += count
            }
        }
    }
}
