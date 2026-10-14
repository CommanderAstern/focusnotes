import Core
import Foundation

func checkSessionStore() async throws {
    let base = try checkMakeDirectory("sessions")
    defer { checkRemoveDirectory(base) }
    let calendar = checkCalendar()
    let vault = Vault(root: base.appendingPathComponent("Vault", isDirectory: true))
    let stateDirectory = base.appendingPathComponent("State", isDirectory: true)
    let stateFile = stateDirectory.appendingPathComponent("session.json")
    let now = checkDate(2026, 10, 13, 10, 0)
    let clock: @Sendable () -> Date = { now }

    let store = SessionStore(stateDirectory: stateDirectory, vault: vault, calendar: calendar, now: clock)
    let initial = await store.current()
    try require(initial == nil, "a new store should have no session")

    let started = try await store.start(name: "Design Review")
    try require(started.name == "Design Review", "session name was \(started.name)")
    try require(
        started.notePath == "Sessions/Design Review.md",
        "session note path was \(started.notePath)"
    )
    try require(started.startedAt == now, "session start time was \(started.startedAt)")
    let noteURL = vault.sessionsURL.appendingPathComponent("Design Review.md")
    let noteText = try checkRead(noteURL)
    try require(noteText == "# Design Review\n", "new session note was \(noteText.debugDescription)")
    try require(FileManager.default.fileExists(atPath: stateFile.path), "start should persist session.json")

    let reopened = SessionStore(stateDirectory: stateDirectory, vault: vault, calendar: calendar, now: clock)
    let restored = await reopened.current()
    try require(restored == started, "a new store on the same folder should restore the session")

    // Same name on the different days reuses the existing note instead of rewriting it.
    try checkWrite(noteText + "extra line\n", to: noteURL)
    _ = try await store.start(name: "Design Review")
    let reused = try checkRead(noteURL)
    try require(reused == noteText + "extra line\n", "starting the same name on the different days should reuse the note")
    let sessionFiles = try FileManager.default.contentsOfDirectory(atPath: vault.sessionsURL.path)
    try require(sessionFiles == ["Design Review.md"], "unexpected files in Sessions: \(sessionFiles)")

    let later = SessionStore(stateDirectory: stateDirectory, vault: vault, calendar: calendar, now: { now.addingTimeInterval(86_400) })
    let resumed = try await later.start(name: "design review")
    try require(resumed.notePath == started.notePath && resumed.name == "Design Review" && resumed.resumed == true,
                "case-insensitive resume must keep the existing filename and title")
    let cleaned = try await store.start(name: "A/B")
    let cleanedResume = try await store.start(name: "a:b")
    try require(cleaned.notePath == cleanedResume.notePath && cleanedResume.resumed == true, "resume must use filename cleaning")
    let legacy = vault.sessionsURL.appendingPathComponent("2026-10-12 Legacy.md")
    try checkWrite("# Legacy\n\nold bytes\n", to: legacy)
    let oldSession = Session(name: "Legacy", notePath: "Sessions/2026-10-12 Legacy.md", startedAt: now)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(oldSession).write(to: stateFile)
    let legacyStore = SessionStore(stateDirectory: stateDirectory, vault: vault, calendar: calendar, now: clock)
    let restoredLegacy = await legacyStore.current()
    let legacyBytes = try checkRead(legacy)
    try require(restoredLegacy?.notePath == oldSession.notePath && legacyBytes == "# Legacy\n\nold bytes\n", "dated sessions must stay where they are")

    let resumedLegacy = try await store.start(name: "legacy")
    try require(resumedLegacy.notePath == oldSession.notePath && resumedLegacy.resumed == true, "resuming an old dated note must keep its path")

    let blank = try await store.start(name: "   ")
    try require(blank.name == "Session", "a blank name should become Session, got \(blank.name)")
    try require(
        blank.notePath == "Sessions/Session.md",
        "blank session note path was \(blank.notePath)"
    )

    try await store.end()
    let ended = await store.current()
    try require(ended == nil, "end should clear the active session")
    try require(!FileManager.default.fileExists(atPath: stateFile.path), "end should delete session.json")
    try await store.end()

    let afterEnd = SessionStore(stateDirectory: stateDirectory, vault: vault, calendar: calendar, now: clock)
    let restoredAfterEnd = await afterEnd.current()
    try require(restoredAfterEnd == nil, "a new store after end should have no session")

    try checkWrite("{not json", to: stateFile)
    let corrupt = SessionStore(stateDirectory: stateDirectory, vault: vault, calendar: calendar, now: clock)
    let corruptSession = await corrupt.current()
    try require(corruptSession == nil, "a corrupt session.json should load as no session")
    let kept = try await store.start(name: "Keep on failure")
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: stateDirectory.path)
    do {
        try await store.end()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stateDirectory.path)
        throw CheckFailure.failed("end should fail when the state directory cannot be modified")
    } catch is CheckFailure { throw CheckFailure.failed("end unexpectedly succeeded") }
    catch {
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stateDirectory.path)
    }
    let retained = await store.current()
    try require(retained == kept && FileManager.default.fileExists(atPath: stateFile.path), "failed state deletion must keep the session active")
    try await store.end()
    print("SessionStore checks passed.")
}
