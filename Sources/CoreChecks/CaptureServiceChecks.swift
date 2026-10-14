import Core
import Foundation

func checkCaptureService() async throws {
    let base = try checkMakeDirectory("capture")
    defer { checkRemoveDirectory(base) }
    let calendar = checkCalendar()
    let vault = Vault(root: base.appendingPathComponent("Vault", isDirectory: true))
    let stateDirectory = base.appendingPathComponent("State", isDirectory: true)
    let now = checkDate(2026, 10, 13, 10, 0)
    let clock: @Sendable () -> Date = { now }
    let captureID = UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!
    let makeID: @Sendable () -> UUID = { captureID }

    let sessions = SessionStore(stateDirectory: stateDirectory, vault: vault, calendar: calendar, now: clock)
    let writer = NoteWriter(vault: vault, calendar: calendar)
    let service = CaptureService(vault: vault, sessions: sessions, writer: writer, now: clock, makeID: makeID)
    let png = Data([0x89, 0x50, 0x4E, 0x47])

    // No active session: text goes to Inbox.md.
    let inboxSave = try await service.saveText("Hello inbox", source: CaptureSource(appName: "Safari"), heading: nil)
    try require(inboxSave.captureID == captureID, "saveText should return the capture id")
    try require(inboxSave.destination.kind == .inbox, "no active session should route to Inbox")
    try require(
        inboxSave.destination.url.path == vault.inboxURL.path,
        "Inbox destination path was \(inboxSave.destination.url.path)"
    )
    let inboxText = try checkRead(vault.inboxURL)
    try require(inboxText.contains("Hello inbox"), "Inbox.md should contain the capture text")
    try require(inboxText.contains(checkCaptureMarker(captureID)), "Inbox.md should contain the capture marker")

    // Active session: text goes to the session note, not Inbox.md.
    _ = try await sessions.start(name: "Design")
    let sessionURL = vault.sessionsURL.appendingPathComponent("Design.md")
    let sessionSave = try await service.saveText("Into session", source: CaptureSource(appName: "Xcode"), heading: nil)
    try require(sessionSave.destination.kind == .session, "an active session should route to the session note")
    try require(
        sessionSave.destination.url.path == sessionURL.path,
        "session destination path was \(sessionSave.destination.url.path)"
    )
    let sessionText = try checkRead(sessionURL)
    try require(
        sessionText.contains("### Xcode\n"),
        "session note should hold the Xcode block heading"
    )
    try require(sessionText.contains("Into session"), "session note should contain the text")
    let inboxAfterSession = try checkRead(vault.inboxURL)
    try require(!inboxAfterSession.contains("Into session"), "session text must not go to Inbox.md")

    // A heading overrides the active session.
    let headingSave = try await service.saveText("Heading wins", source: CaptureSource(), heading: "Inbox")
    try require(headingSave.destination.kind == .inbox, "heading Inbox should beat the active session")
    let inboxAfterHeading = try checkRead(vault.inboxURL)
    try require(inboxAfterHeading.contains("Heading wins"), "heading text should land in Inbox.md")

    // An image in the session note links to ../assets/ and the PNG exists.
    let imageSave = try await service.saveImage(png: png, source: CaptureSource(appName: "Preview"), heading: nil)
    try require(imageSave.destination.kind == .session, "an image with an active session should route to the session note")
    let sessionWithImage = try checkRead(sessionURL)
    guard let linkStart = sessionWithImage.range(of: "![](../assets/") else {
        throw CheckFailure.failed("session note has no ../assets image link")
    }
    guard let linkEnd = sessionWithImage[linkStart.lowerBound...].firstIndex(of: ")") else {
        throw CheckFailure.failed("image link in the session note is not closed")
    }
    let link = String(sessionWithImage[linkStart.lowerBound..<linkEnd])
    let linkPrefix = "![](../"
    let assetRelativePath = String(link.dropFirst(linkPrefix.count))
    try require(
        assetRelativePath.hasPrefix("assets/") && assetRelativePath.hasSuffix(".png"),
        "unexpected asset link \(assetRelativePath)"
    )
    let assetURL = vault.root.appendingPathComponent(assetRelativePath)
    try require(FileManager.default.fileExists(atPath: assetURL.path), "linked PNG should exist at \(assetURL.path)")
    let assetData = try Data(contentsOf: assetURL)
    try require(assetData == png, "saved PNG bytes differ from the input")

    // An image in Inbox.md links to assets/ directly.
    let inboxImage = try await service.saveImage(png: png, source: CaptureSource(), heading: "Inbox")
    try require(inboxImage.destination.kind == .inbox, "heading Inbox should route the image to Inbox.md")
    let inboxWithImage = try checkRead(vault.inboxURL)
    try require(inboxWithImage.contains("![](assets/"), "Inbox image link should point at assets/ directly")
    try require(!inboxWithImage.contains("![](../"), "Inbox image link must not use ../")
    // A failed write and replay both reuse the prepared identity and destination.
    let retryID = UUID()
    let retryCapture = Capture(id: retryID, createdAt: now, content: .text("retry identity"), source: CaptureSource(appName: "Test"))
    let prepared = await service.prepare(retryCapture, heading: "Retry Destination")
    try FileManager.default.createDirectory(at: prepared.destination.url, withIntermediateDirectories: false)
    do {
        _ = try await service.save(prepared)
        throw CheckFailure.failed("a directory cannot be appended as a note")
    } catch is CheckFailure { throw CheckFailure.failed("prepared save should have failed") }
    catch {}
    try FileManager.default.removeItem(at: prepared.destination.url)
    _ = try await sessions.start(name: "Changed Session")
    let retried = try await service.save(prepared)
    let replayed = try await service.save(prepared)
    let retryText = try checkRead(prepared.destination.url)
    try require(retried.captureID == retryID && replayed == retried && retried.destination == prepared.destination,
                "retry must preserve ID, date, and destination after session changes")
    try require(retryText.components(separatedBy: checkCaptureMarker(retryID)).count - 1 == 1,
                "replaying a prepared capture must not duplicate its marker")
    let parsedRetry = NoteParser.parse(contents: retryText, notePath: "Retry Destination.md", titleFallback: "", calendar: calendar)
    try require(parsedRetry.blocks.first?.createdAt == now, "retry must preserve the original timestamp")
    print("CaptureService checks passed (including fixed-destination, idempotent retries).")
}
