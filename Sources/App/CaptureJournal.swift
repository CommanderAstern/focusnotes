import CaptureKit
import Core
import Foundation

struct CaptureJob: Sendable {
    let prepared: PreparedCapture
    let png: Data?
    let ocr: String?
    var deferredOCR: Task<CaptureKit.OCRResult?, Never>? = nil
    var noteDraft: String? = nil
}

actor CaptureJournal {
    struct Record: Codable {
        let prepared: PreparedCapture
        let hasPNG: Bool
        let ocr: String?
        let noteDraft: String?
    }

    let directory: URL

    init(stateDirectory: URL) {
        directory = stateDirectory.appendingPathComponent("unsaved", isDirectory: true)
    }

    func store(_ job: CaptureJob) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = job.prepared.capture.id.uuidString.lowercased()
        if let png = job.png {
            try png.write(to: directory.appendingPathComponent(stem + ".png"), options: .atomic)
        }
        let record = Record(prepared: job.prepared, hasPNG: job.png != nil, ocr: job.ocr, noteDraft: job.noteDraft)
        try JSONEncoder().encode(record).write(to: directory.appendingPathComponent(stem + ".json"), options: .atomic)
    }

    enum RecordError: Error {
        case corrupt
    }

    func recordURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let records = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { url in
                let date = try? JSONDecoder().decode(Record.self, from: Data(contentsOf: url)).prepared.capture.createdAt
                return (url: url, date: date ?? .distantPast)
            }
        return records.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }.map(\.url)
    }

    /// Replay owns only one record's PNG at a time. I/O failures remain retryable.
    func load(record url: URL) throws -> CaptureJob {
        let data = try Data(contentsOf: url)
        let record: Record
        do { record = try JSONDecoder().decode(Record.self, from: data) }
        catch { throw RecordError.corrupt }
        guard url.deletingPathExtension().lastPathComponent == record.prepared.capture.id.uuidString.lowercased() else {
            throw RecordError.corrupt
        }
        var png: Data?
        if record.hasPNG {
            do { png = try Data(contentsOf: url.deletingPathExtension().appendingPathExtension("png")) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                guard let text = record.ocr, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RecordError.corrupt
                }
                let original = record.prepared.capture
                let capture = Capture(id: original.id, createdAt: original.createdAt, content: .text(text), source: original.source)
                return CaptureJob(prepared: PreparedCapture(capture: capture, destination: record.prepared.destination), png: nil, ocr: nil)
            }
        }
        return CaptureJob(prepared: record.prepared, png: png, ocr: record.ocr, noteDraft: record.noteDraft)
    }

    /// Keep undecodable records and their PNGs without retrying them on every launch.
    func quarantine(record url: URL) throws {
        let corrupt = directory.appendingPathComponent("corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        let stem = url.deletingPathExtension().lastPathComponent
        let targetStem = FileManager.default.fileExists(atPath: corrupt.appendingPathComponent(stem + ".json").path)
            ? stem + "-" + UUID().uuidString.lowercased() : stem
        for ext in ["json", "png"] {
            let source = directory.appendingPathComponent(stem + "." + ext)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.moveItem(at: source, to: corrupt.appendingPathComponent(targetStem + "." + ext))
            }
        }
    }

    func remove(id: UUID) throws {
        let stem = id.uuidString.lowercased()
        // Remove the recovery record only after the note append has succeeded.
        for ext in ["json", "png"] {
            let file = directory.appendingPathComponent(stem + "." + ext)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }
}
