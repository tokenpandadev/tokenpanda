// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

/// Week over week: the last value seen per weekly window and the time it first reported 100%, if it did.
/// Four small records in Application Support, nothing else.
public struct WeekRecord: Sendable, Equatable, Codable {
    public var resetsAt: Date
    public var lastUsed: Double
    public var lastSeenAt: Date
    public var hitAt: Date?
    public init(resetsAt: Date, lastUsed: Double, lastSeenAt: Date, hitAt: Date? = nil) {
        self.resetsAt = resetsAt; self.lastUsed = lastUsed; self.lastSeenAt = lastSeenAt; self.hitAt = hitAt
    }
}

public struct WeekRecords: Sendable, Equatable, Codable {
    public var records: [WeekRecord]
    public init(records: [WeekRecord] = []) { self.records = records }

    /// Applies the weekly window of a snapshot. "hit" means a value of 100 or more was seen.
    public mutating func apply(_ w: LimitWindow, at: Date) {
        if let i = records.firstIndex(where: { $0.resetsAt == w.resetsAt }) {
            records[i].lastUsed = w.usedPercentage
            records[i].lastSeenAt = at
            if w.usedPercentage >= 100, records[i].hitAt == nil { records[i].hitAt = at }
        } else {
            records.append(WeekRecord(resetsAt: w.resetsAt, lastUsed: w.usedPercentage, lastSeenAt: at, hitAt: w.usedPercentage >= 100 ? at : nil))
        }
        records.sort { $0.resetsAt < $1.resetsAt }
        if records.count > 4 { records.removeFirst(records.count - 4) }
    }

    public static func load(from url: URL) -> WeekRecords {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        if let d = try? Data(contentsOf: url), let r = try? dec.decode(WeekRecords.self, from: d) { return r }
        return WeekRecords()
    }

    public func save(to url: URL) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(self) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: url, options: .atomic)
        }
    }
}
