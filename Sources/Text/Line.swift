// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// A line of the popover is a run of pieces. Everything the app draws is a line of these.

public enum Action: Sendable, Hashable {
    case tab(Int)
    case section(Int)
    case toggle(String)
    case install
    case uninstall
    case quit
}

public struct BarCell: Sendable, Hashable {
    public var glyph: Character
    public var color: RGBA
    public var solid: Bool   // a full block: paint the cell ground in the fill colour too, so SF Mono's hairline closes
}

public struct BarRender: Sendable, Hashable {
    public var width: Int
    public var cells: [BarCell]
    public var track: [Range<Int>]   // cell ranges that carry the track ground
    public var trackColor: RGBA
    public var plain: Bool           // no track (a row bar)
    public var tick: Int?            // the cell the mark stands on, for the tests and the labels

    public var glyphs: String { String(cells.map(\.glyph)) }
}

public struct Piece: Sendable {
    public var text: String
    public var style: Style
    public var cells: Int
    public var wide: Bool          // each glyph sits in a 2 cell box (the memory grid glyphs)
    public var action: Action?
    public var tip: String?
    public var tipLeft: Bool
    public var bar: BarRender?

    public init(_ text: String, _ style: Style = .text, cells: Int? = nil, wide: Bool = false,
                action: Action? = nil, tip: String? = nil, tipLeft: Bool = false, bar: BarRender? = nil) {
        self.text = text; self.style = style; self.wide = wide; self.action = action
        self.tip = tip; self.tipLeft = tipLeft; self.bar = bar
        self.cells = cells ?? (wide ? text.count * 2 : text.count)
    }

    public static func bar(_ b: BarRender) -> Piece { Piece(b.glyphs, .text, cells: b.width, bar: b) }
}

public struct Line: Sendable {
    public var pieces: [Piece]
    public var hover: Bool          // highlights across the full width under the pointer
    public var label: String?       // the accessibility label of the line, when it differs from its text

    public init(_ pieces: [Piece] = [], hover: Bool = false, label: String? = nil) {
        self.pieces = pieces; self.hover = hover; self.label = label
    }

    /// The line as plain text: bars become their glyph runs. Used by the golden tests.
    public var plain: String { pieces.map(\.text).joined() }
    public var cells: Int { pieces.reduce(0) { $0 + $1.cells } }
}
