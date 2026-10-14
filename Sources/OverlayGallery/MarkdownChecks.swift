import AppKit
import OverlayKit

let editorSample = """
## Working notes
**bold** *italic* `code` ~~strike~~ [link](https://example.com)
- A long item that wraps and keeps its text aligned after the visible Markdown marker, even on a second line.
- [ ] Follow up
- [x] Reviewed
> Keep the source in context.
```swift
let message = "Hello"
print(message)
// **plain code**
```
"""

@MainActor
func checkMarkdownStyler() throws {
    let text = editorSample + "\n# One\n### Three\n#### Four\n####### Deep\n__strong__ _emphasis_\n1. Numbered\n+ Plus\nhttps://example.org\n😀 **unicode**"
    let source = text as NSString
    let result = NSMutableAttributedString(string: text, attributes: MarkdownStyler.baseAttributes)
    let spans = MarkdownStyler.styles(text)
    for span in spans {
        guard span.range.location >= 0, NSMaxRange(span.range) <= source.length else { throw GalleryError("Styler produced invalid UTF-16 range") }
        result.addAttributes(span.attributes, range: span.range)
    }
    func attrs(_ token: String) throws -> [NSAttributedString.Key: Any] {
        let range = source.range(of: token)
        guard range.location != NSNotFound else { throw GalleryError("Missing style fixture: \(token)") }
        return result.attributes(at: range.location, effectiveRange: nil)
    }
    func expect(_ condition: Bool, _ message: String) throws { if !condition { throw GalleryError(message) } }
    try expect((try attrs("Working notes")[.font] as? NSFont)?.pointSize == 19, "H2 font")
    for (token, size) in [("One", CGFloat(22)), ("Three", CGFloat(17)), ("Four", CGFloat(15)), ("Deep", CGFloat(15))] {
        try expect((try attrs(token)[.font] as? NSFont)?.pointSize == size, "Heading font: \(token)")
    }
    try expect((try attrs("## ")[.foregroundColor] as? NSColor) == OverlayTheme.tertiaryColor, "Heading delimiters")
    for token in ["bold", "strong", "unicode"] {
        try expect((try attrs(token)[.font] as? NSFont) == OverlayTheme.editorStrongFont, "Bold range: \(token)")
    }
    for token in ["italic", "emphasis"] {
        try expect((try attrs(token)[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) == true, "Italic trait: \(token)")
    }
    try expect((try attrs("code")[.font] as? NSFont) == OverlayTheme.editorCodeFont, "Inline code font")
    try expect(try attrs("code")[MarkdownStyler.inlineCode] as? Bool == true && attrs("code")[.backgroundColor] == nil, "Inline code uses one padded rounded decoration")
    try expect((try attrs("strike")[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue, "Strike range")
    try expect((try attrs("- A")[.foregroundColor] as? NSColor) == OverlayTheme.secondaryColor, "Bullet marker range")
    try expect((try attrs("- A")[.font] as? NSFont) == OverlayTheme.editorBulletFont && OverlayTheme.editorBulletFont.pointSize == OverlayTheme.editorFont.pointSize,
               "Bullet glyph must use the body font size at semibold weight")
    try expect((try attrs("1. ")[.foregroundColor] as? NSColor) == OverlayTheme.secondaryColor, "Numbered marker range")
    try expect((try attrs("+ ")[.foregroundColor] as? NSColor) == OverlayTheme.secondaryColor, "Plus marker range")
    try expect((try attrs("A long")[.paragraphStyle] as? NSParagraphStyle)?.headIndent ?? 0 > 0, "Hanging list indent")
    try expect((try attrs("- [ ]")[.foregroundColor] as? NSColor) == OverlayTheme.secondaryColor, "Task marker range")
    try expect((try attrs("Reviewed")[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue, "Completed task strike")
    try expect((try attrs("Reviewed")[.foregroundColor] as? NSColor) == OverlayTheme.secondaryColor, "Completed task color")
    try expect((try attrs("> ")[.foregroundColor] as? NSColor) == OverlayTheme.tertiaryColor, "Quote marker")
    try expect((try attrs("Keep")[.paragraphStyle] as? NSParagraphStyle)?.headIndent == OverlayTheme.editorQuoteIndent, "Quote indent")
    try expect((try attrs("link")[.foregroundColor] as? NSColor) == OverlayTheme.editorLinkColor, "Link text range")
    try expect((try attrs("](https:")[.foregroundColor] as? NSColor) == OverlayTheme.tertiaryColor, "Link punctuation range")
    try expect((try attrs("https://example.org")[.foregroundColor] as? NSColor) == OverlayTheme.editorLinkColor, "Bare URL range")
    try expect((try attrs("```swift")[.foregroundColor] as? NSColor) == OverlayTheme.tertiaryColor, "Fence delimiter range")
    try expect(try attrs("```swift")[MarkdownStyler.fencedCodeBlock] as? Bool == true, "Opening fence block decoration")
    try expect(try attrs("let message")[MarkdownStyler.fencedCodeBlock] as? Bool == true, "Code block decoration")
    let closing = source.range(of: "```", options: .backwards)
    try expect(result.attribute(MarkdownStyler.fencedCodeBlock, at: closing.location, effectiveRange: nil) as? Bool == true,
               "Closing fence must receive the full-width block decoration")
    try expect(try attrs("let message")[.backgroundColor] == nil, "Block fill must not also draw behind individual glyphs")
    for (name, alpha, white) in [(NSAppearance.Name.aqua, CGFloat(0.05), CGFloat(0)), (.darkAqua, CGFloat(0.09), CGFloat(1))] {
        guard let appearance = NSAppearance(named: name) else { throw GalleryError("Missing code-fill appearance") }
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance { resolved = OverlayTheme.codeBackground.usingColorSpace(.deviceRGB) }
        guard let color = resolved else { throw GalleryError("Code color did not resolve") }
        try expect(abs(color.alphaComponent - alpha) < 0.001 && abs(color.redComponent - white) < 0.001,
                   "Code background must resolve its tint/opacity for \(name)")
    }
    try expect((try attrs("**plain code**")[.font] as? NSFont) == OverlayTheme.editorCodeFont, "No emphasis inside fenced code")
    try expect((try attrs("**plain code**")[.foregroundColor] as? NSColor) == OverlayTheme.textColor, "Code punctuation must retain body color")
    let fenceText = "```\n# heading **bold** *italic* [link](https://example.com) ~~strike~~\n```"
    let fenceStyles = MarkdownStyler.styles(fenceText)
    let interior = (fenceText as NSString).range(of: "# heading **bold** *italic* [link](https://example.com) ~~strike~~")
    try expect(fenceStyles.filter { NSIntersectionRange($0.range, interior).length > 0 }.allSatisfy {
        $0.attributes[.strikethroughStyle] == nil && $0.attributes[.foregroundColor] == nil && ($0.attributes[.font] as? NSFont) == OverlayTheme.editorCodeFont
    }, "No inline or heading styling inside fences")
    let large = String(repeating: editorSample + "\n", count: 50)
    let largeSource = large as NSString
    let paragraph = largeSource.paragraphRange(for: NSRange(location: largeSource.range(of: "Reviewed").location, length: 1))
    let start = ContinuousClock.now
    for _ in 0..<10 { _ = MarkdownStyler.styles(String(large.prefix(20_000))) }
    let elapsed = start.duration(to: .now)
    let limited = MarkdownStyler.styles(large, in: paragraph)
    try expect(!limited.isEmpty && limited.allSatisfy { NSIntersectionRange($0.range, paragraph) == $0.range }, "Large document paragraph cap")
    print("MarkdownStyler checks passed; ten ~20k-character full passes: \(elapsed); large-document paragraph cap verified.")
}

/// Pixel assertions catch appearance/alpha resolution and ragged fence fills in
/// the production view, rather than only checking the styler's attribute values.
@MainActor
func checkEditorCodePixels(_ root: NSView, bitmap: NSBitmapImageRep) throws {
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    guard let text = descendants(root).compactMap({ $0 as? NSTextView }).first(where: { $0.string == editorSample }),
          let manager = text.layoutManager, let container = text.textContainer,
          let tint = OverlayTheme.codeBackground.usingColorSpace(.deviceRGB) else { return }
    let source = text.string as NSString
    func pixel(_ point: NSPoint) throws -> NSColor {
        let x = Int(point.x * OverlayTheme.galleryScale), y = Int(point.y * OverlayTheme.galleryScale)
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { throw GalleryError("Code-fill pixel outside render") }
        return color
    }
    func expectTint(_ point: NSPoint, context: String) throws {
        let base = try pixel(NSPoint(x: OverlayTheme.padding / 2, y: point.y))
        let actual = try pixel(point)
        let alpha = tint.alphaComponent
        let expected = [base.redComponent, base.greenComponent, base.blueComponent].enumerated().map { index, channel in
            let tintChannel = [tint.redComponent, tint.greenComponent, tint.blueComponent][index]
            return channel * (1 - alpha) + tintChannel * alpha
        }
        let channels = [actual.redComponent, actual.greenComponent, actual.blueComponent]
        guard zip(channels, expected).allSatisfy({ abs($0 - $1) < 0.012 }) else {
            throw GalleryError("\(context) code-fill pixels: actual \(channels), expected \(expected)")
        }
    }
    for (label, range) in [("opening fence", source.range(of: "```swift")),
                           ("code body", source.range(of: "let message")),
                           ("closing fence", source.range(of: "```", options: .backwards))] {
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let line = manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        for x in [container.size.width / 2, container.size.width - OverlayTheme.codeBlockInset] {
            let point = text.convert(NSPoint(x: text.textContainerOrigin.x + x, y: text.textContainerOrigin.y + line.midY), to: root)
            try expectTint(point, context: label)
        }
    }
    let inlineGlyphs = manager.glyphRange(forCharacterRange: source.range(of: "`code`"), actualCharacterRange: nil)
    let inline = manager.boundingRect(forGlyphRange: inlineGlyphs, in: container)
    let point = text.convert(NSPoint(x: text.textContainerOrigin.x + inline.midX, y: text.textContainerOrigin.y + inline.minY + 1), to: root)
    try expectTint(point, context: "inline code")
    let bodyGlyphs = manager.glyphRange(forCharacterRange: source.range(of: "code"), actualCharacterRange: nil)
    let body = manager.boundingRect(forGlyphRange: bodyGlyphs, in: container)
    for x in [body.minX - OverlayTheme.inlineCodePadding / 2, body.maxX + OverlayTheme.inlineCodePadding / 2] {
        let padding = text.convert(NSPoint(x: text.textContainerOrigin.x + x, y: text.textContainerOrigin.y + body.midY), to: root)
        try expectTint(padding, context: "inline code horizontal padding")
    }
    print("Code background pixels passed (inline and full-width opening/body/closing fence).")
}
