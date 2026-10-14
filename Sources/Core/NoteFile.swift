import Darwin
import Foundation

/// O_APPEND protects existing bytes even when independent writers share a note.
enum NoteFile {
    private static let attempts = 4

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

    static func append(block: String, header: String, to url: URL, unlessMarkerExists marker: String? = nil,
                       savedNoteMarker: String? = nil, sourceHeading: String? = nil, equivalentBlocks: [String] = [], calendar: Calendar = .current,
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
                let end = try reader.seekToEnd()
                var emittedBlock = block
                if marker != nil || sourceHeading != nil || attempt > 0 {
                    try reader.seek(toOffset: 0)
                    let contents = try reader.readToEnd() ?? Data()
                    // An independently created note keeps its identity even when
                    // the user has subsequently edited its body in another app.
                    if let savedNoteMarker, contents.range(of: Data(savedNoteMarker.utf8)) != nil { return try isCurrent(descriptor, at: url) }
                    // A marker alone can be left by a short write. Only a whole block is saved.
                    if contents.range(of: blockData) != nil || equivalentBlocks.contains(where: { contents.range(of: Data($0.utf8)) != nil }) { return try isCurrent(descriptor, at: url) }
                    if let sourceHeading, NoteParser.needsSourceHeading(sourceHeading, contents: String(decoding: contents, as: UTF8.self), calendar: calendar) {
                        emittedBlock = "### \(sourceHeading)\n" + block
                    }
                }
                let prefix: String
                if end == 0 { prefix = header }
                else {
                    try reader.seek(toOffset: end - min(2, end))
                    let tail = try reader.read(upToCount: 2) ?? Data()
                    prefix = tail.suffix(2) == Data([10, 10]) ? "" : (tail.last == 10 ? "\n" : "\n\n")
                }
                try writeAll(Data((prefix + emittedBlock).utf8), to: descriptor)
                afterWrite?(url)
                return try isCurrent(descriptor, at: url)
            }
            if current { return }
            // An atomic editor save unlinked our inode. Retry on the replacement; its
            // complete-block check also covers editors that copied our append forward.
        }
        throw POSIXError(.EAGAIN)
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
