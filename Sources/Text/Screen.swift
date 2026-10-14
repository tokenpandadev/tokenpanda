// What the popover shows, as data. The App fills it from the live readers; the snapshot flag fills it from fixtures.

public struct PaceLines: Sendable, Equatable {
    public var reset: String        // "Resets Sun 18:00"
    public var countdown: String    // "in 3d 3h"
    public var status: String       // "Over pace"
    public var projection: String?  // "limit Sun 01:20 at this rate"; nil when there is no rate yet
    public var allowance: String    // "0.5% an hour left"
    public var over: Bool
    public var elapsed: Double      // E, the tick
    public init(reset: String, countdown: String, status: String, projection: String?, allowance: String, over: Bool, elapsed: Double) {
        self.reset = reset; self.countdown = countdown; self.status = status; self.projection = projection
        self.allowance = allowance; self.over = over; self.elapsed = elapsed
    }
}

public enum WindowMode: Sendable, Equatable {
    case live(PaceLines)
    case stale(asOf: String, reset: String, elapsed: Double)
    case resetPassed(reset: String)   // "Reset Sun 18:00  no session since"
    case absent                       // "not in the last feed"
    case unknown                      // "unknown window"
}

public struct WindowView: Sendable, Equatable {
    public var title: String
    public var used: Double
    public var mode: WindowMode
    public init(title: String, used: Double, mode: WindowMode) { self.title = title; self.used = used; self.mode = mode }
}

public enum LimitsView: Sendable, Equatable {
    case windows([WindowView], staleNote: Bool)
    case noHook(previous: String?)
    case noSession
    case noLimits
}

public struct SessionView: Sendable, Equatable {
    public var name: String
    public var model: String
    public var hue: RGBA
    public var used: Int
    public var figure: String       // "405.6k of 1M"
    public var tip: String
    public var waiting: Bool        // current_usage null: empty bar, "waiting for the first reply"
    public init(name: String, model: String, hue: RGBA, used: Int, figure: String, tip: String, waiting: Bool = false) {
        self.name = name; self.model = model; self.hue = hue; self.used = used; self.figure = figure; self.tip = tip; self.waiting = waiting
    }
}

public struct RowView: Sendable, Equatable {
    public var name: String
    public var hue: RGBA
    public var share: Int
    public var figure: String
    public var tip: String
    public init(name: String, hue: RGBA, share: Int, figure: String, tip: String) {
        self.name = name; self.hue = hue; self.share = share; self.figure = figure; self.tip = tip
    }
}

public struct TokensView: Sendable, Equatable {
    public var section: Int                 // 0 models, 1 projects, 2 sessions
    public var rows: [[RowView]]            // three lists
    public var priceChip: String?           // "[list price equivalent  USD 1,140]"
    public var agentChip: String?           // "[44% by subagents]"
    public var empty: String?               // "No transcripts in ~/.claude/projects"
    public var errorLine: String?           // the error's own message, under "Cannot read ~/.claude/projects"
    public init(section: Int, rows: [[RowView]], priceChip: String?, agentChip: String?, empty: String? = nil, errorLine: String? = nil) {
        self.section = section; self.rows = rows; self.priceChip = priceChip; self.agentChip = agentChip; self.empty = empty; self.errorLine = errorLine
    }
}

public struct WeekView: Sendable, Equatable {
    public var date: String          // "21 Sep"
    public var used: Int?            // nil: no figure (an empty bar with a note)
    public var hit: Bool
    public var note: String?         // "Thu 16:10", "so far", "no feed yet", "last seen 61%"
    public var elapsed: Double?      // the current week carries the tick
    public var over: Bool
    public init(date: String, used: Int?, hit: Bool = false, note: String? = nil, elapsed: Double? = nil, over: Bool = false) {
        self.date = date; self.used = used; self.hit = hit; self.note = note; self.elapsed = elapsed; self.over = over
    }
}

public struct ClaudeTab: Sendable, Equatable {
    public var limits: LimitsView
    public var sessions: [SessionView]
    public var moreSessions: Int
    public var tokens: TokensView
    public var weeks: [WeekView]
    public init(limits: LimitsView, sessions: [SessionView], moreSessions: Int = 0, tokens: TokensView, weeks: [WeekView]) {
        self.limits = limits; self.sessions = sessions; self.moreSessions = moreSessions; self.tokens = tokens; self.weeks = weeks
    }
}

public struct MemView: Sendable, Equatable {
    public var usedCells: Int       // of 200
    public var swapCells: Int
    public var usedLine: String     // "25.5 of 36 GB (71%)"
    public var freeLine: String     // "10.5 GB"
    public var swapLine: String     // "0.9 GB"
    public var pressure: String     // "normal"
    public init(usedCells: Int, swapCells: Int, usedLine: String, freeLine: String, swapLine: String, pressure: String) {
        self.usedCells = usedCells; self.swapCells = swapCells; self.usedLine = usedLine; self.freeLine = freeLine; self.swapLine = swapLine; self.pressure = pressure
    }
}

public struct BatteryView: Sendable, Equatable {
    public var percent: Int
    public var line1: String        // "charging  47.6 W in  94 W adapter"
    public var line2: String        // "full in 51 min  health 89%  316 cycles"
    public init(percent: Int, line1: String, line2: String) { self.percent = percent; self.line1 = line1; self.line2 = line2 }
}

public struct MacTab: Sendable, Equatable {
    public var cpu: Int
    public var cpuLine: String      // "user 5%  system 4%  10 cores"
    public var gpu: Int?
    public var memory: MemView?
    public var battery: BatteryView?
    public var processes: [RowView]
    public var processError: String?
    public init(cpu: Int, cpuLine: String, gpu: Int?, memory: MemView?, battery: BatteryView?, processes: [RowView], processError: String? = nil) {
        self.cpu = cpu; self.cpuLine = cpuLine; self.gpu = gpu; self.memory = memory; self.battery = battery; self.processes = processes; self.processError = processError
    }
}

public struct SettingsTab: Sendable, Equatable {
    public var macInBar: Bool
    public var nudges: Bool
    public var listPrice: Bool
    public var nudgeNote: String?   // "Notifications are off for this app in System Settings"
    public var hookInstalled: Bool  // the row reads "Remove the status line entry" when true, "Install the status line entry" when false
    public var hookError: String?   // the last install or remove error, shown under the row
    public init(macInBar: Bool, nudges: Bool, listPrice: Bool, nudgeNote: String? = nil, hookInstalled: Bool = false, hookError: String? = nil) {
        self.macInBar = macInBar; self.nudges = nudges; self.listPrice = listPrice; self.nudgeNote = nudgeNote
        self.hookInstalled = hookInstalled; self.hookError = hookError
    }
}

public struct Screen: Sendable, Equatable {
    public var tab: Int
    public var headerLine: String   // "Usage live  Mac live", "Usage as of 13:05, last Claude Code session" or "No usage feed yet  Mac live"
    public var warn: Bool
    public var claude: ClaudeTab
    public var mac: MacTab
    public var settings: SettingsTab
    public init(tab: Int, headerLine: String, warn: Bool, claude: ClaudeTab, mac: MacTab, settings: SettingsTab) {
        self.tab = tab; self.headerLine = headerLine; self.warn = warn; self.claude = claude; self.mac = mac; self.settings = settings
    }
}

/// The menu bar item, as data.
public struct ItemState: Sendable, Equatable {
    public var used: Int?           // nil: no figure, the track alone
    public var elapsed: Double?
    public var over: Bool
    public var stale: Bool
    public var warn: Bool
    public var macText: String?     // " CPU 9%"
    public var label: String        // the accessibility label
    public init(used: Int?, elapsed: Double?, over: Bool, stale: Bool, warn: Bool, macText: String?, label: String) {
        self.used = used; self.elapsed = elapsed; self.over = over; self.stale = stale; self.warn = warn; self.macText = macText; self.label = label
    }
}
