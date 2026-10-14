// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// The line renderer: one function per component of the style guide, copied from the approved popover draft.
// Nothing here is reinterpreted; a change to the sheet is a change here.

public enum Grammar {
    public static let popCells = 47      // content cells in the 380 pt popover at SF Mono 12
    public static let popBar = 36        // the window bar
    public static let rowBar = 24
    public static let weekBar = 20
    public static let memCols = 20
    public static let memRows = 10

    static let blank = Line()
    static func L(_ pieces: Piece...) -> Line { Line(pieces) }
    static func sp(_ s: String, _ st: Style = .text) -> Piece { Piece(s, st) }

    // 6.1 header line and tab strip
    public static func header(line: String, tab sel: Int, warn: Bool) -> [Line] {
        var tabs: [Piece] = []
        for (i, name) in ["Claude", "Mac", "Settings"].enumerated() {
            if i > 0 { tabs.append(sp("  ")) }
            let style: Style = i == sel ? .tabSelected : .text
            if name == "Mac" && warn {
                tabs.append(Piece(" Mac ", style, action: .tab(i)))
                tabs.append(Piece("\u{25CF}", Style(fg: Tokens.warning, bg: style.bg), action: .tab(i)))
                tabs.append(Piece(" ", style, action: .tab(i)))
            } else {
                tabs.append(Piece(" \(name) ", style, action: .tab(i)))
            }
        }
        return [
            L(sp(" "), sp(line, .dim)),
            L(sp(String(repeating: "\u{2594}", count: popCells + 1), .accent)),
            Line([sp(" ")] + tabs),
        ]
    }

    static func percentPiece(_ used: Double, dim: Bool) -> Piece {
        sp(" \(Int(used.rounded()))% used", dim ? .dim : .text)
    }

    // 6.3 window section
    public static func windowSection(_ w: WindowView) -> [Line] {
        var out: [Line] = [L(sp(" "), sp(w.title, .bold))]
        switch w.mode {
        case .live(let p):
            let bar = Bar.render(width: popBar, used: w.used, elapsed: p.elapsed, options: BarOptions(over: p.over))
            out.append(L(sp(" "), .bar(bar), percentPiece(w.used, dim: false)))
            out.append(L(sp(" "), sp(p.reset + "  " + p.countdown, .dim)))
            if let proj = p.projection {
                out.append(L(sp(" "), sp(p.status, .bold), sp("  " + proj, .dim)))
            } else {
                out.append(L(sp(" "), sp(p.status, .bold)))
            }
            out.append(L(sp(" "), sp(p.allowance, .dim)))
        case .stale(let asOf, let reset, let e):
            let bar = Bar.render(width: popBar, used: w.used, elapsed: e, options: BarOptions(stale: true))
            out.append(L(sp(" "), .bar(bar), percentPiece(w.used, dim: true)))
            out.append(L(sp(" "), sp(reset, .dim)))
            out.append(L(sp(" "), sp("as of " + asOf, .dim)))
        case .resetPassed(let reset):
            out.append(L(sp(" "), .bar(Bar.render(width: popBar, used: 0, elapsed: nil))))
            out.append(L(sp(" "), sp(reset + "  no session since", .dim)))
        case .absent:
            out.append(L(sp(" "), .bar(Bar.render(width: popBar, used: 0, elapsed: nil))))
            out.append(L(sp(" "), sp("not in the last feed", .dim)))
        case .unknown:
            out.append(L(sp(" "), .bar(Bar.render(width: popBar, used: w.used, elapsed: nil)), percentPiece(w.used, dim: true)))
            out.append(L(sp(" "), sp("unknown window", .dim)))
        }
        return out
    }

    static func privacy() -> [Line] {
        [L(sp(" "), sp("This app makes no network calls. Usage comes", .dim)),
         L(sp(" "), sp("from Claude Code's own status feed on this Mac.", .dim))]
    }

    static func windowEmpty(_ title: String, _ line: String) -> [Line] {
        [L(sp(" "), sp(title, .bold)),
         L(sp(" "), .bar(Bar.render(width: popBar, used: 0, elapsed: nil))),
         L(sp(" "), sp(line, .dim))]
    }

    // the empty and first run states of the approved draft
    public static func limits(_ v: LimitsView) -> [Line] {
        switch v {
        case .windows(let ws, let staleNote):
            var out: [Line] = []
            for (i, w) in ws.enumerated() {
                if i > 0 { out.append(blank) }
                out += windowSection(w)
            }
            if staleNote {
                out.append(L(sp(" "), sp("limits are shared with the Claude app and other", .dim)))
                out.append(L(sp(" "), sp("Macs, so the real figure may be higher", .dim)))
            }
            return out
        case .noHook(let previous):
            var out: [Line] = [
                L(sp(" "), sp("Weekly and 5h window", .bold)),
                L(sp(" "), sp("needs Claude Code's status line feed", .dim)),
                L(sp(" "), sp("one statusLine entry in ~/.claude/settings.json", .dim)),
                L(sp(" "), sp(previous == nil ? "chained if one exists" : "your current status line is kept and chained", .dim)),
                L(sp(" "), Piece(" Install the status line hook ", .tabSelected, action: .install)),
                blank,
            ]
            out += privacy()
            return out
        case .noSession:
            return windowEmpty("Weekly (all models)", "no session yet  open Claude Code once") + [blank]
                + windowEmpty("5h window", "no session yet  open Claude Code once")
        case .noLimits:
            return [L(sp(" "), sp("Weekly and 5h window", .bold)),
                    L(sp(" "), sp("this account has no plan limits to show", .dim))]
        }
    }

    // 6.14 open sessions, as the draft draws them: two lines per session
    public static func sessionRows(_ list: [SessionView], more: Int) -> [Line] {
        var out: [Line] = [L(sp(" "), sp("Open sessions", .bold))]
        if list.isEmpty {
            out.append(L(sp(" "), sp("no open session", .dim)))
            return out
        }
        for s in list {
            out.append(L(sp(" "), sp(s.name), sp("  "), sp(s.model, .dim)))
            let bar = Bar.render(width: rowBar, used: s.waiting ? 0 : Double(s.used), elapsed: nil, options: BarOptions(color: s.hue, plain: true))
            if s.waiting {
                out.append(Line([sp(" "), .bar(bar), sp("  "), sp("waiting for the first reply", .dim)], hover: true))
            } else {
                let fig = Piece(s.figure + "  " + Format.rcol("\(s.used)%", 3), .text, tip: s.tip, tipLeft: true)
                out.append(Line([sp(" "), .bar(bar), sp("  "), fig], hover: true,
                                label: "\(s.name), \(s.model), context \(s.figure), \(s.used)% used"))
            }
        }
        if more > 0 { out.append(L(sp(" "), sp("and \(more) more", .dim))) }
        return out
    }

    // 6.5 table row
    public static func row(_ r: RowView) -> Line {
        let bar = Bar.render(width: rowBar, used: Double(r.share), elapsed: nil, options: BarOptions(color: r.hue, plain: true))
        let fig = Piece(Format.rcol(r.figure, 5), .text, tip: r.tip)
        return Line([sp(" "), sp(Format.col(r.name, 14)), sp(" "), .bar(bar), sp("  "), fig], hover: true,
                    label: "\(r.name), \(r.figure), \(r.tip)")
    }

    // 6.6 section switch
    public static func subTabs(_ sel: Int) -> Line {
        var pieces: [Piece] = [sp(" ")]
        for (i, name) in ["Models", "Projects", "Sessions"].enumerated() {
            if i > 0 { pieces.append(sp("  ")) }
            pieces.append(Piece(" \(name) ", i == sel ? .subSelected : .text, action: .section(i)))
        }
        return Line(pieces)
    }

    public static func tokens(_ t: TokensView) -> [Line] {
        let title = ["Tokens by model  7 days", "Tokens by project  7 days", "Tokens by session  today"][t.section]
        var out: [Line] = [L(sp(" "), sp(title, .bold)), subTabs(t.section)]
        if let empty = t.empty {
            out.append(L(sp(" "), sp(empty, .dim)))
            if let e = t.errorLine { out.append(L(sp(" "), sp(Format.col(e, popCells - 1).trimmingCharacters(in: .whitespaces), .dim))) }
            return out
        }
        let list = t.rows[t.section]
        if list.isEmpty {
            out.append(L(sp(" "), sp(t.section == 2 ? "no session today" : "nothing in the last 7 days", .dim)))
        }
        for r in list { out.append(row(r)) }
        if let chip = t.priceChip { out.append(L(sp(" "), sp(chip, .dim))) }
        if let chip = t.agentChip { out.append(L(sp(" "), sp(chip, .dim))) }
        return out
    }

    // 6.8 weeks
    public static func week(_ w: WeekView) -> Line {
        var pieces: [Piece] = [sp(" "), sp(Format.col(w.date, 6)), sp("  ")]
        if let used = w.used {
            let bar = Bar.render(width: weekBar, used: Double(used), elapsed: w.elapsed, options: BarOptions(over: w.over))
            pieces.append(.bar(bar))
            pieces.append(w.hit ? Piece("\u{26A0}", .warning, cells: 1) : sp(" "))
            pieces.append(sp(" " + Format.rcol("\(used)%", 4)))
        } else {
            pieces.append(.bar(Bar.render(width: weekBar, used: 0, elapsed: nil)))
            pieces.append(sp("  "))
        }
        if let note = w.note { pieces.append(sp("  " + note, .dim)) }
        return Line(pieces)
    }

    // 6.9 memory grid
    public static func memGrid(_ m: MemView) -> [Line] {
        let total = memCols * memRows
        var out: [Line] = []
        for r in 0..<memRows {
            var pieces: [Piece] = [sp(" ")]
            var runGlyph = ""
            var runStyle: Style = .accent
            func flush() { if !runGlyph.isEmpty { pieces.append(Piece(runGlyph, runStyle, wide: true)); runGlyph = "" } }
            for c in 0..<memCols {
                let i = r * memCols + c
                let (g, st): (String, Style) = i < m.usedCells ? ("\u{26C1}", .accent) : i >= total - m.swapCells ? ("\u{26DD}", .warning) : ("\u{26F6}", .dimmer)
                if st != runStyle { flush(); runStyle = st }
                runGlyph += g
            }
            flush()
            out.append(Line(pieces))
        }
        out.append(L(sp(" "), Piece("\u{26C1}", .accent, wide: true), sp("Used "), sp(m.usedLine, .dim)))
        out.append(L(sp(" "), Piece("\u{26F6}", .dimmer, wide: true), sp("Free "), sp(m.freeLine, .dim)))
        out.append(L(sp(" "), Piece("\u{26DD}", .warning, wide: true), sp("Swap "), sp(m.swapLine, .dim), sp("   "), sp("Pressure " + m.pressure, .dim)))
        return out
    }

    // 6.10 checkbox rows
    public static func cbRow(_ key: String, _ label: String, _ on: Bool, _ sub: String?) -> [Line] {
        var out = [Line([sp(" "), Piece(on ? "[x]" : "[ ]", .text, action: .toggle(key)), Piece(" " + label, .text, action: .toggle(key))],
                        hover: true, label: label)]
        if let sub { out.append(L(sp("     "), sp(sub, .dim))) }
        return out
    }

    /// The key hints. m, p and s switch the token sections, so they are named only on the Claude tab, where they work.
    public static func foot(tab: Int) -> [Line] {
        [blank, L(sp(" "), sp(tab == 0 ? "Esc closes  Tab switches  m p s sections" : "Esc closes  Tab switches", .quiet))]
    }

    public static func claudeTab(_ c: ClaudeTab) -> [Line] {
        var out = limits(c.limits) + [blank]
        if case .noHook = c.limits {} else {
            out += sessionRows(c.sessions, more: c.moreSessions) + [blank]
        }
        out += tokens(c.tokens)
        out.append(blank)
        out.append(L(sp(" "), sp("Week over week", .bold)))
        if c.weeks.isEmpty { out.append(L(sp(" "), sp("no week recorded yet", .dim))) }
        for w in c.weeks { out.append(week(w)) }
        return out
    }

    public static func macTab(_ m: MacTab) -> [Line] {
        var out: [Line] = [L(sp(" "), sp("CPU", .bold))]
        out.append(L(sp(" "), .bar(Bar.render(width: popBar, used: Double(m.cpu), elapsed: nil)), sp(" \(m.cpu)%")))
        out.append(L(sp(" "), sp(m.cpuLine, .dim)))
        if let gpu = m.gpu {
            out.append(blank)
            out.append(L(sp(" "), sp("GPU", .bold)))
            out.append(L(sp(" "), .bar(Bar.render(width: popBar, used: Double(gpu), elapsed: nil)), sp(" \(gpu)%")))
            out.append(L(sp(" "), sp("device utilisation", .dim)))
        }
        if let mem = m.memory {
            out.append(blank)
            out.append(L(sp(" "), sp("Memory", .bold)))
            out += memGrid(mem)
        }
        if let b = m.battery {
            out.append(blank)
            out.append(L(sp(" "), sp("Battery", .bold)))
            out.append(L(sp(" "), .bar(Bar.render(width: popBar, used: Double(b.percent), elapsed: nil)), sp(" \(b.percent)%")))
            out.append(L(sp(" "), sp(b.line1, .dim)))
            out.append(L(sp(" "), sp(b.line2, .dim)))
        }
        out.append(blank)
        out.append(L(sp(" "), sp("Processes by CPU", .bold)))
        if let e = m.processError {
            out.append(L(sp(" "), sp("Cannot read the process list", .dim)))
            out.append(L(sp(" "), sp(e, .dim)))
        }
        for r in m.processes { out.append(row(r)) }
        return out
    }

    public static func settingsTab(_ s: SettingsTab) -> [Line] {
        var out = cbRow("macFiguresInBar", "Mac figures in the bar", s.macInBar, nil)
        out += cbRow("nudges", "Nudge at 80% and before the 5h end", s.nudges, s.nudgeNote)
        out += cbRow("listPriceEquivalent", "List price equivalent", s.listPrice, "tokens at list prices, not the plan price")
        out.append(blank)
        out += hookRow(installed: s.hookInstalled, error: s.hookError)
        out.append(blank)
        out += privacy()
        out.append(blank)
        out.append(Line([sp(" "), Piece("Quit", .text, action: .quit), Piece(Format.rcol("\u{2318}Q", popCells - 5), .text, action: .quit)],
                        hover: true, label: "Quit, command Q"))
        return out
    }

    /// The status line entry: one click installs it, one click removes it and puts the previous entry back.
    public static func hookRow(installed: Bool, error: String?) -> [Line] {
        let label = installed ? "Remove the status line entry" : "Install the status line entry"
        let action: Action = installed ? .uninstall : .install
        var out = [Line([sp(" "), Piece(label, .text, action: action)], hover: true, label: label)]
        out.append(L(sp("     "), sp(installed ? "puts back what statusLine held before" : "one statusLine entry in ~/.claude/settings.json", .dim)))
        if let error {
            out.append(L(sp("     "), sp(Format.col(error, popCells - 5).trimmingCharacters(in: .whitespaces), .dim)))
        }
        return out
    }

    public static func popover(_ s: Screen) -> [Line] {
        var out = header(line: s.headerLine, tab: s.tab, warn: s.warn) + [blank]
        switch s.tab {
        case 0: out += claudeTab(s.claude)
        case 1: out += macTab(s.mac)
        default: out += settingsTab(s.settings)
        }
        return out + foot(tab: s.tab)
    }
}
