import Foundation

public struct Session: Codable, Sendable, Equatable {
    public var name: String
    /// Vault-relative path, for example `Sessions/Design.md`.
    public var notePath: String
    public var resumed: Bool?
    public var startedAt: Date

    public init(name: String, notePath: String, startedAt: Date) {
        self.name = name
        self.notePath = notePath
        self.startedAt = startedAt
        self.resumed = nil
    }
}

/// Holds the active session and persists it to `stateDirectory/session.json`.
public actor SessionStore {
    private static let stateFileName = "session.json"

    private let stateDirectory: URL
    private let vault: Vault
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let beforeNoteWrite: @Sendable (String) -> Void
    private var session: Session?

    public init(
        stateDirectory: URL,
        vault: Vault,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
        beforeNoteWrite: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.stateDirectory = stateDirectory
        self.vault = vault
        self.calendar = calendar
        self.now = now
        self.beforeNoteWrite = beforeNoteWrite
        self.session = Self.load(from: stateDirectory.appendingPathComponent(Self.stateFileName))
    }

    public func current() -> Session? {
        session
    }

    /// Starts a session, replacing any active one. Resumes the same cleaned filename, regardless of case or date.
    public func start(name: String) throws -> Session {
        let cleaned = NoteTitle.cleanTitle(name)
        let title = cleaned.isEmpty ? "Session" : cleaned

        try vault.prepare()
        let current = now()
        let stem = NoteTitle.fileStem(for: title)
        let existing = try FileManager.default.contentsOfDirectory(at: vault.sessionsURL, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { $0.pathExtension.lowercased() == "md" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { left, right in
                let leftExact = left.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(stem) == .orderedSame
                let rightExact = right.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(stem) == .orderedSame
                if leftExact != rightExact { return leftExact }
                return left.lastPathComponent > right.lastPathComponent
            }
            .first {
                let existingStem = $0.deletingPathExtension().lastPathComponent
                if existingStem.caseInsensitiveCompare(stem) == .orderedSame { return true }
                // Legacy dated notes remain in place and can be resumed by their title.
                let prefix = existingStem.prefix(11)
                guard prefix.count == 11, prefix.last == " ", prefix.dropLast().enumerated().allSatisfy({
                    [4, 7].contains($0.offset) ? $0.element == "-" : $0.element.isNumber
                }) else { return false }
                return String(existingStem.dropFirst(11)).caseInsensitiveCompare(stem) == .orderedSame
            }
        let fileName = existing?.lastPathComponent ?? "\(stem).md"
        let noteURL = vault.sessionsURL.appendingPathComponent(fileName)
        let displayTitle = existing.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { $0.components(separatedBy: "\n").first }
            .flatMap { $0.hasPrefix("# ") ? NoteTitle.cleanTitle(String($0.dropFirst(2))) : nil }
        let sessionTitle = displayTitle.flatMap { $0.isEmpty ? nil : $0 } ?? title
        beforeNoteWrite("\(Vault.sessionsDirectoryName)/\(fileName)")
        try NoteFile.create(Data(CaptureFormat.noteHeader(title: title).utf8), at: noteURL)

        var started = Session(
            name: sessionTitle,
            notePath: "\(Vault.sessionsDirectoryName)/\(fileName)",
            startedAt: current
        )
        started.resumed = existing != nil
        try persist(started)
        session = started
        return started
    }

    /// Ends the active session and deletes the state file.
    public func end() throws {
        let url = stateFileURL
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            // Ending an already ended session is harmless. Other I/O errors retain it.
        }
        session = nil
    }

    private var stateFileURL: URL {
        stateDirectory.appendingPathComponent(Self.stateFileName)
    }

    private func persist(_ session: Session) throws {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(session).write(to: stateFileURL, options: .atomic)
    }

    /// A missing or corrupt state file loads as no session.
    private static func load(from url: URL) -> Session? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Session.self, from: data)
    }
}
