@_spi(Checks) import Core
import Foundation

func checkNoteWriter() async throws {
    let root = try checkMakeDirectory("writer")
    defer { checkRemoveDirectory(root) }
    let calendar = checkCalendar()
    let vault = Vault(root: root)
    try vault.prepare()
    let writer = NoteWriter(vault: vault, calendar: calendar)
    let when = checkDate(2026, 10, 13, 14, 30)

    let captureID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let block = "### Safari\n\(checkCaptureMarker(captureID)) at=2026-10-13T14:30:00+05:30 app=\"Safari\" -->\n\nHello\n"
    let capture = Capture(
        id: captureID,
        createdAt: when,
        content: .text("Hello"),
        source: CaptureSource(appName: "Safari")
    )

    // A missing file is created with its header, one blank line, then the block.
    let newNote = root.appendingPathComponent("New.md")
    try await writer.append(capture, to: newNote, title: "New")
    let newText = try checkRead(newNote)
    try require(newText == "# New\n\n" + block, "new file bytes were \(newText.debugDescription)")

    // Existing files always end with exactly one blank line before the new block.
    let separatorCases: [(name: String, before: String, expected: String)] = [
        ("no trailing newline", "# N\n\nold", "# N\n\nold\n\n" + block),
        ("one trailing newline", "# N\n\nold\n", "# N\n\nold\n\n" + block),
        ("two trailing newlines", "# N\n\nold\n\n", "# N\n\nold\n\n" + block),
        ("empty file", "", "# N\n\n" + block),
    ]
    for item in separatorCases {
        let url = root.appendingPathComponent("Separator \(item.name).md")
        try checkWrite(item.before, to: url)
        try await writer.append(capture, to: url, title: "N")
        let after = try checkRead(url)
        try require(after == item.expected, "\(item.name): got \(after.debugDescription)")
    }

    // Appending never changes the bytes already in the file.
    let keepURL = root.appendingPathComponent("Keep.md")
    try checkWrite("# Keep\n\nexisting \u{00E9} text\n", to: keepURL)
    let beforeBytes = try Data(contentsOf: keepURL)
    try await writer.append(capture, to: keepURL, title: "Keep")
    let afterBytes = try Data(contentsOf: keepURL)
    try require(afterBytes.starts(with: beforeBytes), "append changed existing bytes")

    // Independent writers race both exclusive creation and append offsets.
    let concurrentURL = root.appendingPathComponent("Concurrent.md")
    let ids = (0..<50).map { _ in UUID() }
    let writers = ids.map { _ in NoteWriter(vault: vault, calendar: calendar) }
    try await withThrowingTaskGroup(of: Void.self) { group in
        for (index, id) in ids.enumerated() {
            let item = Capture(id: id, createdAt: when, content: .text("Line \(index)"), source: CaptureSource())
            group.addTask {
                try await writers[index].append(item, to: concurrentURL, title: "Concurrent")
            }
        }
        try await group.waitForAll()
    }
    let concurrentText = try checkRead(concurrentURL)
    try require(concurrentText.hasPrefix("# Concurrent\n\n"), "concurrent file should start with its header")
    try require(concurrentText.components(separatedBy: "# Concurrent\n").count - 1 == 1, "exclusive creation must not duplicate the header")
    let markerTotal = concurrentText.components(separatedBy: "<!-- capture:").count - 1
    try require(markerTotal == 50, "expected 50 capture markers, found \(markerTotal)")
    for id in ids {
        let count = concurrentText.components(separatedBy: checkCaptureMarker(id)).count - 1
        try require(count == 1, "marker \(checkCaptureMarker(id)) appeared \(count) times")
    }

    // Images are written under assets/ with a timestamped name.
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let assetPath = try await writer.saveImage(png: png, createdAt: when)
    try require(
        assetPath.hasPrefix("assets/2026-10-13-143000-") && assetPath.hasSuffix(".png"),
        "unexpected asset path \(assetPath)"
    )
    let assetData = try Data(contentsOf: root.appendingPathComponent(assetPath))
    try require(assetData == png, "saved PNG bytes differ")
    try await checkSourceGrouping(vault: vault, calendar: calendar, capture: capture)
    try await checkPartialCaptureReplay(vault: vault, calendar: calendar, capture: capture)
    try await checkAtomicReplacement(vault: vault, calendar: calendar, capture: capture)
    print("NoteWriter checks passed.")
}

private func checkPartialCaptureReplay(vault: Vault, calendar: Calendar, capture: Capture) async throws {
    let block = CaptureFormat.block(for: capture, noteRelativeDir: "", calendar: calendar)
    let writer = NoteWriter(vault: vault, calendar: calendar)
    for (offset, fragment) in [String(block[..<block.range(of: " -->")!.upperBound]), String(block.dropLast(3))].enumerated() {
        let url = vault.root.appendingPathComponent("Partial \(offset).md")
        try checkWrite("# Partial\n\n" + fragment, to: url)
        let before = try Data(contentsOf: url)
        let destination = Destination(url: url, title: "Partial", kind: .note)
        try await writer.appendIfMissing(capture, to: destination)
        let after = try Data(contentsOf: url)
        try require(after.starts(with: before), "partial recovery must preserve every existing byte")
        let text = String(decoding: after, as: UTF8.self)
        try require(text.components(separatedBy: checkCaptureMarker(capture.id)).count - 1 == 2, "a partial block must be followed by a full replay block")
        let parsed = NoteParser.parse(contents: text, notePath: url.lastPathComponent, titleFallback: "", calendar: calendar)
        try require(parsed.blocks.count == 1 && parsed.blocks[0].captureID == capture.id && parsed.blocks[0].body == "Hello", "parser must prefer the last full occurrence of a repeated capture")
        try await writer.appendIfMissing(capture, to: destination)
        let repeated = try Data(contentsOf: url)
        try require(repeated == after, "replay of a complete block must be a byte-for-byte no-op")
        let index = try SearchIndex(vault: vault, databaseURL: vault.root.appendingPathComponent("partial-index.sqlite"), calendar: calendar)
        try await index.reindex(note: url)
        let count = try await index.captureCount(notePath: url.lastPathComponent)
        let hits = try await index.search("Hello")
        try require(count == 1 && hits.filter { $0.notePath == url.lastPathComponent }.count == 1, "repeated markers must produce one search row")
    }
}

private final class EditorReplacement: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private(set) var error: Error?
    let copyAppend: Bool

    init(copyAppend: Bool, count: Int = 1) { self.copyAppend = copyAppend; remaining = count }

    func replace(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard remaining > 0 else { return }
        remaining -= 1
        do {
            let bytes = copyAppend ? try Data(contentsOf: url) : Data("# Replacement\n\neditor kept this\n".utf8)
            try bytes.write(to: url, options: .atomic)
        } catch { self.error = error }
    }
}

private func checkAtomicReplacement(vault: Vault, calendar: Calendar, capture: Capture) async throws {
    for copiesAppend in [false, true] {
        let url = vault.root.appendingPathComponent("Replacement \(copiesAppend).md")
        let editor = EditorReplacement(copyAppend: copiesAppend)
        let writer = NoteWriter(vault: vault, calendar: calendar, afterAppend: { editor.replace($0) })
        try await writer.appendIfMissing(capture, to: Destination(url: url, title: "Replacement", kind: .note))
        let text = try checkRead(url)
        try require(editor.error == nil, "atomic replacement fixture failed")
        try require(text.components(separatedBy: checkCaptureMarker(capture.id)).count - 1 == 1 && text.contains("Hello\n"), "replacement retry must keep exactly one full capture on the current inode")
        if !copiesAppend { try require(text.contains("editor kept this"), "replacement retry must preserve the editor's bytes") }
    }
    let editor = EditorReplacement(copyAppend: false, count: 10)
    let writer = NoteWriter(vault: vault, calendar: calendar, afterAppend: { editor.replace($0) })
    do {
        try await writer.appendIfMissing(capture, to: Destination(url: vault.root.appendingPathComponent("Unstable.md"), title: "Unstable", kind: .note))
        throw CheckFailure.failed("continually replaced notes must fail rather than silently lose an append")
    } catch is CheckFailure { throw CheckFailure.failed("unstable note unexpectedly succeeded") }
    catch {}
    try require(editor.error == nil, "bounded replacement fixture failed")
}

private func checkSourceGrouping(vault: Vault, calendar: Calendar, capture: Capture) async throws {
    let writer = NoteWriter(vault: vault, calendar: calendar)
    let note = vault.root.appendingPathComponent("Grouped.md")
    let destination = Destination(url: note, title: "Grouped", kind: .note)
    try await writer.appendIfMissing(capture, to: destination)
    var repeatCapture = capture
    repeatCapture.id = UUID(); repeatCapture.content = .text("Repeat body")
    try await writer.appendIfMissing(repeatCapture, to: destination)
    let repeated = try checkRead(note)
    try require(repeated.components(separatedBy: "### Safari\n").count - 1 == 1, "same source must omit its heading")
    try require(repeated.contains("Hello\n\n" + checkCaptureMarker(repeatCapture.id)), "heading-less capture separator changed")
    try await writer.appendIfMissing(repeatCapture, to: destination)
    let retried = try checkRead(note)
    try require(retried == repeated, "heading-less retry must not duplicate a capture")
    // Heading-like lines in fenced code must not force another heading.
    let handle = try FileHandle(forWritingTo: note)
    try handle.seekToEnd(); try handle.write(contentsOf: Data("\n```markdown\n## code heading\n```\n".utf8)); try handle.close()
    repeatCapture.id = UUID()
    try await writer.appendIfMissing(repeatCapture, to: destination)
    let fenced = try checkRead(note)
    try require(fenced.components(separatedBy: "### Safari\n").count - 1 == 1, "fenced headings must not force re-emission")
    let subheading = Capture(id: UUID(), createdAt: capture.createdAt, content: .subheading("### Details\n next"), source: CaptureSource())
    try await writer.appendIfMissing(subheading, to: destination)
    let beforeRetry = try checkRead(note)
    try await writer.appendIfMissing(subheading, to: destination)
    let subheadingRetried = try checkRead(note)
    try require(subheadingRetried == beforeRetry && beforeRetry.contains("## Details next\n<!-- subheading:"), "subheading must be cleaned and idempotent")
    repeatCapture.id = UUID()
    try await writer.appendIfMissing(repeatCapture, to: destination)
    let afterSubheading = try checkRead(note)
    try require(afterSubheading.components(separatedBy: "### Safari\n").count - 1 == 2, "subheading must force a source heading")
    repeatCapture.id = UUID(); repeatCapture.source.windowTitle = "Other page - Google Chrome"
    try await writer.appendIfMissing(repeatCapture, to: destination)
    let changed = try checkRead(note)
    try require(changed.contains("### Other page\n" + checkCaptureMarker(repeatCapture.id)), "changed source must emit a heading")
    let legacyNote = vault.root.appendingPathComponent("Legacy replay.md")
    let legacy = "# Legacy\n\n### 2026-10-13 14:30 · Safari\n<!-- capture:\(capture.id.uuidString.lowercased()) -->\n\nHello\n"
    try checkWrite(legacy, to: legacyNote)
    try await writer.appendIfMissing(capture, to: Destination(url: legacyNote, title: "Legacy", kind: .note))
    let legacyAfter = try checkRead(legacyNote)
    try require(legacyAfter == legacy, "upgraded replay must not duplicate a complete legacy capture")
    let damaged = vault.root.appendingPathComponent("Interrupted metadata.md")
    let metadataFragment = "# Interrupted\n\n### Safari\n" + checkCaptureMarker(capture.id) + " at=2026-10"
    try checkWrite(metadataFragment, to: damaged)
    try await writer.appendIfMissing(capture, to: Destination(url: damaged, title: "Interrupted", kind: .note))
    let damagedAfter = try checkRead(damaged)
    let recovered = NoteParser.parse(contents: damagedAfter, notePath: damaged.lastPathComponent, titleFallback: "", calendar: calendar)
    try require(damagedAfter.hasPrefix(metadataFragment) && recovered.blocks.filter { $0.captureID == capture.id && $0.body == "Hello" }.count == 1,
                "interrupted metadata must retain its bytes and recover one complete capture")
    // Independent writers must decide under the same lock.
    let concurrent = vault.root.appendingPathComponent("Grouped concurrent.md")
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<20 {
            let item = Capture(id: UUID(), createdAt: capture.createdAt, content: .text("Concurrent body"), source: capture.source)
            group.addTask {
                let other = NoteWriter(vault: vault, calendar: calendar)
                try await other.appendIfMissing(item, to: Destination(url: concurrent, title: "Concurrent", kind: .note))
            }
        }
        try await group.waitForAll()
    }
    let text = try checkRead(concurrent)
    try require(text.components(separatedBy: "### Safari\n").count - 1 == 1 && text.components(separatedBy: "<!-- capture:").count - 1 == 20,
                "concurrent source decisions must emit one heading and every capture")
}
