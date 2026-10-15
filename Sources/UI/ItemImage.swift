// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import AppKit
import CoreText
import Text

/// The menu bar item as a template image: the panda from the app icon as a 7 by 7 pixel mark, a 5 pt gap, then
/// the weekly percentage in SF with tabular digits at 13 pt. Monochrome; the OS inverts it on a light menu bar. The
/// panda's eyes and nose are left open so the mark reads at menu bar size. The semibold figure carries over pace.
public enum ItemImage {
    // nonisolated: NSImage and NSFont are usable off the main actor; the item is also drawn by the snapshot flag
    public static let height: CGFloat = 22
    public static let gap: CGFloat = 5
    /// Side of one panda pixel in points; seven of them make the mark.
    static let cell: CGFloat = 2
    static var glyphFont: NSFont { NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) }

    /// The panda, row by row from the top: ears, head, the eye patches and the nose left open. Same grid as the app icon.
    static let panda = [
        "XX...XX",
        "XXXXXXX",
        "XXXXXXX",
        "X..X..X",
        "X.XXX.X",
        "XXX.XXX",
        ".XXXXX.",
    ]

    static func width(_ s: NSAttributedString) -> CGFloat {
        CTLineGetTypographicBounds(CTLineCreateWithAttributedString(s), nil, nil, nil)
    }

    public static func make(_ st: ItemState) -> NSImage {
        let digitsFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: st.over ? .semibold : .regular)
        let glyphFont = Self.glyphFont
        let black = NSColor.black
        let digits = st.used.map { NSAttributedString(string: "\($0)%", attributes: [.font: digitsFont, .foregroundColor: black]) }
        let markW = cell * CGFloat(panda[0].count)
        let warn = st.warn ? NSAttributedString(string: "\u{26A0}", attributes: [.font: glyphFont, .foregroundColor: black]) : nil
        let mac = st.macText.map { NSAttributedString(string: $0, attributes: [.font: digitsFont, .foregroundColor: black]) }
        var w: CGFloat = 4 + markW
        if let d = digits { w += gap + width(d) }
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
            // the panda on whole points, centred on the item's height
            let top = ((height - cell * CGFloat(panda.count)) / 2).rounded()
            ctx.setFillColor(black.cgColor)
            for (r, row) in panda.enumerated() {
                for (c, ch) in row.enumerated() where ch == "X" {
                    ctx.fill(CGRect(x: x + cell * CGFloat(c), y: top + cell * CGFloat(r), width: cell, height: cell))
                }
            }
            x += markW
            if let d = digits { x += gap; draw(d, baselineFrom: digitsFont) }
            if let a = warn { x += gap; draw(a, baselineFrom: glyphFont) }
            if let m = mac { draw(m, baselineFrom: digitsFont) }
            return true
        }
        image.isTemplate = true
        return image
    }
}
