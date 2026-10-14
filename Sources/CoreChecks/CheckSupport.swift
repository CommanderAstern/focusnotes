import Core
import Foundation

/// Gregorian calendar in Asia/Kolkata, the zone every check uses.
func checkCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return calendar
}

/// Whole-second date in Asia/Kolkata. Whole seconds matter because session.json stores ISO-8601 without fractions.
func checkDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: 0)
    return checkCalendar().date(from: components)!
}

/// Fresh, empty directory under the system temp folder. Callers remove it with `defer`.
func checkMakeDirectory(_ label: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("corechecks-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func checkRemoveDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

/// Writes UTF-8 text, creating parent folders as needed.
func checkWrite(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

func checkRead(_ url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    return String(decoding: data, as: UTF8.self)
}

/// The marker line exactly as the format writes it: lowercase UUID.
func checkMarker(_ id: UUID) -> String {
    "<!-- capture:" + id.uuidString.lowercased() + " -->"
}

func checkKindName(_ kind: NoteKind) -> String {
    switch kind {
    case .inbox:
        return "inbox"
    case .session:
        return "session"
    case .note:
        return "note"
    }
}

/// Identity prefix works for both legacy and metadata-bearing capture markers.
func checkCaptureMarker(_ id: UUID) -> String {
    "<!-- capture:" + id.uuidString.lowercased()
}
