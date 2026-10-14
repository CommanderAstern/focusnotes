import Foundation

public enum NoteKind: Codable, Sendable, Equatable {
    case inbox
    case session
    case note
}

public struct NoteRef: Sendable, Equatable {
    public var url: URL
    public var title: String
    public var kind: NoteKind

    public init(url: URL, title: String, kind: NoteKind) {
        self.url = url
        self.title = title
        self.kind = kind
    }
}

/// The notes folder: root notes, `Sessions/` and `assets/`.
public struct Vault: Sendable {
    public static let inboxFileName = "Inbox.md"
    public static let inboxTitle = "Inbox"
    public static let sessionsDirectoryName = "Sessions"
    public static let assetsDirectoryName = "assets"

    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    public var inboxURL: URL {
        root.appendingPathComponent(Self.inboxFileName)
    }

    public var sessionsURL: URL {
        root.appendingPathComponent(Self.sessionsDirectoryName, isDirectory: true)
    }

    public var assetsURL: URL {
        root.appendingPathComponent(Self.assetsDirectoryName, isDirectory: true)
    }

    /// Creates the folder layout and `Inbox.md` if missing. Never overwrites existing files.
    public func prepare() throws {
        let fm = FileManager.default
        for directory in [root, sessionsURL, assetsURL] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: inboxURL.path) {
            try Data(CaptureFormat.noteHeader(title: Self.inboxTitle).utf8)
                .write(to: inboxURL, options: .withoutOverwriting)
        }
    }

    /// Lists `*.md` files directly in the root and in `Sessions/`. Hidden files are skipped.
    public func listNotes() throws -> [NoteRef] {
        var refs: [NoteRef] = []
        for url in try markdownFiles(in: root) {
            let kind: NoteKind = url.lastPathComponent == Self.inboxFileName ? .inbox : .note
            refs.append(NoteRef(url: url, title: title(of: url), kind: kind))
        }
        for url in try markdownFiles(in: sessionsURL) {
            refs.append(NoteRef(url: url, title: title(of: url), kind: .session))
        }
        return refs
    }

    /// `Stem.md`, then `Stem 2.md`, `Stem 3.md`, ... in the root, whichever is free first.
    public func uniqueNoteURL(forTitle title: String, excluding reserved: Set<URL> = []) -> URL {
        let stem = NoteTitle.fileStem(for: title)
        let fm = FileManager.default
        var candidate = root.appendingPathComponent("\(stem).md")
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) || reserved.contains(candidate) {
            candidate = root.appendingPathComponent("\(stem) \(suffix).md")
            suffix += 1
        }
        return candidate
    }

    /// Resolves a vault-relative, slash-separated path such as `Sessions/2026-10-13 Foo.md`.
    public func url(forRelativePath path: String) -> URL {
        path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    /// Vault-relative path of a URL inside the vault, or nil when it is outside.
    public func relativePath(of url: URL) -> String? {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard components.count > rootComponents.count,
              Array(components.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }

    /// Vault-relative folder of a note: `""` for root notes, `"Sessions"` for session notes.
    func relativeDirectory(of note: URL) -> String {
        let path = relativePath(of: note) ?? note.lastPathComponent
        return path.split(separator: "/").dropLast().joined(separator: "/")
    }

    private func markdownFiles(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let items = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return items
            .filter { $0.pathExtension.lowercased() == "md" }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Title from a leading `# ` line within the first 4 KB, else the file stem.
    private func title(of url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        guard let handle = try? FileHandle(forReadingFrom: url) else { return stem }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 4096)) ?? Data()
        let lineData = data.prefix { $0 != 0x0A }
        var firstLine = String(decoding: lineData, as: UTF8.self)
        if firstLine.hasPrefix("\u{FEFF}") {
            firstLine.removeFirst()
        }
        guard firstLine.hasPrefix("# ") else { return stem }
        let title = NoteTitle.cleanTitle(String(firstLine.dropFirst(2)))
        return title.isEmpty ? stem : title
    }
}
