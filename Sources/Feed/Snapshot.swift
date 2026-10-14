// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

// The status line feed as the hook writes it, one file per session. The app reads these fields and nothing else.

public struct LimitWindow: Sendable, Equatable, Codable {
    public var key: String
    public var usedPercentage: Double
    public var resetsAt: Date
    public init(key: String, usedPercentage: Double, resetsAt: Date) { self.key = key; self.usedPercentage = usedPercentage; self.resetsAt = resetsAt }
}

public struct Snapshot: Sendable, Equatable {
    public var sessionId: String
    public var projectDir: String?
    public var modelDisplayName: String?
    public var modelId: String?
    public var effortLevel: String?
    public var contextWindowSize: Int?
    public var contextUsedPercentage: Double?
    public var currentUsageTokens: Int?        // the four counts of current_usage summed; nil on the first call
    public var totalCostUSD: Double?
    public var linesAdded: Int?
    public var linesRemoved: Int?
    public var rateLimits: [String: LimitWindow]?   // absent on the first call of a session
    public var writtenAt: Date

    public init(sessionId: String, writtenAt: Date) { self.sessionId = sessionId; self.writtenAt = writtenAt }

    public var projectName: String? { projectDir.map { ($0 as NSString).lastPathComponent } }
}

public enum SnapshotParser {
    public static func parse(_ data: Data, writtenAt: Date) -> Snapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data), let d = obj as? [String: Any] else { return nil }
        guard let sid = d["session_id"] as? String else { return nil }
        var s = Snapshot(sessionId: sid, writtenAt: writtenAt)
        if let w = d["workspace"] as? [String: Any] { s.projectDir = w["project_dir"] as? String }
        if let m = d["model"] as? [String: Any] { s.modelDisplayName = m["display_name"] as? String; s.modelId = m["id"] as? String }
        if let e = d["effort"] as? [String: Any] { s.effortLevel = e["level"] as? String }
        if let c = d["context_window"] as? [String: Any] {
            s.contextWindowSize = number(c["context_window_size"]).map { Int($0) }
            s.contextUsedPercentage = number(c["used_percentage"])
            if let u = c["current_usage"] as? [String: Any] {
                let keys = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                s.currentUsageTokens = keys.reduce(0) { $0 + Int(number(u[$1]) ?? 0) }
            }
        }
        if let c = d["cost"] as? [String: Any] {
            s.totalCostUSD = number(c["total_cost_usd"])
            s.linesAdded = number(c["total_lines_added"]).map { Int($0) }
            s.linesRemoved = number(c["total_lines_removed"]).map { Int($0) }
        }
        if let r = d["rate_limits"] as? [String: Any] {
            var windows: [String: LimitWindow] = [:]
            for (key, value) in r {
                guard key != "spend_limit", let w = value as? [String: Any],
                      let used = number(w["used_percentage"]), let reset = number(w["resets_at"]) else { continue }
                windows[key] = LimitWindow(key: key, usedPercentage: used, resetsAt: Date(timeIntervalSince1970: reset))
            }
            s.rateLimits = windows
        }
        return s
    }

    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }
}

/// The rules for the per session files: open within 10 s of the last write, dropped after 60 s.
public enum OpenSessionsRule {
    public static let openWithin: TimeInterval = 10
    public static let dropAfter: TimeInterval = 60
    public static let staleAfter: TimeInterval = 3600
    public static let liveHeaderWithin: TimeInterval = 60

    public static func isOpen(writtenAt: Date, now: Date) -> Bool { now.timeIntervalSince(writtenAt) <= openWithin }
    public static func shouldDelete(writtenAt: Date, now: Date) -> Bool { now.timeIntervalSince(writtenAt) > dropAfter }
    public static func isStale(asOf: Date, now: Date) -> Bool { now.timeIntervalSince(asOf) > staleAfter }
}
