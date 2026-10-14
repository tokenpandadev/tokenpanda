import AppKit
import CoreText
import Text

/// The menu bar item as a template image: the weekly percentage in SF with tabular digits at 13 pt, a 5 pt gap,
/// a 5 cell block bar at 9 pt in SF Mono. Monochrome; the OS inverts it on a light menu bar. As the approved
/// draft chose: no tick in the bar, the semibold figure carries over pace.
public enum ItemImage {
    // nonisolated: NSImage and NSFont are usable off the main actor; the item is also drawn by the snapshot flag
    public static let height: CGFloat = 22
    public static let barCells = 5
    public static let gap: CGFloat = 5
    static var barFont: NSFont { NSFont.monospacedSystemFont(ofSize: 9, weight: .regular) }
    static var glyphFont: NSFont { NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) }

    static func width(_ s: NSAttributedString) -> CGFloat {
        CTLineGetTypographicBounds(CTLineCreateWithAttributedString(s), nil, nil, nil)
    }

    public static func make(_ st: ItemState) -> NSImage {
        let digitsFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: st.over ? .semibold : .regular)
        let barFont = Self.barFont, glyphFont = Self.glyphFont
        let black = NSColor.black
        let digits = st.used.map { NSAttributedString(string: "\($0)%", attributes: [.font: digitsFont, .foregroundColor: black]) }
        let cell = width(NSAttributedString(string: "0", attributes: [.font: barFont]))
        let barW = cell * CGFloat(barCells)
        let warn = st.warn ? NSAttributedString(string: "\u{26A0}", attributes: [.font: glyphFont, .foregroundColor: black]) : nil
        let mac = st.macText.map { NSAttributedString(string: $0, attributes: [.font: digitsFont, .foregroundColor: black]) }
        var w: CGFloat = 4
        if let d = digits { w += width(d) + gap }
        w += barW
        if let a = warn { w += gap + width(a) }
        if let m = mac { w += width(m) }
        w += 4
        let size = NSSize(width: ceil(w), height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            var x: CGFloat = 4
            func draw(_ s: NSAttributedString, baselineFrom font: NSFont) {
                let line = CTLineCreateWithAttributedString(s)
                let ascent = font.ascender, descent = -font.descender
                let baseline = (height - (ascent + descent)) / 2 + ascent
                ctx.saveGState()
                ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
                ctx.textPosition = CGPoint(x: x, y: baseline)
                CTLineDraw(line, ctx)
                ctx.restoreGState()
                x += width(s)
            }
            if let d = digits { draw(d, baselineFrom: digitsFont); x += gap }
            // the 5 cell bar: track at 28% behind, full cells solid, one eighth block
            let top = (height - 10) / 2
            let glyphs = Bar.glyphs(width: barCells, used: Double(st.used ?? 0))
            let fill = Bar.fill(width: barCells, used: Double(st.used ?? 0))
            let barFontAscent = barFont.ascender, barFontDescent = -barFont.descender
            let barBaseline = top + (10 - (barFontAscent + barFontDescent)) / 2 + barFontAscent
            func glyphRun(_ s: String, alpha: CGFloat, at gx: CGFloat) {
                let a = NSAttributedString(string: s, attributes: [.font: barFont, .foregroundColor: black.withAlphaComponent(alpha)])
                let line = CTLineCreateWithAttributedString(a)
                ctx.saveGState()
                ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
                ctx.textPosition = CGPoint(x: gx, y: barBaseline)
                CTLineDraw(line, ctx)
                ctx.restoreGState()
            }
            glyphRun(String(repeating: String(Bar.full), count: barCells), alpha: 0.28, at: x)
            if fill.fullCells > 0 {
                // the glyph ink box, so the solid run closes the hairlines between blocks
                var chars = Array(String(Bar.full).utf16)
                var g = [CGGlyph](repeating: 0, count: 1)
                let used = CTFontCreateForString(barFont as CTFont, String(Bar.full) as CFString, CFRange(location: 0, length: 1))
                CTFontGetGlyphsForCharacters(used, &chars, &g, 1)
                var r = CGRect.zero
                CTFontGetBoundingRectsForGlyphs(used, .horizontal, &g, &r, 1)
                let inkTop = barBaseline - r.maxY
                ctx.setFillColor(black.cgColor)
                ctx.fill(CGRect(x: x, y: inkTop, width: cell * CGFloat(fill.fullCells), height: r.height))
            }
            let rest = String(glyphs.dropFirst(fill.fullCells))
            glyphRun(String(glyphs.prefix(fill.fullCells)), alpha: 1, at: x)
            glyphRun(rest, alpha: 1, at: x + cell * CGFloat(fill.fullCells))
            x += barW
            if let a = warn { x += gap; draw(a, baselineFrom: glyphFont) }
            if let m = mac { draw(m, baselineFrom: digitsFont) }
            return true
        }
        image.isTemplate = true
        return image
    }
}
