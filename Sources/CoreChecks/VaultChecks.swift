import Core
import Darwin
import Foundation

func checkVault() throws {
    let root = try checkMakeDirectory("vault")
    defer { checkRemoveDirectory(root) }
    let vault = Vault(root: root)

    try vault.prepare()
    let firstInbox = try checkRead(vault.inboxURL)
    try require(firstInbox == "# Inbox\n", "prepare wrote Inbox.md as \(firstInbox.debugDescription)")
    let initialMode = try FileManager.default.attributesOfItem(atPath: vault.inboxURL.path)[.posixPermissions] as? NSNumber
    try require(initialMode?.intValue == 0o600, "new Inbox.md should be private (0600)")
    try checkWrite("# Inbox\n\nkept\n", to: vault.inboxURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: vault.inboxURL.path)
    try vault.prepare()
    let secondInbox = try checkRead(vault.inboxURL)
    try require(secondInbox == "# Inbox\n\nkept\n", "prepare must not overwrite an existing Inbox.md")
    let existingMode = try FileManager.default.attributesOfItem(atPath: vault.inboxURL.path)[.posixPermissions] as? NSNumber
    try require(existingMode?.intValue == 0o600, "prepare must migrate a legacy readable Inbox.md to owner-only access")
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: vault.inboxURL.path)
    try vault.prepare()
    let readOnlyMode = try FileManager.default.attributesOfItem(atPath: vault.inboxURL.path)[.posixPermissions] as? NSNumber
    try require(readOnlyMode?.intValue == 0o400, "privacy migration must preserve an owner's read-only mode")
    let readOnlyContents = try checkRead(vault.inboxURL)
    try require(readOnlyContents == secondInbox, "permission migration must preserve Inbox contents")
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: vault.inboxURL.path)
    try checkInboxLinks()
    try require(FileManager.default.fileExists(atPath: vault.sessionsURL.path), "prepare should create Sessions/")
    try require(FileManager.default.fileExists(atPath: vault.assetsURL.path), "prepare should create assets/")

    try checkWrite("# Alpha Title  \nbody\n", to: root.appendingPathComponent("Alpha.md"))
    try checkWrite("no heading here\n", to: root.appendingPathComponent("Beta.md"))
    try checkWrite("\u{FEFF}# BOM Title\n", to: root.appendingPathComponent("Bom.md"))
    try checkWrite("# Hidden\n", to: root.appendingPathComponent(".Hidden.md"))
    try checkWrite("# Not markdown\n", to: root.appendingPathComponent("notes.txt"))
    try checkWrite("# 2026-10-13 Design\n", to: vault.sessionsURL.appendingPathComponent("2026-10-13 Design.md"))
    try checkWrite("plain session\n", to: vault.sessionsURL.appendingPathComponent("Plain.md"))

    let listed = try vault.listNotes().map { "\(checkKindName($0.kind))|\($0.title)" }
    let expectedList = [
        "note|Alpha Title",
        "note|Beta",
        "note|BOM Title",
        "inbox|Inbox",
        "session|2026-10-13 Design",
        "session|Plain",
    ]
    try require(listed == expectedList, "listNotes returned \(listed)")

    try require(
        vault.uniqueNoteURL(forTitle: "Foo").lastPathComponent == "Foo.md",
        "a free title should map to Foo.md"
    )
    try checkWrite("# Foo\n", to: root.appendingPathComponent("Foo.md"))
    try require(
        vault.uniqueNoteURL(forTitle: "Foo").lastPathComponent == "Foo 2.md",
        "a taken Foo.md should map to Foo 2.md"
    )
    try checkWrite("# Foo 2\n", to: root.appendingPathComponent("Foo 2.md"))
    try require(
        vault.uniqueNoteURL(forTitle: "Foo").lastPathComponent == "Foo 3.md",
        "a taken Foo 2.md should map to Foo 3.md"
    )
    try checkUnsafeNoteListing()
    try checkSelectedRootSymlink()
    try checkRootAnchorAdoptsExternalCreation()
    print("Vault checks passed.")
}

private func checkUnsafeNoteListing() throws {
    let base = try checkMakeDirectory("vault-listing-links")
    defer { checkRemoveDirectory(base) }
    let root = base.appendingPathComponent("Vault", isDirectory: true)
    let vault = Vault(root: root)
    try vault.prepare()
    let outside = base.appendingPathComponent("outside.md")
    try checkWrite("# Outside title\nprivate body\n", to: outside)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Symlink.md"), withDestinationURL: outside)
    try FileManager.default.linkItem(at: outside, to: root.appendingPathComponent("Hardlink.md"))
    let fifo = root.appendingPathComponent("Waiting.md")
    try require(mkfifo(fifo.path, 0o600) == 0, "could not create FIFO fixture")

    let names = try vault.listNotes().map(\.url.lastPathComponent)
    let repeatedNames = try vault.listNotes().map(\.url.lastPathComponent)
    try require(names == repeatedNames, "repeated descriptor-backed listings must return the same notes")
    try require(!names.contains("Symlink.md"), "listNotes must skip symlink notes")
    try require(!names.contains("Hardlink.md"), "listNotes must skip hard-linked notes")
    try require(!names.contains("Waiting.md"), "listNotes must skip FIFOs without blocking")
}

private func checkSelectedRootSymlink() throws {
    let base = try checkMakeDirectory("vault-root-symlink")
    defer { checkRemoveDirectory(base) }
    let target = base.appendingPathComponent("target", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let alias = base.appendingPathComponent("alias", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
    let vault = Vault(root: alias)
    let targetVault = Vault(root: target)
    try vault.prepare()
    try require(vault.root.standardizedFileURL.path == targetVault.root.standardizedFileURL.path,
                "Vault should resolve a user-selected root symlink once")
    try require(FileManager.default.fileExists(atPath: target.appendingPathComponent("Inbox.md").path),
                "a resolved vault root symlink should remain writable")
}

private func checkRootAnchorAdoptsExternalCreation() throws {
    let base = try checkMakeDirectory("vault-root-created-later")
    defer { checkRemoveDirectory(base) }
    let root = base.appendingPathComponent("Vault", isDirectory: true)
    let vault = Vault(root: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let emptyListing = try vault.listNotes()
    try require(emptyListing.isEmpty, "an absent Sessions directory should be treated as an empty listing")
    let sessionDirectory = vault.sessionsURL
    try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
    let note = sessionDirectory.appendingPathComponent("External.md")
    try checkWrite("# External\nbody\n", to: note)

    guard let snapshot = try vault.fileSnapshot(relativePath: "Sessions/External.md"),
          let contents = snapshot.contents else {
        throw CheckFailure.failed("a root created after Vault initialization should be adopted for safe reads")
    }
    try require(String(decoding: contents, as: UTF8.self) == "# External\nbody\n",
                "the adopted root snapshot returned wrong bytes")
    let listed = try vault.listNotes()
    try require(listed.contains { $0.title == "External" && $0.kind == .session },
                "descriptor-backed listing should adopt an externally created root")
}

private func checkInboxLinks() throws {
    let root = try checkMakeDirectory("inbox-links")
    defer { checkRemoveDirectory(root) }
    let outside = root.appendingPathComponent("Outside.md")
    try checkWrite("outside bytes\n", to: outside)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: outside.path)
    let vault = Vault(root: root.appendingPathComponent("vault"))
    try FileManager.default.createDirectory(at: vault.root, withIntermediateDirectories: true)
    for symbolic in [true, false] {
        if symbolic { try FileManager.default.createSymbolicLink(at: vault.inboxURL, withDestinationURL: outside) }
        else { try FileManager.default.linkItem(at: outside, to: vault.inboxURL) }
        do {
            try vault.prepare()
            throw CheckFailure.failed("prepare must reject a linked Inbox instead of changing an outside target")
        } catch is CheckFailure { throw CheckFailure.failed("linked Inbox unexpectedly accepted") }
        catch {}
        let mode = try FileManager.default.attributesOfItem(atPath: outside.path)[.posixPermissions] as? NSNumber
        try require(mode?.intValue == 0o644, "prepare must leave an outside linked target's permissions untouched")
        let contents = try checkRead(outside)
        try require(contents == "outside bytes\n", "prepare must leave an outside linked target's content untouched")
        try FileManager.default.removeItem(at: vault.inboxURL)
    }
}
