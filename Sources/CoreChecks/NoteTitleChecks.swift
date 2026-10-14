import Core

func checkNoteTitle() throws {
    try require(
        NoteTitle.cleanTitle("  Rate   Limiting \n") == "Rate Limiting",
        "cleanTitle should trim and collapse whitespace"
    )
    try require(
        NoteTitle.matchKey("  Rate   Limiting ") == NoteTitle.matchKey("rate limiting"),
        "matchKey should ignore case and extra whitespace"
    )
    try require(
        NoteTitle.matchKey("Caf\u{00E9}") == NoteTitle.matchKey("cafe"),
        "matchKey should ignore diacritics"
    )
    try require(
        NoteTitle.matchKey("Caf\u{0065}\u{0301}") == NoteTitle.matchKey("CAFE"),
        "matchKey should treat decomposed accents the same as composed ones"
    )
    try require(
        NoteTitle.matchKey("Foo") != NoteTitle.matchKey("Foo 2"),
        "matchKey should keep distinct titles distinct"
    )
    try require(NoteTitle.fileStem(for: "a/b:c") == "a-b-c", "fileStem should replace / and :")
    try require(NoteTitle.fileStem(for: "a\\b") == "a-b", "fileStem should replace backslash")
    try require(NoteTitle.fileStem(for: "Plan\u{0007}X") == "Plan-X", "fileStem should replace control characters")
    try require(NoteTitle.fileStem(for: ".hidden") == "hidden", "fileStem should strip leading dots")
    try require(NoteTitle.fileStem(for: "   ") == "Untitled", "a blank title should become Untitled")
    try require(NoteTitle.fileStem(for: "..") == "Untitled", "a dots-only title should become Untitled")
    let longStem = NoteTitle.fileStem(for: String(repeating: "a", count: 200))
    try require(longStem.count == 120, "fileStem should truncate to 120 characters, got \(longStem.count)")
    print("NoteTitle checks passed.")
}
