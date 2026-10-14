import AppKit

/// Attributes only: the underlying Markdown and all UTF-16 offsets stay intact.
@MainActor
public enum MarkdownStyler {
    public typealias Span = (range: NSRange, attributes: [NSAttributedString.Key: Any])
    /// A layout decoration, independent of font/color runs within a code block.
    public static let fencedCodeBlock = NSAttributedString.Key("OverlayKit.fencedCodeBlock")
    public static let inlineCode = NSAttributedString.Key("OverlayKit.inlineCode")

    public static let syntax = NSAttributedString.Key("OverlayKit.markdownSyntax")
    public static let element = NSAttributedString.Key("OverlayKit.markdownElement")
    public static let bullet = NSAttributedString.Key("OverlayKit.bullet")
    public static let task = NSAttributedString.Key("OverlayKit.task")
    public static let taskIndent = NSAttributedString.Key("OverlayKit.taskIndent")
    public static let quote = NSAttributedString.Key("OverlayKit.quote")
    public static let rawParagraph = NSAttributedString.Key("OverlayKit.rawParagraph")
    public static let previewParagraph = NSAttributedString.Key("OverlayKit.previewParagraph")

    public enum ElementKind: Hashable {
        case blockMarker
        case headingLine
        case inlineSpan
    }

    public struct Element: Hashable {
        public let range: NSRange
        public let kind: ElementKind

        public init(range: NSRange, kind: ElementKind) {
            self.range = range
            self.kind = kind
        }
    }

    public static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = OverlayTheme.editorLineHeightMultiple
        return [.font: OverlayTheme.editorFont, .foregroundColor: OverlayTheme.textColor,
                .paragraphStyle: paragraph]
    }

    /// Large documents restrict attribute generation to edited paragraphs. Fence
    /// context is scanned as plain lines, without running inline expressions there.
    public static func styles(_ text: String, in requested: NSRange? = nil) -> [Span] {
        let source = text as NSString
        let target = requested ?? NSRange(location: 0, length: source.length)
        var spans: [Span] = []
        var fence: (character: unichar, length: Int)?
        func add(_ range: NSRange, _ attributes: [NSAttributedString.Key: Any]) {
            let intersection = NSIntersectionRange(range, target)
            if intersection.length > 0 { spans.append((intersection, attributes)) }
        }
        var expressions: [String: NSRegularExpression] = [:]
        func matches(_ pattern: String, _ range: NSRange) -> [NSTextCheckingResult] {
            let regex: NSRegularExpression
            if let cached = expressions[pattern] { regex = cached }
            else {
                guard let compiled = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return [] }
                expressions[pattern] = compiled; regex = compiled
            }
            return regex.matches(in: text, range: range)
        }
        var offset = 0
        while offset < source.length {
            let line = source.lineRange(for: NSRange(location: offset, length: 0))
            let value = source.substring(with: line) as NSString
            let trimmed = value.trimmingCharacters(in: .newlines) as NSString
            var indent = 0
            while indent < trimmed.length, trimmed.character(at: indent) == 32 { indent += 1 }
            var run = 0
            let first: unichar = indent < trimmed.length ? trimmed.character(at: indent) : 0
            if indent <= 3, first == 96 || first == 126 {
                while indent + run < trimmed.length, trimmed.character(at: indent + run) == first { run += 1 }
            }
            let rest = trimmed.substring(from: min(trimmed.length, indent + run))
            var fenceLine = false
            if let current = fence {
                if first == current.character, run >= current.length,
                   rest.trimmingCharacters(in: .whitespaces).isEmpty { fence = nil; fenceLine = true }
            } else if run >= 3, first != 96 || !rest.contains("`") {
                fence = (first, run); fenceLine = true
            }
            if fence != nil || fenceLine {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineHeightMultiple = OverlayTheme.editorLineHeightMultiple
                paragraph.firstLineHeadIndent = OverlayTheme.codeBlockInset
                paragraph.headIndent = OverlayTheme.codeBlockInset
                paragraph.tailIndent = -OverlayTheme.codeBlockInset
                add(line, [.font: OverlayTheme.editorCodeFont, .paragraphStyle: paragraph, fencedCodeBlock: true])
                if fenceLine { add(line, [.foregroundColor: OverlayTheme.tertiaryColor]) }
                offset = NSMaxRange(line); continue
            }
            guard NSIntersectionRange(line, target).length > 0 else { offset = NSMaxRange(line); continue }
            var lineFont = OverlayTheme.editorFont
            if let heading = matches("^#+ ", line).first {
                let level = heading.range.length - 1
                lineFont = OverlayTheme.editorHeadingFonts[min(level, 4) - 1]
                add(line, [.font: lineFont, .foregroundColor: OverlayTheme.editorHeadingColor])
                let contentLength = (trimmed as NSString).length
                let element = Element(range: NSRange(location: line.location, length: contentLength), kind: .headingLine)
                add(heading.range, [.foregroundColor: OverlayTheme.tertiaryColor, syntax: true, Self.element: element])
            }
            if let list = matches(#"^([ \t]*)([-*+] (?:\[[ xX]\] )?|[0-9]+\. )"#, line).first {
                let marker = NSRange(location: line.location, length: list.range.length)
                let itemMarker = list.range(at: 2)
                let blockElement = Element(range: itemMarker, kind: .blockMarker)
                add(itemMarker, [Self.element: blockElement])
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineHeightMultiple = OverlayTheme.editorLineHeightMultiple
                var displayedMarker = source.substring(with: marker)
                let first = source.character(at: itemMarker.location)
                if first == 45 || first == 42 || first == 43 {
                    add(NSRange(location: itemMarker.location, length: 1), [bullet: true, .font: OverlayTheme.editorBulletFont])
                    displayedMarker = (displayedMarker as NSString).replacingCharacters(in: NSRange(location: itemMarker.location - marker.location, length: 1), with: OverlayTheme.editorBullet)
                }
                paragraph.headIndent = (displayedMarker as NSString).size(withAttributes: [.font: OverlayTheme.editorFont]).width
                if first == 45 || first == 42 || first == 43 {
                    let bullet = OverlayTheme.editorBullet as NSString
                    paragraph.headIndent += bullet.size(withAttributes: [.font: OverlayTheme.editorBulletFont]).width - bullet.size(withAttributes: [.font: OverlayTheme.editorFont]).width
                }
                add(line, [.paragraphStyle: paragraph])
                add(marker, [.foregroundColor: OverlayTheme.secondaryColor])
                let markerText = source.substring(with: marker)
                if markerText.contains("[") {
                    let checked = markerText.lowercased().contains("[x]")
                    let indentation = (source.substring(with: list.range(at: 1)) as NSString).size(withAttributes: [.font: OverlayTheme.editorFont]).width
                    let preview = paragraph.mutableCopy() as! NSMutableParagraphStyle
                    preview.firstLineHeadIndent = indentation + OverlayTheme.editorCheckboxSize + OverlayTheme.editorCheckboxGap
                    preview.headIndent = preview.firstLineHeadIndent
                    add(line, [rawParagraph: paragraph, previewParagraph: preview])
                    add(itemMarker, [syntax: true, Self.element: blockElement, task: checked, taskIndent: indentation])
                }
                if markerText.lowercased().contains("[x]") {
                    add(NSRange(location: NSMaxRange(marker), length: NSMaxRange(line) - NSMaxRange(marker)),
                        [.foregroundColor: OverlayTheme.secondaryColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue])
                }
            } else if let quote = matches("^> ", line).first {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineHeightMultiple = OverlayTheme.editorLineHeightMultiple
                paragraph.headIndent = OverlayTheme.editorQuoteIndent
                let preview = paragraph.mutableCopy() as! NSMutableParagraphStyle
                preview.firstLineHeadIndent = OverlayTheme.editorQuoteIndent
                let blockElement = Element(range: quote.range, kind: .blockMarker)
                add(line, [.foregroundColor: OverlayTheme.secondaryColor, .paragraphStyle: paragraph, Self.quote: true,
                           rawParagraph: paragraph, previewParagraph: preview])
                add(quote.range, [.foregroundColor: OverlayTheme.tertiaryColor, syntax: true, Self.element: blockElement])
            }

            // Mask inline code and links before emphasis, so punctuation in a URL
            // or a code sample never becomes an emphasis delimiter.
            let codes = matches(#"(`+)([^`\r\n]+)\1"#, line)
            let links = matches(#"\[([^\]\r\n]+)\]\(([^)\r\n]+)\)|https?://[^\s<>]+"#, line)
            let protected = codes.map(\.range) + links.map(\.range)
            func emphasis(_ pattern: String, _ attrs: [NSAttributedString.Key: Any]) {
                for match in matches(pattern, line) where !protected.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    add(match.range(at: 2), attrs)
                    let element = Element(range: match.range, kind: .inlineSpan)
                    add(match.range(at: 1), [.foregroundColor: OverlayTheme.tertiaryColor, syntax: true, Self.element: element])
                    let end = NSMaxRange(match.range(at: 2))
                    add(NSRange(location: end, length: NSMaxRange(match.range) - end),
                        [.foregroundColor: OverlayTheme.tertiaryColor, syntax: true, Self.element: element])
                }
            }
            emphasis(#"(\*\*|__)(?=\S)(.+?\S|\S)\1"#, [.font: NSFont.systemFont(ofSize: lineFont.pointSize, weight: .semibold)])
            let italic = NSFont(descriptor: lineFont.fontDescriptor.withSymbolicTraits(lineFont.fontDescriptor.symbolicTraits.union(.italic)), size: lineFont.pointSize) ?? lineFont
            emphasis(#"(?<![\w*_])(\*|_)(?=\S)([^*_\r\n]+?\S|[^\s*_])\1(?![\w*_])"#, [.font: italic])
            emphasis(#"(~~)(?=\S)(.+?\S|\S)\1"#, [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
            for code in codes {
                add(code.range, [.font: OverlayTheme.editorCodeFont, inlineCode: true])
                let element = Element(range: code.range, kind: .inlineSpan)
                add(code.range(at: 1), [.foregroundColor: OverlayTheme.tertiaryColor, syntax: true, Self.element: element])
                add(NSRange(location: NSMaxRange(code.range(at: 2)), length: code.range(at: 1).length),
                    [.foregroundColor: OverlayTheme.tertiaryColor, syntax: true, Self.element: element])
            }
            for link in links where !codes.contains(where: { NSIntersectionRange($0.range, link.range).length > 0 }) {
                if link.range(at: 1).location == NSNotFound { add(link.range, [.foregroundColor: OverlayTheme.editorLinkColor]) }
                else {
                    add(link.range, [.foregroundColor: OverlayTheme.tertiaryColor])
                    let label = link.range(at: 1)
                    let element = Element(range: link.range, kind: .inlineSpan)
                    add(NSRange(location: link.range.location, length: label.location - link.range.location),
                        [syntax: true, Self.element: element])
                    add(NSRange(location: NSMaxRange(label), length: NSMaxRange(link.range) - NSMaxRange(label)),
                        [syntax: true, Self.element: element])
                    add(label, [.foregroundColor: OverlayTheme.editorLinkColor])
                }
            }
            offset = NSMaxRange(line)
        }
        return spans
    }
}
