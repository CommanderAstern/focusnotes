import Foundation
import Core

struct NoteDraftSnapshot: Codable, Sendable {
    var text: String
    var pinOnSave: Bool
}

/// Text and pin intent share one atomic record. The lock also protects compare-and-clear
/// when a journal replay finishes while the main actor is accepting edits.
final class NoteDraftStore: @unchecked Sendable {
    private let lock = NSLock()
    let url: URL
    private let legacyURL: URL
    init(stateDirectory: URL) {
        url = stateDirectory.appendingPathComponent("draft-note.json")
        legacyURL = stateDirectory.appendingPathComponent("draft-note.md")
    }
    func load() throws -> String { try loadSnapshot().text }
    func loadSnapshot() throws -> NoteDraftSnapshot { try lock.withLock { try read() } }
    func store(_ text: String, pinOnSave: Bool? = nil) throws {
        try lock.withLock {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try remove(); return }
            let pin = try pinOnSave ?? read().pinOnSave
            try write(NoteDraftSnapshot(text: text, pinOnSave: pin))
        }
    }
    func setPinOnSave(_ pin: Bool) throws {
        try lock.withLock {
            var draft = try read()
            guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            draft.pinOnSave = pin
            try write(draft)
        }
    }
    func clear(ifMatching text: String) throws {
        try lock.withLock {
            if CaptureFormat.noteBody(try read().text) == CaptureFormat.noteBody(text) { try remove() }
        }
    }
    /// Apply the current intent before consuming the matching draft. Recovery never
    /// takes intent from a replaced/discarded draft; interactive saves supply their call's intent.
    func completeSave(matching text: String, pinOnSave: Bool?, applyPin: (Bool) -> Void) throws {
        try lock.withLock {
            let draft = try read()
            let matches = CaptureFormat.noteBody(draft.text) == CaptureFormat.noteBody(text)
            applyPin(pinOnSave ?? (matches && draft.pinOnSave))
            if matches { try remove() }
        }
    }
    private func read() throws -> NoteDraftSnapshot {
        do { return try JSONDecoder().decode(NoteDraftSnapshot.self, from: Data(contentsOf: url)) }
        catch is DecodingError {
            // A corrupt record must not block the editor or fail saves; keep it aside for inspection.
            let aside = url.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return NoteDraftSnapshot(text: "", pinOnSave: false)
        }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            do { return NoteDraftSnapshot(text: try String(contentsOf: legacyURL, encoding: .utf8), pinOnSave: false) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                return NoteDraftSnapshot(text: "", pinOnSave: false)
            }
        }
    }
    private func write(_ draft: NoteDraftSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: url, options: .atomic)
        try removeFile(legacyURL)
    }
    private func remove() throws { try removeFile(legacyURL); try removeFile(url) }
    private func removeFile(_ file: URL) throws {
        do { try FileManager.default.removeItem(at: file) }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {}
    }
}
