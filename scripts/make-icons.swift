#!/usr/bin/env swift
// Builds the app icon (1024 master, .iconset, .icns) and the menu bar template icon
// from the app-specific source PNG named in Config/app.env. Run from the repo root:
//   swift scripts/make-icons.swift
// Outputs land in assets/icons/; the intermediate .iconset and preview sheet go to .build/icons/.
import AppKit
import CoreText

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let config = root.appendingPathComponent("Config/app.env")
let configText = try String(contentsOf: config, encoding: .utf8)
let appName = configText.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
    guard let separator = line.firstIndex(of: "="), line[..<separator] == "APPNAME" else { return nil }
    return String(line[line.index(after: separator)...])
}.last
guard let appName else { fatalError("Config/app.env must define APPNAME") }

func isASCIIAlphaNumeric(_ value: UInt32) -> Bool {
    (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
}

let appNameScalars = Array(appName.unicodeScalars)
let isSafeAppName = !appNameScalars.isEmpty &&
    appNameScalars.count <= 63 &&
    isASCIIAlphaNumeric(appNameScalars[0].value) &&
    appNameScalars.dropFirst().allSatisfy {
        isASCIIAlphaNumeric($0.value) || $0.value == 45 || $0.value == 95
    }
guard isSafeAppName else { fatalError("APPNAME must be a safe app-name basename") }

let source = root.appendingPathComponent("assets/\(appName)-app-icon-ligature.png")
let outDir = root.appendingPathComponent("assets/icons")
let scratchDir = root.appendingPathComponent(".build/icons")
let iconsetDir = scratchDir.appendingPathComponent("AppIcon.iconset")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: - Helpers

func bitmap(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func writePNG(_ image: CGImage, _ url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "failed to write \(url.path)")
}

func scaled(_ image: CGImage, _ size: Int) -> CGImage {
    let ctx = bitmap(size, size)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

// Halve repeatedly before the final step so small sizes stay crisp instead of aliased.
func resized(_ image: CGImage, _ size: Int) -> CGImage {
    var img = image
    while img.width >= size * 4 { img = scaled(img, img.width / 2) }
    return scaled(img, size)
}

func color(_ c: SIMD3<Double>, alpha: Double = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [c.x / 255, c.y / 255, c.z / 255, alpha])!
}

// Apple's macOS icon outline is close to a superellipse with n ≈ 5.
func superellipse(_ r: CGRect, n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 1440
    for i in 0..<steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let p = CGPoint(x: r.midX + r.width / 2 * copysign(pow(abs(c), 2 / n), c),
                        y: r.midY + r.height / 2 * copysign(pow(abs(s), 2 / n), s))
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    return path
}

// MARK: - Extract the glyphs from the source artwork as clean, flat-colour alpha

let srcImage = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(source as CFURL, nil)!, 0, nil)!
let w = srcImage.width, h = srcImage.height
let srcCtx = bitmap(w, h)
srcCtx.draw(srcImage, in: CGRect(x: 0, y: 0, width: w, height: h))
let srcBPR = srcCtx.bytesPerRow
let src = srcCtx.data!.assumingMemoryBound(to: UInt8.self)

func pixel(_ x: Int, _ y: Int) -> SIMD3<Double> {
    let i = y * srcBPR + x * 4
    return SIMD3(Double(src[i]), Double(src[i + 1]), Double(src[i + 2]))
}

func mean(_ samples: [SIMD3<Double>]) -> SIMD3<Double> {
    samples.reduce(SIMD3<Double>(repeating: 0), +) / Double(samples.count)
}

var bgSamples: [SIMD3<Double>] = [], inkSamples: [SIMD3<Double>] = [], coralSamples: [SIMD3<Double>] = []
for (x0, y0) in [(0, 0), (w - 60, 0), (0, h - 60), (w - 60, h - 60)] {
    for y in y0..<(y0 + 60) { for x in x0..<(x0 + 60) { bgSamples.append(pixel(x, y)) } }
}
for y in stride(from: 0, to: h, by: 2) {
    for x in stride(from: 0, to: w, by: 2) {
        let p = pixel(x, y)
        if p.x > 200 && p.x - p.y > 100 { coralSamples.append(p) }
        else if p.min() > 215 { inkSamples.append(p) }
    }
}
let bg = mean(bgSamples), ink = mean(inkSamples), coral = mean(coralSamples)

let glyphCtx = bitmap(w, h)
let gBPR = glyphCtx.bytesPerRow
let g = glyphCtx.data!.assumingMemoryBound(to: UInt8.self)
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h {
    for x in 0..<w {
        let d = pixel(x, y) - bg
        // Unmix each pixel against whichever ink explains it best, then flatten its colour.
        var best: (alpha: Double, residual: Double, ink: SIMD3<Double>) = (0, .infinity, ink)
        for k in [ink, coral] {
            let kb = k - bg
            let a = min(max((d * kb).sum() / (kb * kb).sum(), 0), 1)
            let r = d - kb * a
            let residual = (r * r).sum()
            if residual < best.residual { best = (a, residual, k) }
        }
        let a = best.alpha < 0.04 ? 0 : best.alpha
        let i = y * gBPR + x * 4
        g[i] = UInt8((best.ink.x * a).rounded())
        g[i + 1] = UInt8((best.ink.y * a).rounded())
        g[i + 2] = UInt8((best.ink.z * a).rounded())
        g[i + 3] = UInt8((255 * a).rounded())
        if a > 0.25 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    }
}
let pad = 6
let glyphs = glyphCtx.makeImage()!.cropping(to: CGRect(x: minX - pad, y: minY - pad,
                                                       width: maxX - minX + 1 + 2 * pad,
                                                       height: maxY - minY + 1 + 2 * pad))!

// MARK: - App icon master (1024 canvas, 824 body, macOS icon grid)

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = superellipse(body)
let master = bitmap(1024, 1024)

master.saveGState()
master.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
master.addPath(shape)
master.setFillColor(color(bg))
master.fillPath()
master.restoreGState()

master.saveGState()
master.addPath(shape)
master.clip()
let gradient = CGGradient(colorsSpace: sRGB,
                          colors: [color(bg + 16), color(bg - 4)] as CFArray,
                          locations: [0, 1])!
master.drawLinearGradient(gradient, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY),
                          options: [])
master.addPath(shape)
master.setStrokeColor(CGColor(gray: 1, alpha: 0.07))
master.setLineWidth(4)
master.strokePath()
master.restoreGState()

let glyphWidth = body.width * 0.62
let glyphScale = glyphWidth / Double(glyphs.width)
let glyphHeight = Double(glyphs.height) * glyphScale
master.draw(glyphs, in: CGRect(x: 512 - glyphWidth / 2, y: 512 - glyphHeight / 2 + 6,
                               width: glyphWidth, height: glyphHeight))
let masterImage = master.makeImage()!
writePNG(masterImage, outDir.appendingPathComponent("AppIcon-1024.png"))

var appIconBySize: [Int: CGImage] = [1024: masterImage]
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = pt * scale
        let img = appIconBySize[px] ?? resized(masterImage, px)
        appIconBySize[px] = img
        let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
        writePNG(img, iconsetDir.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")

// MARK: - Menu bar template icon (black on transparent, vector PDF)

let serifItalic: CTFont = {
    let base = NSFont.systemFont(ofSize: 100, weight: .medium).fontDescriptor
    let serif = base.withDesign(.serif) ?? base
    return NSFont(descriptor: serif.withSymbolicTraits(.italic), size: 100)! as CTFont
}()

func textPath(_ text: String) -> CGPath {
    let chars = Array(text.utf16)
    var glyphIDs = [CGGlyph](repeating: 0, count: chars.count)
    CTFontGetGlyphsForCharacters(serifItalic, chars, &glyphIDs, chars.count)
    var advances = [CGSize](repeating: .zero, count: chars.count)
    CTFontGetAdvancesForGlyphs(serifItalic, .horizontal, glyphIDs, &advances, chars.count)
    let path = CGMutablePath()
    var x = 0.0
    for (glyph, advance) in zip(glyphIDs, advances) {
        if let p = CTFontCreatePathForGlyph(serifItalic, glyph, nil) {
            path.addPath(p, transform: CGAffineTransform(translationX: x, y: 0))
        }
        x += advance.width
    }
    return path
}

struct TemplateIcon {
    let glyph: CGPath
    let bar: CGPath
    let size: CGSize

    /// `active` adds a small dot after the cursor, used while a capture session is running.
    init(_ text: String, active: Bool = false) {
        let canvasHeight = 18.0, glyphHeight = 16.0, barHeight = 14.0, barWidth = 1.6, gap = 1.6, side = 1.0
        let raw = textPath(text)
        let b = raw.boundingBoxOfPath
        let s = glyphHeight / b.height
        var t = CGAffineTransform(translationX: side, y: (canvasHeight - glyphHeight) / 2)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -b.minX, y: -b.minY)
        glyph = raw.copy(using: &t)!
        let barX = side + b.width * s + gap
        let barRect = CGRect(x: barX, y: (canvasHeight - barHeight) / 2, width: barWidth, height: barHeight)
        let barPath = CGMutablePath()
        barPath.addRoundedRect(in: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2)
        var right = barRect.maxX
        if active {
            let dot = 4.0
            barPath.addEllipse(in: CGRect(x: barRect.maxX + 1.4, y: barRect.maxY - dot, width: dot, height: dot))
            right += 1.4 + dot
        }
        bar = barPath
        size = CGSize(width: (right + side).rounded(.up), height: canvasHeight)
    }

    func draw(in ctx: CGContext, color: CGColor) {
        ctx.setFillColor(color)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(0.4) // slight embolden so hairlines survive at menu bar size
        ctx.setLineJoin(.round)
        ctx.addPath(glyph)
        ctx.drawPath(using: .fillStroke)
        ctx.addPath(bar)
        ctx.fillPath()
    }

    func writePDF(_ url: URL) {
        var box = CGRect(origin: .zero, size: size)
        let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        draw(in: ctx, color: CGColor(gray: 0, alpha: 1))
        ctx.endPDFPage()
        ctx.closePDF()
    }

    func png(scale: Int, color: CGColor = CGColor(gray: 0, alpha: 1)) -> CGImage {
        let ctx = bitmap(Int(size.width) * scale, Int(size.height) * scale)
        ctx.scaleBy(x: Double(scale), y: Double(scale))
        draw(in: ctx, color: color)
        return ctx.makeImage()!
    }
}

let menuIcons = [("MenuBarIcon", TemplateIcon("fn")), ("MenuBarIcon-active", TemplateIcon("fn", active: true))]
for (name, icon) in menuIcons {
    icon.writePDF(outDir.appendingPathComponent("\(name).pdf"))
}

// MARK: - Preview sheet (rendered at 2x, like a Retina display)

let sheetW = 520.0, sheetH = 300.0
let sheet = bitmap(Int(sheetW) * 2, Int(sheetH) * 2)
sheet.scaleBy(x: 2, y: 2)
let light = SIMD3<Double>(236, 236, 236), dark = SIMD3<Double>(30, 30, 30)
for (row, bgColor) in [(1, light), (0, dark)] {
    let y0 = Double(row) * sheetH / 2
    sheet.setFillColor(color(bgColor))
    sheet.fill(CGRect(x: 0, y: y0, width: sheetW, height: sheetH / 2))

    // App icon at 16, 32, 64, 128 pt.
    var x = 16.0
    for pt in [16, 32, 64, 128] {
        let img = appIconBySize[pt * 2] ?? resized(masterImage, pt * 2)
        sheet.draw(img, in: CGRect(x: x, y: y0 + 74 - Double(pt) / 2, width: Double(pt), height: Double(pt)))
        x += Double(pt) + 16
    }

    // Fake menu bar strip with both template variants, tinted the way macOS would.
    let barY = y0 + 6
    sheet.setFillColor(color(row == 1 ? SIMD3(246, 246, 246) : SIMD3(43, 43, 43)))
    sheet.fill(CGRect(x: 300, y: barY, width: 204, height: 24))
    let tint = row == 1 ? CGColor(gray: 0, alpha: 0.85) : CGColor(gray: 1, alpha: 0.9)
    var mx = 320.0
    for (_, icon) in menuIcons {
        sheet.draw(icon.png(scale: 2, color: tint),
                   in: CGRect(x: mx, y: barY + 3, width: icon.size.width, height: icon.size.height))
        mx += icon.size.width + 28
    }
}
writePNG(sheet.makeImage()!, scratchDir.appendingPathComponent("preview.png"))

print("bg \(bg) ink \(ink) coral \(coral)")
print("wrote \(outDir.path)")
