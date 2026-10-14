import Testing
import Foundation
import Text

/// The bar builder against the spec's test plan, and the grammar components against golden strings.
struct BarTests {
    @Test func thirtySixCellsAtSixtyOne() {
        let f = Bar.fill(width: 36, used: 61)
        #expect(f.fullCells == 21)
        #expect(f.eighths == 8)          // 0.96 of a cell rounds to a full block
        #expect(f.cellsDrawn == 22)
        let g = Bar.glyphs(width: 36, used: 61)
        #expect(g.count == 36)
        #expect(String(g.prefix(22)) == String(repeating: "\u{2588}", count: 22))
        #expect(g[22] == " ")
    }

    @Test func fiftyCellsAtNine() {
        let f = Bar.fill(width: 50, used: 9)
        #expect(f.fullCells == 4)
        #expect(f.eighths == 4)
        #expect(Bar.glyphs(width: 50, used: 9)[4] == "\u{258C}")   // ▌
    }

    @Test func tickAtFiftyFiveOfThirtySix() {
        #expect(Bar.tick(width: 36, elapsed: 55) == 20)
        #expect(Bar.tick(width: 36, elapsed: 54.96) == 20)
    }

    @Test func tickNeverExceedsNMinusOne() {
        #expect(Bar.tick(width: 36, elapsed: 100) == 35)
        #expect(Bar.tick(width: 36, elapsed: 99.9) == 35)
        #expect(Bar.tick(width: 5, elapsed: 100) == 4)
        #expect(Bar.tick(width: 36, elapsed: 0) == 1)   // the notch needs the cell before it
    }

    @Test func staleYieldsNoCoral() {
        let r = Bar.render(width: 36, used: 61, elapsed: 55, options: BarOptions(over: true, stale: true))
        #expect(!(r.cells.contains { $0.color == Tokens.coral }))
        #expect(r.cells[0].color == Tokens.track)
        #expect(r.cells[20].color == Tokens.dim)        // the mark goes dim
        #expect(r.trackColor == Tokens.trackStale)
    }

    @Test func overPaceIsCoralFromTheTick() {
        let r = Bar.render(width: 36, used: 61, elapsed: 55, options: BarOptions(over: true))
        #expect(r.tick == 20)
        #expect(r.cells[18].color == Tokens.accent)
        #expect(r.cells[19].glyph == "\u{2590}")        // ▐ on the cell before the tick
        #expect(r.cells[20].glyph == "\u{258C}")        // ▌ on the tick
        #expect(r.cells[19].color == Tokens.bold)
        #expect(r.cells[21].color == Tokens.coral)
        #expect(r.cells[21].glyph == "\u{2588}")
        #expect(r.track == [0..<19, 21..<36])
    }

    @Test func aheadHasNothingPastTheTick() {
        let r = Bar.render(width: 36, used: 24, elapsed: 31.67)
        #expect(r.tick == 11)
        #expect(!(r.cells.contains { $0.color == Tokens.coral }))
        #expect(r.glyphs == String(repeating: "\u{2588}", count: 8) + "\u{258B}" + " " + "\u{2590}\u{258C}" + String(repeating: " ", count: 24))
    }

    @Test func plainRowBarHasNoTrack() {
        let r = Bar.render(width: 24, used: 49, elapsed: nil, options: BarOptions(color: Tokens.magenta, plain: true))
        #expect(r.track.isEmpty)
        #expect(r.tick == nil)
        #expect(Bar.fill(width: 24, used: 49) == Bar.Fill(fullCells: 11, eighths: 6))
    }

    // MARK: golden strings of the grammar

    @Test func windowSectionGolden() {
        let w = WindowView(title: "Weekly (all models)", used: 61, mode: .live(PaceLines(
            reset: "Resets Sun 18:00", countdown: "in 3d 3h", status: "Over pace", projection: "limit Sun 01:20 at this rate",
            allowance: "0.5% an hour left", over: true, elapsed: 54.96)))
        let lines = Grammar.windowSection(w).map(\.plain)
        let bar = String(repeating: "\u{2588}", count: 19) + "\u{2590}\u{258C}" + "\u{2588}" + String(repeating: " ", count: 14)
        #expect(lines == [
            " Weekly (all models)",
            " " + bar + " 61% used",
            " Resets Sun 18:00  in 3d 3h",
            " Over pace  limit Sun 01:20 at this rate",
            " 0.5% an hour left",
        ])
    }

    @Test func staleWindowGolden() {
        let w = WindowView(title: "5h window", used: 24, mode: .stale(asOf: "13:05", reset: "Resets 17:45", elapsed: 31.67))
        #expect(Grammar.windowSection(w).map(\.plain).dropFirst(2).map { $0 } == [" Resets 17:45", " as of 13:05"])
    }

    @Test func headerGolden() {
        let h = Grammar.header(line: "Usage live  Mac live", tab: 0, warn: true)
        #expect(h[0].plain == " Usage live  Mac live")
        #expect(h[1].plain == String(repeating: "\u{2594}", count: 48))
        #expect(h[2].plain == "  Claude    Mac \u{25CF}    Settings ")
        #expect(h[2].pieces[1].style == .tabSelected)
    }

    @Test func rowGolden() {
        let r = Grammar.row(RowView(name: "Fable 5.1", hue: Tokens.magenta, share: 49, figure: "1.02B", tip: "1.02B tokens  49% of 7 days"))
        #expect(r.plain == " Fable 5.1      " + String(repeating: "\u{2588}", count: 11) + "\u{258A}" + String(repeating: " ", count: 12) + "  1.02B")
        #expect(r.cells == 1 + 14 + 1 + 24 + 2 + 5)
        #expect(Format.col("cherry-pie-recipes", 14) == "cherry-pie-re\u{2026}")
    }

    @Test func weekGolden() {
        let w = Grammar.week(WeekView(date: "28 Sep", used: 100, hit: true, note: "Thu 16:10"))
        #expect(w.plain == " 28 Sep  " + String(repeating: "\u{2588}", count: 20) + "\u{26A0} 100%  Thu 16:10")
        let c = Grammar.week(WeekView(date: "12 Oct", used: 61, note: "so far", elapsed: 54.96, over: true))
        // 20 cells at 61%: 12 full and two eighths, the notch at round(0.5496 * 20) = 11 covers cells 10 and 11
        #expect(c.plain == " 12 Oct  " + String(repeating: "\u{2588}", count: 10) + "\u{2590}\u{258C}" + "\u{258E}" + String(repeating: " ", count: 7) + "   61%  so far")
    }

    @Test func memoryGridGolden() {
        let m = MemView(usedCells: 142, swapCells: 5, usedLine: "25.5 of 36 GB (71%)", freeLine: "10.5 GB", swapLine: "0.9 GB", pressure: "normal")
        let g = Grammar.memGrid(m)
        #expect(g.count == 13)
        #expect(g[0].plain == " " + String(repeating: "\u{26C1}", count: 20))
        #expect(g[7].plain == " " + String(repeating: "\u{26C1}", count: 2) + String(repeating: "\u{26F6}", count: 18))
        #expect(g[9].plain == " " + String(repeating: "\u{26F6}", count: 15) + String(repeating: "\u{26DD}", count: 5))
        #expect(g[12].plain == " \u{26DD}Swap 0.9 GB   Pressure normal")
        #expect(g[0].cells == 41)
    }

    @Test func settingsGolden() {
        let s = Grammar.settingsTab(SettingsTab(macInBar: false, nudges: true, listPrice: true)).map(\.plain)
        #expect(s[0] == " [ ] Mac figures in the bar")
        #expect(s[1] == " [x] Nudge at 80% and before the 5h end")
        #expect(s[3] == "     tokens at list prices, not the plan price")
        #expect(s[5] == " Install the status line entry")
        #expect(s[6] == "     one statusLine entry in ~/.claude/settings.json")
        #expect(s[8] == " This app makes no network calls. Usage comes")
        #expect(s[9] == " from Claude Code's own status feed on this Mac.")
        #expect(s[11] == " Quit" + String(repeating: " ", count: 40) + "\u{2318}Q")
    }

    @Test func hookRowRemovesWhenInstalledAndShowsTheError() {
        let lines = Grammar.settingsTab(SettingsTab(macInBar: false, nudges: true, listPrice: true, hookInstalled: true,
                                                    hookError: "Could not remove the entry: cannot write settings.json: denied"))
        #expect(lines[5].plain == " Remove the status line entry")
        #expect(lines[5].pieces[1].action == .uninstall)
        #expect(lines[6].plain == "     puts back what statusLine held before")
        #expect(lines[7].plain.hasPrefix("     Could not remove the entry"))
        #expect(lines[7].cells <= Grammar.popCells + 1)
        let off = Grammar.settingsTab(SettingsTab(macInBar: false, nudges: true, listPrice: true, hookInstalled: false))
        #expect(off[5].pieces[1].action == .install)
    }

    @Test func keyHintsNameMPSOnlyOnTheClaudeTab() {
        #expect(Grammar.foot(tab: 0)[1].plain == " Esc closes  Tab switches  m p s sections")
        #expect(Grammar.foot(tab: 1)[1].plain == " Esc closes  Tab switches")
        #expect(Grammar.foot(tab: 2)[1].plain == " Esc closes  Tab switches")
    }

    @Test func openSessionGolden() {
        let s = SessionView(name: "workspace", model: "Fable 5.1", hue: Tokens.magenta, used: 41, figure: "405.6k of 1M", tip: "t")
        let lines = Grammar.sessionRows([s], more: 0).map(\.plain)
        #expect(lines[1] == " workspace  Fable 5.1")
        #expect(lines[2] == " " + String(repeating: "\u{2588}", count: 9) + "\u{2589}" + String(repeating: " ", count: 14) + "  405.6k of 1M  41%")
        #expect(Grammar.sessionRows([], more: 0).map(\.plain) == [" Open sessions", " no open session"])
    }

    @Test func noSeparatorsInTheGrammar() {
        let screen = Screen(tab: 0, headerLine: "Usage live  Mac live", warn: false,
                            claude: ClaudeTab(limits: .noHook(previous: nil), sessions: [], tokens: TokensView(section: 0, rows: [[], [], []], priceChip: nil, agentChip: nil), weeks: []),
                            mac: MacTab(cpu: 0, cpuLine: "", gpu: nil, memory: nil, battery: nil, processes: []),
                            settings: SettingsTab(macInBar: false, nudges: true, listPrice: true))
        for tab in 0..<3 {
            var s = screen; s.tab = tab
            let text = Grammar.popover(s).map(\.plain).joined(separator: "\n")
            for banned in ["\u{2014}", "\u{2013}", "\u{00B7}", "|"] { #expect(!(text.contains(banned)), "separator in tab \(tab)") }
        }
    }

    @Test func formats() {
        #expect(Format.tokens(1_020_000_000) == "1.02B")
        #expect(Format.tokens(72_400_000) == "72.4M")
        #expect(Format.tokens(710_000_000, scale: .billions) == "0.71B")
        #expect(Format.contextTokens(405_600) == "405.6k")
        #expect(Format.contextTokens(1_000_000, decimal: false) == "1M")
        #expect(Format.usd(1140, cents: false) == "USD 1,140")
        #expect(Format.usd(38.2, cents: true) == "USD 38.20")
    }
}
