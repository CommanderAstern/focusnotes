import Foundation

public enum NoteTitle {
    /// Trims the title and collapses every run of whitespace to a single space.
    public static func cleanTitle(_ title: String) -> String {
        title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Comparison key for matching a heading to a note title.
    public static func matchKey(_ title: String) -> String {
        cleanTitle(title)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
    }

    /// File name stem (without `.md`) for a note title. Never empty.
    public static func fileStem(for title: String) -> String {
        var replaced = String.UnicodeScalarView()
        for scalar in title.unicodeScalars {
            if scalar == "/" || scalar == "\\" || scalar == ":" || CharacterSet.controlCharacters.contains(scalar) {
                replaced.append("-")
            } else {
                replaced.append(scalar)
            }
        }

        var stem = String(replaced).trimmingCharacters(in: .whitespacesAndNewlines)
        while stem.hasPrefix(".") {
            stem.removeFirst()
            stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        stem = String(stem.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Untitled" : stem
    }
}
