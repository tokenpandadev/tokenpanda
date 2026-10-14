#if DEBUG
// Sample data for the debug snapshot flag only; release builds do not contain it.
import Foundation
import Text
import Pace
import Prices
import Feed
import Transcripts
import MacStats

/// The sample (Thursday 15 October 2026, 14:20, in the sample zone UTC) as live inputs, for the snapshot flag.
/// Every name and figure is invented sample data; nothing here comes from a real machine.
public enum Fixtures {
    public static let timeZone = TimeZone.gmt   // the sample zone
    public static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c }

    public static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)) ?? Date(timeIntervalSince1970: 0)
    }

    public static let now = date(2026, 10, 15, 14, 20)
    public static let weeklyReset = date(2026, 10, 18, 18, 0)
    public static let fiveReset = date(2026, 10, 15, 17, 45)

    public static func limits(weekly: Double, five: Double = 24, asOf: Date = now.addingTimeInterval(-60)) -> Limits {
        Limits(windows: ["seven_day": .init(used: weekly, resetsAt: weeklyReset, previousResetsAt: nil, contradicts: false),
                         "five_hour": .init(used: five, resetsAt: fiveReset, previousResetsAt: nil, contradicts: false)], asOf: asOf)
    }

    static func snapshot(_ sid: String, project: String, model: String, modelId: String, tokens: Int, used: Double, cost: Double, added: Int, removed: Int) -> Snapshot {
        var s = Snapshot(sessionId: sid, writtenAt: now.addingTimeInterval(-2))
        s.projectDir = "/Users/someone/" + project
        s.modelDisplayName = model; s.modelId = modelId; s.effortLevel = "high"
        s.contextWindowSize = 1_000_000; s.contextUsedPercentage = used; s.currentUsageTokens = tokens
        s.totalCostUSD = cost; s.linesAdded = added; s.linesRemoved = removed
        s.rateLimits = ["seven_day": LimitWindow(key: "seven_day", usedPercentage: 61, resetsAt: weeklyReset),
                        "five_hour": LimitWindow(key: "five_hour", usedPercentage: 24, resetsAt: fiveReset)]
        return s
    }

    public static let openSessions: [OpenSession] = [
        OpenSession(snapshot: snapshot("3f1a9c2e-0000-4000-8000-000000000001", project: "workspace", model: "Fable 5.1", modelId: "claude-fable-5-1",
                                       tokens: 405_600, used: 41, cost: 38.20, added: 112, removed: 9)),
        OpenSession(snapshot: snapshot("7b2d4e6f-0000-4000-8000-000000000002", project: "tooling", model: "Opus 5.5", modelId: "claude-opus-5-5",
                                       tokens: 88_400, used: 9, cost: 6.10, added: 0, removed: 0)),
    ]

    public static let tokens = TokenSummary(
        byModel7d: [TokenGroup(name: "Fable 5.1", key: "claude-fable-5-1", tokens: 1_020_000_000, share: 49),
                    TokenGroup(name: "Opus 5.5", key: "claude-opus-5-5", tokens: 710_000_000, share: 34),
                    TokenGroup(name: "Sonnet 5.5", key: "claude-sonnet-5-5", tokens: 240_000_000, share: 11),
                    TokenGroup(name: "Haiku 4.5", key: "claude-haiku-4-5-20251001", tokens: 130_000_000, share: 6)],
        byProject7d: [TokenGroup(name: "workspace", key: "workspace", tokens: 1_460_000_000, share: 70),
                      TokenGroup(name: "website", key: "website", tokens: 420_000_000, share: 20),
                      TokenGroup(name: "tooling", key: "tooling", tokens: 140_000_000, share: 7),
                      TokenGroup(name: "other", key: "other", tokens: 80_000_000, share: 4)],
        bySessionToday: [TokenGroup(name: "3f1a9c2e", key: "3f1a9c2e-0000-4000-8000-000000000001", tokens: 31_200_000, share: 43),
                         TokenGroup(name: "7b2d4e6f", key: "7b2d4e6f-0000-4000-8000-000000000002", tokens: 18_000_000, share: 25),
                         TokenGroup(name: "c91e0a44", key: "c91e0a44-0000-4000-8000-000000000003", tokens: 12_600_000, share: 17),
                         TokenGroup(name: "other", key: "other", tokens: 10_600_000, share: 15)],
        agentShare7d: 44, listPrice7d: 1140, unpricedModels: 0,
        tokensToday: 72_400_000, tokens7d: 2_100_000_000, tokens30d: 9_800_000_000, total7d: 2_100_000_000, totalToday: 72_400_000)

    public static let weeks: WeekRecords = {
        var w = WeekRecords()
        w.records = [
            WeekRecord(resetsAt: date(2026, 9, 27, 18, 0), lastUsed: 88, lastSeenAt: date(2026, 9, 27, 17, 50)),
            WeekRecord(resetsAt: date(2026, 10, 4, 18, 0), lastUsed: 100, lastSeenAt: date(2026, 10, 1, 16, 10), hitAt: date(2026, 10, 1, 16, 10)),
            WeekRecord(resetsAt: date(2026, 10, 11, 18, 0), lastUsed: 96, lastSeenAt: date(2026, 10, 11, 17, 58)),
            WeekRecord(resetsAt: weeklyReset, lastUsed: 61, lastSeenAt: now.addingTimeInterval(-60)),
        ]
        return w
    }()

    public static func mac(healthKnown: Bool = true, hog: Bool = false) -> MacSample {
        let gb: UInt64 = 1_073_741_824
        let procs = [ProcessSample(pid: 501, name: "Safari", cpuPercent: 6.1, footprint: UInt64(6.2 * Double(gb))),
                     ProcessSample(pid: 502, name: "Xcode", cpuPercent: 2.3, footprint: UInt64(1.4 * Double(gb))),
                     ProcessSample(pid: 503, name: "WindowServer", cpuPercent: 1.4, footprint: 512 * 1_048_576),
                     ProcessSample(pid: 504, name: "Terminal", cpuPercent: 0.8, footprint: 128 * 1_048_576),
                     ProcessSample(pid: 505, name: "Music", cpuPercent: 0.6, footprint: UInt64(2.1 * Double(gb)))]
        let battery = BatterySample(percent: 75, charging: true, charged: false, onAC: true, minutesToFull: 51, minutesToEmpty: nil,
                                    adapterWatts: 94, watts: 47.6, cycles: 316, healthPercent: healthKnown ? 89 : nil)
        var sample = MacSample(cpuBusy: 9, cpuUser: 5, cpuSystem: 4, cores: 10, gpuUtilisation: 11,
                         memoryUsed: UInt64(25.5 * Double(gb)), memoryTotal: 36 * gb, pressureLevel: hog ? 2 : 1, swapUsed: UInt64(0.9 * Double(gb)),
                         battery: battery, processes: procs, processError: nil, hogPid: nil)
        sample.processTotalCPU = 9
        return sample
    }

    public static func input(weekly: Double = 61, stale: Bool = false, feedState: FeedState? = nil, hook: HookStatus = HookStatus(installed: true, previousCommand: nil),
                             warn: Bool = false, tab: Int = 0, section: Int = 0, healthKnown: Bool = true) -> LiveInput {
        let feed = feedState ?? FeedState(limits: limits(weekly: weekly, asOf: stale ? date(2026, 10, 15, 13, 5) : now.addingTimeInterval(-60)),
                                          sessions: stale ? [] : openSessions, lastWriteAt: stale ? date(2026, 10, 15, 13, 5) : now.addingTimeInterval(-2))
        var w = weeks
        w.records[3].lastUsed = weekly
        return LiveInput(feed: feed, hook: hook, tokens: tokens, transcriptsRootsExist: true, transcriptsError: nil,
                         mac: mac(healthKnown: healthKnown), weeks: w, macInBar: false, nudges: true, listPrice: true, nudgeNote: nil,
                         warn: warn, tab: tab, section: section, now: now, timeZone: timeZone, calendar: calendar)
    }

    /// Every state the docs show, by the shot names in docs/shots/app.
    public static func all() -> [(String, LiveInput)] {
        let fresh = FeedState(limits: nil, sessions: [], lastWriteAt: nil)
        var noLimitsSnap = openSessions
        noLimitsSnap = noLimitsSnap.map { var o = $0; o.snapshot.rateLimits = nil; return o }
        let noLimits = FeedState(limits: nil, sessions: noLimitsSnap, lastWriteAt: now.addingTimeInterval(-2))
        var passedWeeks = weeks
        passedWeeks.records[3].lastUsed = 61
        let passed = FeedState(limits: Limits(windows: ["seven_day": .init(used: 61, resetsAt: date(2026, 10, 11, 18, 0), previousResetsAt: nil, contradicts: false),
                                                        "five_hour": .init(used: 24, resetsAt: date(2026, 10, 11, 17, 45), previousResetsAt: nil, contradicts: false)],
                                              asOf: date(2026, 10, 11, 13, 5)), sessions: [], lastWriteAt: date(2026, 10, 11, 13, 5))
        var resetPassed = input(feedState: passed)
        resetPassed.weeks = passedWeeks
        return [
            ("claude-overpace", input(weekly: 61)),
            ("claude-ahead", input(weekly: 45)),
            ("claude-onpace", input(weekly: 57)),
            ("claude-stale", input(weekly: 61, stale: true)),
            ("claude-nohook", input(feedState: fresh, hook: HookStatus(installed: false, previousCommand: nil))),
            ("claude-nosession", input(feedState: fresh)),
            ("claude-nolimits", input(feedState: noLimits)),
            ("claude-resetpassed", resetPassed),
            ("claude-projects", input(section: 1)),
            ("claude-sessions", input(section: 2)),
            ("mac", input(tab: 1)),
            ("mac-warning", input(warn: true, tab: 1)),
            ("mac-health-na", input(tab: 1, healthKnown: false)),
            ("settings", input(tab: 2)),
        ]
    }
}
#endif
