import Foundation

// The pace model of the spec, section 7. All arithmetic in seconds since the epoch; the clock is the Mac's zone.

public enum PaceStatus: String, Sendable, Equatable {
    case ahead = "Ahead"
    case onPace = "On pace"
    case overPace = "Over pace"
}

public enum WindowKind {
    /// The window length comes from the key name. Any other key is unknown and never guessed.
    public static func length(forKey key: String) -> TimeInterval? {
        switch key {
        case "five_hour": return 5 * 3600
        case "seven_day": return 168 * 3600
        default: return nil
        }
    }

    public static func title(forKey key: String) -> String {
        switch key {
        case "five_hour": return "5h window"
        case "seven_day": return "Weekly (all models)"
        default: return key
        }
    }

    /// Whether the clock carries a weekday: windows longer than a day do.
    public static func showsWeekday(length: TimeInterval) -> Bool { length > 24 * 3600 }
}

public struct PaceReading: Sendable, Equatable {
    public var elapsedShare: Double        // E, percent
    public var status: PaceStatus
    public var projection: String?         // nil when the window has no rate yet (U = 0 or nothing elapsed)
    public var allowance: String           // "0.5% an hour left"
    public var countdown: String           // "in 3d 3h" or "in 3h 25m"
    public var resetText: String           // "Resets Sun 18:00" or "Resets 17:45"
    public var ratePerHour: Double
    public var remainingHours: Double
}

public enum PaceModel {
    public static let band = 5.0           // points either side of E that count as on pace

    /// DateFormatters are costly to create and not thread safe: one per format and zone, behind a lock.
    nonisolated(unsafe) static var formatters: [String: DateFormatter] = [:]
    static let formatterLock = NSLock()

    public static func format(_ date: Date, _ dateFormat: String, timeZone: TimeZone) -> String {
        formatterLock.lock(); defer { formatterLock.unlock() }
        let key = dateFormat + "|" + timeZone.identifier
        let f: DateFormatter
        if let cached = formatters[key] { f = cached } else {
            f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = timeZone
            f.dateFormat = dateFormat
            formatters[key] = f
        }
        return f.string(from: date)
    }

    public static func clock(_ date: Date, weekday: Bool, timeZone: TimeZone) -> String {
        format(date, weekday ? "EEE HH:mm" : "HH:mm", timeZone: timeZone)
    }

    public static func resetText(reset: Date, weekday: Bool, timeZone: TimeZone, passed: Bool = false) -> String {
        (passed ? "Reset " : "Resets ") + clock(reset, weekday: weekday, timeZone: timeZone)
    }

    public static func countdown(remainingHours r: Double) -> String {
        let d = Int((r / 24).rounded(.down))
        let h = Int(r.truncatingRemainder(dividingBy: 24).rounded(.down))
        let m = Int((r * 60).truncatingRemainder(dividingBy: 60).rounded(.down))
        return d > 0 ? "in \(d)d \(h)h" : "in \(h)h \(m)m"
    }

    public static func allowance(used u: Double, remainingHours r: Double) -> String {
        let perHour = (100 - u) / r
        let s = perHour < 1 ? String(format: "%.1f", perHour) : String(Int(perHour.rounded()))
        return s + "% an hour left"
    }

    public static func status(used u: Double, elapsedShare e: Double) -> PaceStatus {
        if u > e + band { return .overPace }
        if u < e - band { return .ahead }
        return .onPace
    }

    /// The reading for a window that has not ended. Returns nil when now is at or past the reset, or before the start.
    public static func reading(used rawUsed: Double, start: Date, reset: Date, now: Date,
                               timeZone: TimeZone = .current) -> PaceReading? {
        let used = min(max(rawUsed, 0), 100)
        let length = reset.timeIntervalSince(start)
        guard length > 0, now < reset, now >= start else { return nil }
        let weekday = WindowKind.showsWeekday(length: length)
        let elapsedH = now.timeIntervalSince(start) / 3600
        let remainH = reset.timeIntervalSince(now) / 3600
        let e = elapsedH / (length / 3600) * 100
        let st = status(used: used, elapsedShare: e)
        var projection: String? = nil
        var rate = 0.0
        if used > 0, used < 100, elapsedH > 0 {
            rate = used / elapsedH
            let toLimitH = (100 - used) / rate
            if toLimitH < remainH {
                let raw = now.addingTimeInterval(toLimitH * 3600)
                let rounded = Date(timeIntervalSince1970: (raw.timeIntervalSince1970 / 300).rounded() * 300)
                projection = "limit " + clock(rounded, weekday: weekday, timeZone: timeZone) + " at this rate"
            } else {
                projection = "\(Int((used + rate * remainH).rounded()))% by reset at this rate"
            }
        }
        return PaceReading(elapsedShare: e, status: st, projection: projection,
                           allowance: allowance(used: used, remainingHours: remainH),
                           countdown: countdown(remainingHours: remainH),
                           resetText: resetText(reset: reset, weekday: weekday, timeZone: timeZone),
                           ratePerHour: rate, remainingHours: remainH)
    }

    /// The body of the weekly nudge: the countdown as days and hours, then the projection sentence.
    public static func nudgeBody(_ r: PaceReading, timeZone: TimeZone = .current) -> String {
        let d = Int((r.remainingHours / 24).rounded(.down))
        let h = Int(r.remainingHours.truncatingRemainder(dividingBy: 24).rounded(.down))
        let lead = d > 0 ? "\(d) day\(d == 1 ? "" : "s") \(h) h to the reset." : "\(h) h to the reset."
        guard let p = r.projection else { return lead }
        if p.hasPrefix("limit ") {
            let when = p.replacingOccurrences(of: "limit ", with: "").replacingOccurrences(of: " at this rate", with: "")
            return lead + " At this pace the limit lands \(when)."
        }
        return lead + " At this pace " + p + "."
    }
}
