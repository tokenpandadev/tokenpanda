import Foundation
import Text
import Pace
import Prices
import Feed
import Transcripts
import MacStats

/// Everything the popover and the item are built from, as data. The App fills it from the readers.
public struct LiveInput: Sendable {
    public var feed: FeedState
    public var hook: HookStatus
    public var tokens: TokenSummary?
    public var transcriptsRootsExist: Bool
    public var transcriptsError: String?
    public var mac: MacSample?
    public var weeks: WeekRecords
    public var macInBar: Bool
    public var nudges: Bool
    public var listPrice: Bool
    public var nudgeNote: String?
    public var hookError: String?
    public var warn: Bool
    public var tab: Int
    public var section: Int
    public var now: Date
    public var timeZone: TimeZone
    public var calendar: Calendar

    public init(feed: FeedState, hook: HookStatus, tokens: TokenSummary?, transcriptsRootsExist: Bool, transcriptsError: String?,
                mac: MacSample?, weeks: WeekRecords, macInBar: Bool, nudges: Bool, listPrice: Bool, nudgeNote: String?, hookError: String? = nil,
                warn: Bool, tab: Int, section: Int, now: Date, timeZone: TimeZone = .current, calendar: Calendar = .current) {
        self.feed = feed; self.hook = hook; self.tokens = tokens; self.transcriptsRootsExist = transcriptsRootsExist
        self.transcriptsError = transcriptsError; self.mac = mac; self.weeks = weeks; self.macInBar = macInBar; self.nudges = nudges
        self.listPrice = listPrice; self.nudgeNote = nudgeNote; self.hookError = hookError; self.warn = warn; self.tab = tab; self.section = section
        self.now = now; self.timeZone = timeZone; self.calendar = calendar
    }
}

public enum ScreenBuilder {
    static let keys = ["seven_day", "five_hour"]

    public static func clock(_ d: Date, _ tz: TimeZone, weekday: Bool = false) -> String {
        PaceModel.clock(d, weekday: weekday, timeZone: tz)
    }

    // MARK: the windows

    public static func windowView(key: String, limits: Limits, now: Date, tz: TimeZone) -> WindowView {
        let title = WindowKind.title(forKey: key)
        guard let rec = limits.windows[key] else { return WindowView(title: title, used: 0, mode: .absent) }
        guard !limits.isUnknown(key), let length = WindowKind.length(forKey: key) else { return WindowView(title: title, used: rec.used, mode: .unknown) }
        let weekday = WindowKind.showsWeekday(length: length)
        if now >= rec.resetsAt {
            return WindowView(title: title, used: rec.used, mode: .resetPassed(reset: PaceModel.resetText(reset: rec.resetsAt, weekday: weekday, timeZone: tz, passed: true)))
        }
        let start = rec.resetsAt.addingTimeInterval(-length)
        let stale = OpenSessionsRule.isStale(asOf: limits.asOf, now: now)
        guard let r = PaceModel.reading(used: rec.used, start: start, reset: rec.resetsAt, now: now, timeZone: tz) else {
            return WindowView(title: title, used: rec.used, mode: .absent)
        }
        if stale {
            return WindowView(title: title, used: rec.used, mode: .stale(asOf: clock(limits.asOf, tz), reset: r.resetText, elapsed: r.elapsedShare))
        }
        let p = PaceLines(reset: r.resetText, countdown: r.countdown, status: r.status.rawValue, projection: r.projection,
                          allowance: r.allowance, over: r.status == .overPace, elapsed: r.elapsedShare)
        return WindowView(title: title, used: rec.used, mode: .live(p))
    }

    public static func limitsView(_ i: LiveInput) -> LimitsView {
        if let limits = i.feed.limits {
            var views = keys.map { windowView(key: $0, limits: limits, now: i.now, tz: i.timeZone) }
            for key in limits.windows.keys.sorted() where !keys.contains(key) {
                views.append(windowView(key: key, limits: limits, now: i.now, tz: i.timeZone))
            }
            let stale = views.contains { if case .stale = $0.mode { return true } else { return false } }
            return .windows(views, staleNote: stale)
        }
        if i.feed.lastWriteAt == nil {
            return i.hook.installed ? .noSession : .noHook(previous: i.hook.previousCommand)
        }
        // a feed arrived and carried no rate_limits: after the first reply that means the account has none to show
        let answered = i.feed.sessions.contains { $0.snapshot.currentUsageTokens != nil }
        return answered ? .noLimits : .noSession
    }

    // MARK: open sessions

    public static func sessionViews(_ i: LiveInput) -> ([SessionView], Int) {
        let all = i.feed.sessions.map { s -> SessionView in
            let snap = s.snapshot
            let family = PriceTable.family(forModel: snap.modelId ?? "")
            let size = snap.contextWindowSize ?? 0
            let figure = (snap.currentUsageTokens.map { Format.contextTokens($0) } ?? "0") + " of " + Format.contextTokens(size, decimal: false)
            var tip = Format.usd(snap.totalCostUSD ?? 0, cents: true) + " list price equivalent  \(snap.linesAdded ?? 0) added  \(snap.linesRemoved ?? 0) removed"
            if let e = snap.effortLevel { tip += "  effort \(e)" }
            return SessionView(name: snap.projectName ?? snap.sessionId.prefix(8).description, model: snap.modelDisplayName ?? "",
                               hue: Tokens.hue(forFamily: family), used: Int((snap.contextUsedPercentage ?? 0).rounded()),
                               figure: figure, tip: tip, waiting: snap.currentUsageTokens == nil)
        }
        return (Array(all.prefix(5)), max(0, all.count - 5))
    }

    // MARK: tokens

    public static func tokensView(_ i: LiveInput) -> TokensView {
        guard i.transcriptsRootsExist else {
            return TokensView(section: i.section, rows: [[], [], []], priceChip: nil, agentChip: nil, empty: "No transcripts in ~/.claude/projects")
        }
        if let e = i.transcriptsError, i.tokens == nil {
            return TokensView(section: i.section, rows: [[], [], []], priceChip: nil, agentChip: nil, empty: "Cannot read ~/.claude/projects", errorLine: e)
        }
        guard let t = i.tokens else {
            return TokensView(section: i.section, rows: [[], [], []], priceChip: nil, agentChip: nil, empty: "reading the transcripts")
        }
        func rows(_ g: [TokenGroup], hue: (TokenGroup) -> RGBA, unit: String) -> [RowView] {
            let scale = Format.tokenScale(g.map(\.tokens).max() ?? 0)
            return g.map { RowView(name: $0.name, hue: hue($0), share: $0.share, figure: Format.tokens($0.tokens, scale: scale),
                                   tip: "\(Format.tokens($0.tokens, scale: scale)) tokens  \($0.share)% of \(unit)") }
        }
        let models = rows(t.byModel7d, hue: { Tokens.hue(forFamily: PriceTable.family(forModel: $0.key)) }, unit: "7 days")
        let projects = rows(t.byProject7d, hue: { _ in Tokens.blue }, unit: "7 days")
        let sessions = rows(t.bySessionToday, hue: { _ in Tokens.blue2 }, unit: "today")
        var price: String? = nil
        if i.listPrice, t.tokens7d > 0 {
            var chip = "[list price equivalent  " + Format.usd(t.listPrice7d, cents: false)
            if t.unpricedModels == 1 { chip += "  one model unpriced" } else if t.unpricedModels > 1 { chip += "  \(t.unpricedModels) models unpriced" }
            price = chip + "]"
        }
        let agents: String? = t.tokens7d > 0 ? "[\(t.agentShare7d)% by subagents]" : nil
        return TokensView(section: i.section, rows: [models, projects, sessions], priceChip: price, agentChip: agents)
    }

    // MARK: weeks

    public static func weekViews(_ i: LiveInput) -> [WeekView] {
        let tz = i.timeZone
        let f = DayFormatter(timeZone: tz)
        var out: [WeekView] = []
        guard let weeklyLength = WindowKind.length(forKey: "seven_day") else { return [] }
        let current = i.feed.limits?.windows["seven_day"]
        // a week is labelled by its first full day: the window starts Sunday 18:00, the row says Monday
        var cal = i.calendar; cal.timeZone = tz
        func label(_ reset: Date) -> String {
            let start = reset.addingTimeInterval(-weeklyLength)
            let midnight = cal.startOfDay(for: start)
            return f.string(from: midnight == start ? start : cal.date(byAdding: .day, value: 1, to: midnight) ?? start)
        }
        for r in i.weeks.records where r.resetsAt <= i.now || r.resetsAt == current?.resetsAt {
            let date = label(r.resetsAt)
            if let c = current, r.resetsAt == c.resetsAt, i.now < c.resetsAt {
                let stale = i.feed.limits.map { OpenSessionsRule.isStale(asOf: $0.asOf, now: i.now) } ?? true
                let start = c.resetsAt.addingTimeInterval(-weeklyLength)
                let reading = PaceModel.reading(used: c.used, start: start, reset: c.resetsAt, now: i.now, timeZone: tz)
                out.append(WeekView(date: date, used: Int(c.used.rounded()), hit: false, note: "so far",
                                    elapsed: reading?.elapsedShare, over: !stale && reading?.status == .overPace))
            } else {
                out.append(WeekView(date: date, used: Int(r.lastUsed.rounded()), hit: r.hitAt != nil,
                                    note: r.hitAt.map { clock($0, tz, weekday: true) }))
            }
        }
        // without a live window the current row is the calendar week of today, labelled by its Monday
        var weekCal = cal; weekCal.firstWeekday = 2
        let thisWeek = f.string(from: weekCal.dateInterval(of: .weekOfYear, for: i.now)?.start ?? i.now)
        if let c = current, i.now >= c.resetsAt {
            // the window rolled while no session fed: the current row has no figure, only the last value seen
            out.append(WeekView(date: thisWeek, used: nil, note: "last seen \(Int(c.used.rounded()))%"))
        } else if current == nil {
            out.append(WeekView(date: thisWeek, used: nil, note: "no feed yet"))
        }
        return Array(out.suffix(4))
    }

    // MARK: the Mac tab

    public static func macTab(_ i: LiveInput) -> MacTab {
        guard let m = i.mac else {
            return MacTab(cpu: 0, cpuLine: "sampling", gpu: nil, memory: nil, battery: nil, processes: [])
        }
        let cpu = Int(m.cpuBusy.rounded())
        let line = "user \(Int(m.cpuUser.rounded()))%  system \(Int(m.cpuSystem.rounded()))%  \(m.cores) cores"
        var mem: MemView? = nil
        if m.memoryTotal > 0 {
            let total = Double(m.memoryTotal), used = Double(m.memoryUsed), swap = Double(m.swapUsed)
            let cells = Grammar.memCols * Grammar.memRows
            let usedCells = min(cells, Int((used / total * Double(cells)).rounded()))
            let swapCells = min(cells - usedCells, Int((swap / total * Double(cells)).rounded()))
            let totalGB = total / 1_073_741_824
            let totalText = totalGB == totalGB.rounded() ? String(Int(totalGB)) : String(format: "%.1f", totalGB)
            mem = MemView(usedCells: usedCells, swapCells: swapCells,
                          usedLine: "\(Format.gb(m.memoryUsed)) of \(totalText) GB (\(Int((used / total * 100).rounded()))%)",
                          freeLine: "\(Format.gb(m.memoryTotal - min(m.memoryUsed, m.memoryTotal))) GB",
                          swapLine: "\(Format.gb(m.swapUsed)) GB", pressure: m.pressureWord)
        }
        var battery: BatteryView? = nil
        if let b = m.battery {
            var l1: String
            if b.charging {
                l1 = "charging"
                if let w = b.watts, w > 0 { l1 += "  \(String(format: "%.1f", w)) W in" }
                if let a = b.adapterWatts { l1 += "  \(a) W adapter" }
            } else if b.onAC {
                l1 = b.charged ? "charged" : "on power"
                if let a = b.adapterWatts { l1 += "  \(a) W adapter" }
            } else {
                l1 = "discharging"
                if let w = b.watts, w < 0 { l1 += "  \(String(format: "%.1f", -w)) W out" }
            }
            var parts: [String] = []
            if b.charging, let m = b.minutesToFull { parts.append("full in " + minutes(m)) }
            if !b.onAC, let m = b.minutesToEmpty { parts.append("empty in " + minutes(m)) }
            parts.append(b.healthPercent.map { "health \($0)%" } ?? "health n/a")
            if let c = b.cycles { parts.append("\(c) cycles") }
            battery = BatteryView(percent: b.percent, line1: l1, line2: parts.joined(separator: "  "))
        }
        let inUse = max(m.processTotalCPU, 0.1)
        let procs = m.processes.map { p -> RowView in
            let share = min(100, Int((p.cpuPercent / inUse * 100).rounded()))
            let fig = String(format: "%.1f%%", p.cpuPercent)
            return RowView(name: p.name, hue: Tokens.procWhite, share: share, figure: fig, tip: fig + " CPU  " + memory(p.footprint) + " memory")
        }
        return MacTab(cpu: cpu, cpuLine: line, gpu: m.gpuUtilisation, memory: mem, battery: battery, processes: procs, processError: m.processError)
    }

    struct DayFormatter {
        let timeZone: TimeZone
        func string(from d: Date) -> String { PaceModel.format(d, "d MMM", timeZone: timeZone) }
    }

    static func minutes(_ m: Int) -> String {
        m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }

    static func memory(_ bytes: UInt64) -> String {
        bytes >= 1_073_741_824 ? "\(Format.gb(bytes)) GB" : "\(bytes / 1_048_576) MB"
    }

    // MARK: the whole screen and the item

    /// "Usage live" only while a session fed in the last minute; between sessions the time of the last figures;
    /// before any feed arrived, says so.
    public static func headerLine(_ i: LiveInput) -> String {
        if i.feed.isLive(now: i.now) { return "Usage live  Mac live" }
        if let l = i.feed.limits { return "Usage as of \(clock(l.asOf, i.timeZone)), last Claude Code session" }
        return "No usage feed yet  Mac live"
    }

    public static func screen(_ i: LiveInput) -> Screen {
        let (sessions, more) = sessionViews(i)
        let claude = ClaudeTab(limits: limitsView(i), sessions: sessions, moreSessions: more, tokens: tokensView(i), weeks: weekViews(i))
        let settings = SettingsTab(macInBar: i.macInBar, nudges: i.nudges, listPrice: i.listPrice, nudgeNote: i.nudgeNote,
                                   hookInstalled: i.hook.installed, hookError: i.hookError)
        return Screen(tab: i.tab, headerLine: headerLine(i), warn: i.warn, claude: claude, mac: macTab(i), settings: settings)
    }

    public static func item(_ i: LiveInput) -> ItemState {
        let macText = i.macInBar ? i.mac.map { " CPU \(Int($0.cpuBusy.rounded()))%" } : nil
        guard let limits = i.feed.limits, let rec = limits.windows["seven_day"], !limits.isUnknown("seven_day"),
              let length = WindowKind.length(forKey: "seven_day") else {
            return ItemState(used: nil, elapsed: nil, over: false, stale: true, warn: i.warn, macText: macText,
                             label: "Claude usage, no figures yet" + (i.warn ? ", Mac warning" : ""))
        }
        let stale = OpenSessionsRule.isStale(asOf: limits.asOf, now: i.now)
        if i.now >= rec.resetsAt {
            return ItemState(used: nil, elapsed: nil, over: false, stale: true, warn: i.warn, macText: macText,
                             label: "Claude usage, reset passed " + clock(rec.resetsAt, i.timeZone, weekday: true) + (i.warn ? ", Mac warning" : ""))
        }
        let r = PaceModel.reading(used: rec.used, start: rec.resetsAt.addingTimeInterval(-length), reset: rec.resetsAt, now: i.now, timeZone: i.timeZone)
        let over = !stale && r?.status == .overPace
        var label = "Weekly \(Int(rec.used.rounded()))% used"
        if let r { label += ", " + r.status.rawValue.lowercased() + ", " + r.resetText.lowercased() }
        if stale { label += ", as of " + clock(limits.asOf, i.timeZone) }
        if i.warn { label += ", Mac warning" }
        return ItemState(used: Int(rec.used.rounded()), elapsed: r?.elapsedShare, over: over, stale: stale, warn: i.warn, macText: macText, label: label)
    }
}
