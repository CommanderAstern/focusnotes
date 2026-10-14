import Core
import Foundation

func checkVault() throws {
    let root = try checkMakeDirectory("vault")
    defer { checkRemoveDirectory(root) }
    let vault = Vault(root: root)

    try vault.prepare()
    let firstInbox = try checkRead(vault.inboxURL)
    try require(firstInbox == "# Inbox\n", "prepare wrote Inbox.md as \(firstInbox.debugDescription)")
    try checkWrite("# Inbox\n\nkept\n", to: vault.inboxURL)
    try vault.prepare()
    let secondInbox = try checkRead(vault.inboxURL)
    try require(secondInbox == "# Inbox\n\nkept\n", "prepare must not overwrite an existing Inbox.md")
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
    print("Vault checks passed.")
}
