import Foundation

/// Serializes all note and asset writes. Note files are only ever appended to, never rewritten.
public actor NoteWriter {
    private let vault: Vault
    private let calendar: Calendar
    private let afterAppend: (@Sendable (URL) -> Void)?

    public init(vault: Vault, calendar: Calendar) {
        self.vault = vault
        self.calendar = calendar
        afterAppend = nil
    }

    /// Deterministic atomic-replacement injection, unavailable to normal clients.
    @_spi(Checks)
    public init(vault: Vault, calendar: Calendar, afterAppend: @escaping @Sendable (URL) -> Void) {
        self.vault = vault
        self.calendar = calendar
        self.afterAppend = afterAppend
    }

    /// Appends one capture block to `note`. Creates the file with its header when it does not exist.
    public func append(_ capture: Capture, to note: URL, title: String) throws {
        let block = CaptureFormat.block(
            for: capture,
            noteRelativeDir: vault.relativeDirectory(of: note),
            calendar: calendar, includeSourceHeading: false
        )
        let header = CaptureFormat.noteHeader(title: title) + "\n"

        try NoteFile.append(block: block, header: header, to: note, sourceHeading: headingSource(capture), equivalentBlocks: legacyBlocks(capture, block: block), calendar: calendar, afterWrite: afterAppend)
    }

    /// Retries keep the original marker and asset path, including after journal replay.
    public func appendIfMissing(_ capture: Capture, to destination: Destination, png: Data? = nil, noteMarkerIsIdentity: Bool = false) throws {
        if case .image(let path) = capture.content, let png {
            let url = vault.root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
            guard vault.relativePath(of: url) == path else { throw CocoaError(.fileWriteInvalidFileName) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The stable asset path survives retries. Replace an incomplete asset
            // atomically; a previous failed write must not leave a truncated PNG.
            if (try? Data(contentsOf: url)) != png { try png.write(to: url, options: .atomic) }
        }
        let block = CaptureFormat.block(for: capture, noteRelativeDir: vault.relativeDirectory(of: destination.url), calendar: calendar, includeSourceHeading: false)
        let prefix: String = switch capture.content {
        case .note: "note"
        case .subheading: "subheading"
        default: "capture"
        }
        let marker = "<!-- \(prefix):\(capture.id.uuidString.lowercased()) -->"
        let savedNoteMarker = noteMarkerIsIdentity && prefix == "note" ? String(block.prefix(while: { $0 != "\n" })) : nil
        try NoteFile.append(block: block, header: CaptureFormat.noteHeader(title: destination.title) + "\n",
                            to: destination.url, unlessMarkerExists: marker, savedNoteMarker: savedNoteMarker, sourceHeading: headingSource(capture), equivalentBlocks: legacyBlocks(capture, block: block), calendar: calendar, afterWrite: afterAppend)
    }

    private func legacyBlocks(_ capture: Capture, block: String) -> [String] {
        switch capture.content {
        case .subheading, .note: return []
        default:
            // An upgrade may replay a job already saved by the old writer.
            let body = block.drop(while: { $0 != "\n" })
            return ["<!-- capture:\(capture.id.uuidString.lowercased()) -->" + body]
        }
    }

    private func headingSource(_ capture: Capture) -> String? {
        switch capture.content {
        case .subheading, .note: return nil
        default: break
        }
        return CaptureFormat.sourceHeading(capture.source)
    }

    /// Writes a PNG to `assets/{yyyy-MM-dd-HHmmss}-{4 hex}.png` and returns its vault-relative path.
    public func saveImage(png: Data, createdAt: Date) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: vault.assetsURL, withIntermediateDirectories: true)
        let stamp = CaptureFormat.localStamp(createdAt, pattern: "yyyy-MM-dd-HHmmss", calendar: calendar)

        while true {
            let suffix = String(format: "%04x", Int.random(in: 0...0xFFFF))
            let name = "\(stamp)-\(suffix).png"
            let url = vault.assetsURL.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                continue
            }
            try png.write(to: url, options: .atomic)
            return "\(Vault.assetsDirectoryName)/\(name)"
        }
    }
}
