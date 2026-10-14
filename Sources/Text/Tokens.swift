// The token table of the style guide, section 1. One job per hex.

public struct RGBA: Sendable, Hashable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    public init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xff) / 255; g = Double((hex >> 8) & 0xff) / 255; b = Double(hex & 0xff) / 255; a = alpha
    }
    public func with(alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }
}

public enum Tokens {
    public static let text = RGBA(hex: 0xe0e0e0)      // default text, the percent, figures
    public static let bold = RGBA(hex: 0xededed)      // section titles, the status word, the notch mark
    public static let dim = RGBA(hex: 0x999999)       // reset line, pace lines, captions, header line, chips
    public static let dimmer = RGBA(hex: 0x888888)    // free cells in the memory grid
    public static let quiet = RGBA(hex: 0x505050)     // key hints in the foot
    public static let accent = RGBA(hex: 0xb1b9f9)    // used fill, selected tab, the rule
    public static let track = RGBA(hex: 0x505370)     // the bar behind the fill; the fill when stale
    public static let trackStale = RGBA(hex: 0x505370, alpha: 0.35)
    public static let coral = RGBA(hex: 0xd77757)     // the fill past the tick when over pace
    public static let warning = RGBA(hex: 0xffc107)   // the hit mark, swap cells, the Mac warning dot
    public static let box = RGBA(hex: 0x373737)       // the tooltip ground
    public static let selection = RGBA(r: 39 / 255, g: 61 / 255, b: 76 / 255) // row hover
    public static let inkOnAccent = RGBA(hex: 0x000000)
    public static let inkOnBold = RGBA(hex: 0x191d27)
    public static let white = RGBA(hex: 0xffffff)
    public static let tint = RGBA(r: 25 / 255, g: 29 / 255, b: 39 / 255, a: 0.82)
    public static let stage = RGBA(hex: 0x0e1120)     // the draft's ground behind the glass, for snapshots only

    // Hues from the terminal's ANSI palette
    public static let magenta = RGBA(hex: 0xbd7bcd)   // Fable
    public static let yellow = RGBA(hex: 0xc4ac62)    // Opus
    public static let cyan = RGBA(hex: 0x7ccbcd)      // Sonnet
    public static let green = RGBA(hex: 0x6caa71)     // Haiku
    public static let blue = RGBA(hex: 0x6d96b4)      // projects
    public static let blue2 = RGBA(hex: 0x67b5ed)     // sessions
    public static let procWhite = RGBA(hex: 0xdee5eb) // processes

    /// The hue of a model family. A family not in the table takes the process white: the sheet
    /// names "the next unused ANSI hue" but gives no value for it, so nothing is guessed.
    public static func hue(forFamily family: String) -> RGBA {
        switch family.lowercased() {
        case "fable": return magenta
        case "opus": return yellow
        case "sonnet": return cyan
        case "haiku": return green
        default: return procWhite
        }
    }
}

public struct Style: Sendable, Hashable {
    public var fg: RGBA
    public var bg: RGBA?
    public var bold: Bool
    public init(fg: RGBA, bg: RGBA? = nil, bold: Bool = false) { self.fg = fg; self.bg = bg; self.bold = bold }

    public static let text = Style(fg: Tokens.text)
    public static let bold = Style(fg: Tokens.bold, bold: true)
    public static let dim = Style(fg: Tokens.dim)
    public static let dimmer = Style(fg: Tokens.dimmer)
    public static let quiet = Style(fg: Tokens.quiet)
    public static let accent = Style(fg: Tokens.accent)
    public static let warning = Style(fg: Tokens.warning)
    public static let tabSelected = Style(fg: Tokens.inkOnAccent, bg: Tokens.accent, bold: true)
    public static let subSelected = Style(fg: Tokens.inkOnBold, bg: Tokens.bold, bold: true)
}
