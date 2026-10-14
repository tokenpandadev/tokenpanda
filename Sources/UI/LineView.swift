import AppKit
import CoreText
import Text

extension RGBA {
    public var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

/// Draws lines of SF Mono 12 on the glass: text runs, block bars with their track, the tab inversions,
/// row hover and the tooltip. Cells, not pixels: every piece advances by its cell count.
@MainActor
public final class LineView: NSView {
    public static let lineHeight: CGFloat = 16
    public static let width: CGFloat = 380
    public let padTop: CGFloat = 12
    public let padSide: CGFloat = 10
    public let padBottom: CGFloat = 10

    public var lines: [Line] = [] {
        didSet { hoverLine = nil; hoverTip = nil; rebuildHits(); needsDisplay = true; window?.invalidateCursorRects(for: self) }
    }
    public var onAction: ((Action) -> Void)?
    /// Snapshot mode: paint the draft's stage colour under the tint, since there is no desktop behind an offscreen view.
    public var drawsStage = false

    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    let cellWidth: CGFloat
    let baseline: CGFloat
    let barTop: CGFloat
    let barHeight: CGFloat

    struct Hit { var rect: NSRect; var line: Int; var piece: Int }
    var hits: [Hit] = []
    var hoverLine: Int? = nil
    var hoverTip: (line: Int, piece: Int)? = nil
    var lineCache: [String: CTLine] = [:]

    public override var isFlipped: Bool { true }
    public var contentHeight: CGFloat { padTop + CGFloat(lines.count) * LineView.lineHeight + padBottom }

    public init() {
        let probe = NSAttributedString(string: "0", attributes: [.font: font])
        cellWidth = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(probe), nil, nil, nil)
        let ascent = font.ascender, descent = -font.descender
        baseline = (LineView.lineHeight - (ascent + descent)) / 2 + ascent
        // the block glyph's ink box inside the 16 pt line, measured from the font that renders it
        let ct = font as CTFont
        let s = String(Bar.full) as CFString
        let used = CTFontCreateForString(ct, s, CFRange(location: 0, length: 1))
        var chars = Array(String(Bar.full).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(used, &chars, &glyphs, chars.count)
        var rect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(used, .horizontal, &glyphs, &rect, 1)
        if rect.height > 0 {
            barTop = baseline - rect.maxY
            barHeight = rect.height
        } else {
            barTop = 3; barHeight = 12
        }
        super.init(frame: NSRect(x: 0, y: 0, width: LineView.width, height: 100))
        wantsLayer = false
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Usage")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: layout

    func lineY(_ i: Int) -> CGFloat { padTop + CGFloat(i) * LineView.lineHeight }

    func rebuildHits() {
        hits = []
        for (li, line) in lines.enumerated() {
            var x = padSide
            for (pi, p) in line.pieces.enumerated() {
                let w = CGFloat(p.cells) * cellWidth
                if p.action != nil || p.tip != nil {
                    hits.append(Hit(rect: NSRect(x: x, y: lineY(li), width: w, height: LineView.lineHeight), line: li, piece: pi))
                }
                x += w
            }
        }
        var elements: [NSAccessibilityElement] = []
        for (li, line) in lines.enumerated() {
            let text = line.label ?? line.plain.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let frame = NSRect(x: padSide, y: lineY(li), width: bounds.width - 2 * padSide, height: LineView.lineHeight)
            if let e = NSAccessibilityElement.element(withRole: .staticText, frame: frame, label: text, parent: self) as? NSAccessibilityElement { elements.append(e) }
        }
        setAccessibilityChildren(elements)
    }

    public override func resetCursorRects() {
        for h in hits where lines[h.line].pieces[h.piece].action != nil { addCursorRect(h.rect, cursor: .pointingHand) }
    }

    // MARK: drawing

    func ctLine(_ text: String, bold: Bool, color: RGBA) -> CTLine {
        let key = "\(bold ? 1 : 0)|\(color.r),\(color.g),\(color.b),\(color.a)|\(text)"
        if let l = lineCache[key] { return l }
        if lineCache.count > 4000 { lineCache.removeAll() }
        let attr = NSAttributedString(string: text, attributes: [.font: bold ? boldFont : font, .foregroundColor: color.ns])
        let l = CTLineCreateWithAttributedString(attr)
        lineCache[key] = l
        return l
    }

    func drawRun(_ text: String, bold: Bool, color: RGBA, x: CGFloat, y: CGFloat, cells: Int, wide: Bool, ctx: CGContext) {
        guard !text.isEmpty else { return }
        let line = ctLine(text, bold: bold, color: color)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let expected = CGFloat(cells) * cellWidth
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        if !wide && abs(width - expected) < 0.75 {
            ctx.textPosition = CGPoint(x: x, y: y + baseline)
            CTLineDraw(line, ctx)
        } else {
            // a glyph from another font: each one in its own cell box, left aligned
            let box = wide ? 2 * cellWidth : cellWidth
            var gx = x
            for ch in text {
                let gl = ctLine(String(ch), bold: bold, color: color)
                ctx.textPosition = CGPoint(x: gx, y: y + baseline)
                CTLineDraw(gl, ctx)
                gx += box
            }
        }
        ctx.restoreGState()
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if drawsStage {
            Tokens.stage.ns.setFill(); bounds.fill()
            Tokens.tint.ns.setFill(); bounds.fill()
        }
        for (li, line) in lines.enumerated() {
            let y = lineY(li)
            if hoverLine == li, line.hover {
                Tokens.selection.ns.setFill()
                NSRect(x: padSide, y: y, width: bounds.width - 2 * padSide, height: LineView.lineHeight).fill()
            }
            var x = padSide
            for p in line.pieces {
                let w = CGFloat(p.cells) * cellWidth
                if let bg = p.style.bg {
                    bg.ns.setFill(); NSRect(x: x, y: y, width: w, height: LineView.lineHeight).fill()
                }
                if let bar = p.bar {
                    drawBar(bar, x: x, y: y, ctx: ctx)
                } else {
                    drawRun(p.text, bold: p.style.bold, color: p.style.fg, x: x, y: y, cells: p.cells, wide: p.wide, ctx: ctx)
                }
                x += w
            }
        }
        if let (li, pi) = hoverTip, li < lines.count, pi < lines[li].pieces.count, let tip = lines[li].pieces[pi].tip {
            drawTip(tip, line: li, piece: pi, ctx: ctx)
        }
    }

    func drawBar(_ bar: BarRender, x: CGFloat, y: CGFloat, ctx: CGContext) {
        let top = y + barTop
        bar.trackColor.ns.setFill()
        for r in bar.track {
            NSRect(x: x + CGFloat(r.lowerBound) * cellWidth, y: top, width: CGFloat(r.count) * cellWidth, height: barHeight).fill()
        }
        // full cells run with their colour behind them too, so the hairline between blocks closes
        var i = 0
        while i < bar.cells.count {
            let c = bar.cells[i]
            if c.solid {
                var j = i
                while j < bar.cells.count, bar.cells[j].solid, bar.cells[j].color == c.color { j += 1 }
                c.color.ns.setFill()
                NSRect(x: x + CGFloat(i) * cellWidth, y: top, width: CGFloat(j - i) * cellWidth, height: barHeight).fill()
                i = j
            } else { i += 1 }
        }
        // the glyphs, as runs of one colour
        i = 0
        while i < bar.cells.count {
            let c = bar.cells[i]
            var j = i
            var run = ""
            while j < bar.cells.count, bar.cells[j].color == c.color { run.append(bar.cells[j].glyph); j += 1 }
            if run.trimmingCharacters(in: .whitespaces).isEmpty == false {
                drawRun(run, bold: false, color: c.color, x: x + CGFloat(i) * cellWidth, y: y, cells: j - i, wide: false, ctx: ctx)
            }
            i = j
        }
    }

    func drawTip(_ tip: String, line li: Int, piece pi: Int, ctx: CGContext) {
        let p = lines[li].pieces[pi]
        var px = padSide
        for k in 0..<pi { px += CGFloat(lines[li].pieces[k].cells) * cellWidth }
        let w = CGFloat(tip.count + 2) * cellWidth
        var x = p.tipLeft ? padSide : px + CGFloat(p.cells) * cellWidth - w
        x = max(padSide, min(x, bounds.width - padSide - w))
        let y = max(0, lineY(li) - LineView.lineHeight - 2)
        Tokens.box.ns.setFill()
        NSRect(x: x, y: y, width: w, height: LineView.lineHeight).fill()
        drawRun(tip, bold: false, color: Tokens.text, x: x + cellWidth, y: y, cells: tip.count, wide: false, ctx: ctx)
    }

    // MARK: pointer

    func hit(at point: NSPoint) -> Hit? { hits.first { $0.rect.contains(point) } }

    public override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let li = Int((p.y - padTop) / LineView.lineHeight)
        let newLine: Int? = (li >= 0 && li < lines.count && lines[li].hover && p.x >= padSide && p.x <= bounds.width - padSide) ? li : nil
        var newTip: (Int, Int)? = nil
        if let h = hit(at: p), lines[h.line].pieces[h.piece].tip != nil { newTip = (h.line, h.piece) }
        if newLine != hoverLine || newTip?.0 != hoverTip?.line || newTip?.1 != hoverTip?.piece {
            hoverLine = newLine
            hoverTip = newTip.map { (line: $0.0, piece: $0.1) }
            needsDisplay = true
        }
    }

    public override func mouseExited(with event: NSEvent) {
        if hoverLine != nil || hoverTip != nil { hoverLine = nil; hoverTip = nil; needsDisplay = true }
    }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let h = hit(at: p), let a = lines[h.line].pieces[h.piece].action { onAction?(a) }
    }

    public override var acceptsFirstResponder: Bool { true }
}
