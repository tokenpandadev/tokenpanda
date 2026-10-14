// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import Pace

/// The last limits the feed carried, kept so the figures survive the per session files being dropped.
/// Only the two windows and the snapshot time: no path, no model, no session id.
public struct Limits: Sendable, Equatable, Codable {
    public struct Record: Sendable, Equatable, Codable {
        public var used: Double
        public var resetsAt: Date
        public var previousResetsAt: Date?   // the reset before this one, for the length check
        public var contradicts: Bool         // a consecutive reset closer than the key's length: unknown window
        public init(used: Double, resetsAt: Date, previousResetsAt: Date? = nil, contradicts: Bool = false) {
            self.used = used; self.resetsAt = resetsAt; self.previousResetsAt = previousResetsAt; self.contradicts = contradicts
        }
    }
    public var windows: [String: Record]
    public var asOf: Date
    public init(windows: [String: Record] = [:], asOf: Date) { self.windows = windows; self.asOf = asOf }

    /// Applies a feed's rate_limits. A window whose reset moved is checked against the key's length.
    public mutating func apply(_ rateLimits: [String: LimitWindow], at: Date) {
        for (key, w) in rateLimits {
            var rec = windows[key] ?? Record(used: w.usedPercentage, resetsAt: w.resetsAt, previousResetsAt: nil, contradicts: false)
            if let old = windows[key], old.resetsAt != w.resetsAt {
                rec.previousResetsAt = old.resetsAt
                if let len = WindowKind.length(forKey: key) {
                    // consecutive windows of one key are at least one length apart; closer means the key's length is wrong
                    rec.contradicts = w.resetsAt.timeIntervalSince(old.resetsAt) < len - 60
                }
            }
            rec.used = w.usedPercentage
            rec.resetsAt = w.resetsAt
            windows[key] = rec
        }
        asOf = at
    }

    public func isUnknown(_ key: String) -> Bool {
        WindowKind.length(forKey: key) == nil || (windows[key]?.contradicts ?? false)
    }
}

public struct OpenSession: Sendable, Equatable {
    public var snapshot: Snapshot
    public init(snapshot: Snapshot) { self.snapshot = snapshot }
    public var usedPercentage: Double { snapshot.contextUsedPercentage ?? 0 }
}

public struct FeedState: Sendable, Equatable {
    public var limits: Limits?
    public var sessions: [OpenSession]       // open, sorted by context used, largest first
    public var lastWriteAt: Date?            // the newest file's write time, for "Usage live"
    public var scanError: String?
    public init(limits: Limits? = nil, sessions: [OpenSession] = [], lastWriteAt: Date? = nil, scanError: String? = nil) {
        self.limits = limits; self.sessions = sessions; self.lastWriteAt = lastWriteAt; self.scanError = scanError
    }
    public func isLive(now: Date) -> Bool {
        guard let t = lastWriteAt else { return false }
        return now.timeIntervalSince(t) <= OpenSessionsRule.liveHeaderWithin
    }
}

/// Reads the snapshot folder the hook writes into, keeps the last limits, drops files after 60 s.
public actor FeedReader {
    public nonisolated let sessionsDir: URL
    let limitsFile: URL
    var limits: Limits?
    var seen: [String: Date] = [:]   // session id to the write time last applied

    public init(dataDir: URL) {
        sessionsDir = dataDir.appendingPathComponent("sessions", isDirectory: true)
        limitsFile = dataDir.appendingPathComponent("limits.json")
        if let d = try? Data(contentsOf: limitsFile) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
            limits = try? dec.decode(Limits.self, from: d)
        }
    }

    public func scan(now: Date = Date()) -> FeedState {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: sessionsDir.path) else {
            return FeedState(limits: limits, sessions: [], lastWriteAt: nil)
        }
        var sessions: [OpenSession] = []
        var newest: (Date, Snapshot)? = nil
        var lastWrite: Date? = nil
        for name in names where name.hasSuffix(".json") {
            let url = sessionsDir.appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: url.path), let mtime = attrs[.modificationDate] as? Date else { continue }
            if OpenSessionsRule.shouldDelete(writtenAt: mtime, now: now) {
                try? fm.removeItem(at: url)
                continue
            }
            guard let data = try? Data(contentsOf: url), let snap = SnapshotParser.parse(data, writtenAt: mtime) else { continue }
            if mtime > (lastWrite ?? .distantPast) { lastWrite = mtime }
            if snap.rateLimits != nil, mtime > (newest?.0 ?? .distantPast) { newest = (mtime, snap) }
            if OpenSessionsRule.isOpen(writtenAt: mtime, now: now) { sessions.append(OpenSession(snapshot: snap)) }
        }
        if let (t, snap) = newest, let rl = snap.rateLimits, t > (limits?.asOf ?? .distantPast) {
            var l = limits ?? Limits(asOf: t)
            l.apply(rl, at: t)
            limits = l
            persist()
        }
        sessions.sort { $0.usedPercentage > $1.usedPercentage }
        return FeedState(limits: limits, sessions: sessions, lastWriteAt: lastWrite)
    }

    func persist() {
        guard let limits else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(limits) {
            try? FileManager.default.createDirectory(at: limitsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: limitsFile, options: .atomic)
        }
    }
}
