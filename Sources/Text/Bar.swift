// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

// The bar grammar of the style guide, section 5, as the approved popover draws it:
// full cells plus one eighth block, the notch mark at the elapsed share.

public struct BarOptions: Sendable {
    public var color: RGBA?     // the fill hue of a row bar
    public var over: Bool       // coral from the tick on
    public var stale: Bool      // fill in the track colour, track at 35%, mark dim
    public var plain: Bool      // no track
    public init(color: RGBA? = nil, over: Bool = false, stale: Bool = false, plain: Bool = false) {
        self.color = color; self.over = over; self.stale = stale; self.plain = plain
    }
}

public enum Bar {
    public static let eighths: [Character] = [" ", "\u{258F}", "\u{258E}", "\u{258D}", "\u{258C}", "\u{258B}", "\u{258A}", "\u{2589}"]
    public static let full: Character = "\u{2588}"
    public static let notchLeft: Character = "\u{2590}"   // ▐ on the cell before the tick
    public static let notchRight: Character = "\u{258C}"  // ▌ on the tick cell

    public struct Fill: Sendable, Equatable {
        public var fullCells: Int
        public var eighths: Int   // 0 to 8; 8 means the last cell is a full block too
        public init(fullCells: Int, eighths: Int) { self.fullCells = fullCells; self.eighths = eighths }
        public var cellsDrawn: Int { fullCells + (eighths > 0 ? 1 : 0) }
    }

    /// f = U / 100 * N, full cells floor(f), then round((f - floor(f)) * 8) eighths.
    public static func fill(width n: Int, used u: Double) -> Fill {
        let clamped = min(max(u, 0), 100)
        let f = clamped / 100 * Double(n)
        let fullCells = Int(f.rounded(.down))
        let e8 = Int(((f - Double(fullCells)) * 8).rounded())
        return Fill(fullCells: min(fullCells, n), eighths: fullCells >= n ? 0 : e8)
    }

    /// The glyph per cell, without the mark.
    public static func glyphs(width n: Int, used u: Double) -> [Character] {
        let f = fill(width: n, used: u)
        return (0..<n).map { i in
            if i < f.fullCells { return full }
            if i == f.fullCells { return f.eighths == 8 ? full : eighths[f.eighths] }
            return " "
        }
    }

    /// The mark stands at cell round(E / 100 * N), never past N - 1 and never before cell 1 (the notch needs the cell before it).
    public static func tick(width n: Int, elapsed e: Double) -> Int {
        max(1, min(n - 1, Int((e / 100 * Double(n)).rounded())))
    }

    public static func render(width n: Int, used u: Double, elapsed e: Double?, options o: BarOptions = BarOptions()) -> BarRender {
        let base = glyphs(width: n, used: u)
        let t = e.map { tick(width: n, elapsed: $0) }
        let fillColor = o.color ?? (o.stale ? Tokens.track : Tokens.accent)
        let pastColor = (o.over && !o.stale) ? Tokens.coral : fillColor
        let markColor = o.stale ? Tokens.dim : Tokens.bold
        var cells: [BarCell] = []
        for i in 0..<n {
            if let t, i == t - 1 || i == t {
                cells.append(BarCell(glyph: i == t - 1 ? notchLeft : notchRight, color: markColor, solid: false))
            } else {
                let color = i >= (t ?? n) ? pastColor : fillColor
                cells.append(BarCell(glyph: base[i], color: color, solid: base[i] == full))
            }
        }
        var track: [Range<Int>] = []
        if !o.plain {
            if let t {
                if t - 1 > 0 { track.append(0..<(t - 1)) }
                if t + 1 < n { track.append((t + 1)..<n) }
            } else {
                track.append(0..<n)
            }
        }
        return BarRender(width: n, cells: cells, track: track,
                         trackColor: o.stale ? Tokens.trackStale : Tokens.track, plain: o.plain, tick: t)
    }
}

public enum Format {
    /// A name cut to a column: w - 1 characters and the ellipsis, or padded to w.
    public static func col(_ s: String, _ w: Int) -> String {
        if s.count > w { return String(s.prefix(w - 1)) + "\u{2026}" }
        return s + String(repeating: " ", count: w - s.count)
    }

    public static func rcol(_ s: String, _ w: Int) -> String {
        if s.count >= w { return s }
        return String(repeating: " ", count: w - s.count) + s
    }

    /// Tokens: "72.4M", "1.02B", "31.2M", "0.13B"; fits five cells.
    public static func tokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1e9 { return String(format: "%.2fB", d / 1e9) }
        if d >= 100e6 { return String(format: "%.0fM", d / 1e6) }
        if d >= 1e6 { return String(format: "%.1fM", d / 1e6) }
        if d >= 100e3 { return String(format: "%.0fk", d / 1e3) }
        if d >= 1e3 { return String(format: "%.1fk", d / 1e3) }
        return String(n)
    }

    /// A column of figures shares one unit, set by its largest: "1.02B" above "0.71B", never "710M".
    public enum TokenScale { case billions, millions, thousands, units }
    public static func tokenScale(_ n: Int) -> TokenScale {
        n >= 1_000_000_000 ? .billions : n >= 1_000_000 ? .millions : n >= 1_000 ? .thousands : .units
    }
    public static func tokens(_ n: Int, scale: TokenScale) -> String {
        let d = Double(n)
        switch scale {
        case .billions: return String(format: "%.2fB", d / 1e9)
        case .millions: return d >= 100e6 ? String(format: "%.0fM", d / 1e6) : String(format: "%.1fM", d / 1e6)
        case .thousands: return d >= 100e3 ? String(format: "%.0fk", d / 1e3) : String(format: "%.1fk", d / 1e3)
        case .units: return String(n)
        }
    }

    /// Context figures: "405.6k", "88.4k", "1.2M"; the window size without a decimal: "1M", "200k".
    public static func contextTokens(_ n: Int, decimal: Bool = true) -> String {
        let d = Double(n)
        if d >= 1e6 { return decimal ? trim(String(format: "%.1fM", d / 1e6)) : String(format: "%.0fM", d / 1e6) }
        if d >= 1e3 { return decimal ? trim(String(format: "%.1fk", d / 1e3)) : String(format: "%.0fk", d / 1e3) }
        return String(n)
    }

    private static func trim(_ s: String) -> String { s.replacingOccurrences(of: ".0", with: "") }

    /// "USD 1,140" for the chip; "USD 38.20" in a tooltip.
    public static func usd(_ v: Double, cents: Bool) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.minimumFractionDigits = cents ? 2 : 0
        f.maximumFractionDigits = cents ? 2 : 0
        f.usesGroupingSeparator = true
        return "USD " + (f.string(from: NSNumber(value: v)) ?? String(format: cents ? "%.2f" : "%.0f", v))
    }

    public static func gb(_ bytes: UInt64, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", Double(bytes) / 1_073_741_824)
    }
}
