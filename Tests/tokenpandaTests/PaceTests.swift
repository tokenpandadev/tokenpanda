import Testing
import Foundation
import Pace
import Feed

/// The worked example of the spec, section 7, and the edge cases.
struct PaceTests {
    let tz = TimeZone.gmt   // the sample zone
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c }
    func d(_ y: Int, _ mo: Int, _ da: Int, _ h: Int, _ mi: Int, in zone: TimeZone? = nil) -> Date {
        var c = cal
        if let zone { c.timeZone = zone }
        return c.date(from: DateComponents(year: y, month: mo, day: da, hour: h, minute: mi)) ?? Date(timeIntervalSince1970: 0)
    }
    var now: Date { d(2026, 10, 15, 14, 20) }

    @Test func weeklySample() throws {
        let r = try #require(PaceModel.reading(used: 61, start: d(2026, 10, 11, 18, 0), reset: d(2026, 10, 18, 18, 0), now: now, timeZone: tz))
        #expect(abs((r.elapsedShare) - (92.333 / 168 * 100)) <= 0.01)
        #expect(r.status == .overPace)
        #expect(r.projection == "limit Sun 01:20 at this rate")
        #expect(r.allowance == "0.5% an hour left")
        #expect(r.countdown == "in 3d 3h")
        #expect(r.resetText == "Resets Sun 18:00")
        #expect(abs((r.ratePerHour) - (0.66)) <= 0.01)
    }

    @Test func fiveHourSample() throws {
        let r = try #require(PaceModel.reading(used: 24, start: d(2026, 10, 15, 12, 45), reset: d(2026, 10, 15, 17, 45), now: now, timeZone: tz))
        #expect(abs((r.elapsedShare) - (95.0 / 300 * 100)) <= 0.01)
        #expect(r.status == .ahead)
        #expect(r.projection == "76% by reset at this rate")
        #expect(r.allowance == "22% an hour left")
        #expect(r.countdown == "in 3h 25m")
        #expect(r.resetText == "Resets 17:45")
    }

    @Test func onPaceSample() throws {
        // the draft's on pace state: 57% against E 55 is within the band; the limit still lands before the reset
        let r = try #require(PaceModel.reading(used: 57, start: d(2026, 10, 11, 18, 0), reset: d(2026, 10, 18, 18, 0), now: now, timeZone: tz))
        #expect(r.status == .onPace)
        #expect(r.projection == "limit Sun 12:00 at this rate")
        #expect(r.allowance == "0.6% an hour left")
    }

    @Test func aheadSample() throws {
        let r = try #require(PaceModel.reading(used: 45, start: d(2026, 10, 11, 18, 0), reset: d(2026, 10, 18, 18, 0), now: now, timeZone: tz))
        #expect(r.status == .ahead)
        #expect(r.projection == "82% by reset at this rate")
        #expect(r.allowance == "0.7% an hour left")
    }

    @Test func statusThresholds() {
        #expect(PaceModel.status(used: 60, elapsedShare: 55) == .onPace)        // U = E + 5
        #expect(PaceModel.status(used: 60.01, elapsedShare: 55) == .overPace)   // U = E + 5.01
        #expect(PaceModel.status(used: 50, elapsedShare: 55) == .onPace)        // U = E - 5
        #expect(PaceModel.status(used: 49.99, elapsedShare: 55) == .ahead)
    }

    @Test func zeroUsedHasNoProjection() throws {
        let r = try #require(PaceModel.reading(used: 0, start: d(2026, 10, 11, 18, 0), reset: d(2026, 10, 18, 18, 0), now: now, timeZone: tz))
        #expect(r.projection == nil)
        #expect(r.status == .ahead)
        #expect(r.allowance == "1% an hour left")
    }

    @Test func nowPastResetIsNoReading() {
        #expect(PaceModel.reading(used: 61, start: d(2026, 10, 4, 18, 0), reset: d(2026, 10, 11, 18, 0), now: now, timeZone: tz) == nil)
        #expect(PaceModel.reading(used: 61, start: d(2026, 10, 11, 18, 0), reset: d(2026, 10, 11, 18, 0), now: now, timeZone: tz) == nil)
    }

    @Test func nowAtStartHasNoRate() throws {
        // elapsed is zero right at the start; the division is guarded, nothing explodes
        let r = try #require(PaceModel.reading(used: 8, start: now, reset: now.addingTimeInterval(5 * 3600), now: now, timeZone: tz))
        #expect(r.projection == nil)
        #expect(r.status == .overPace)
        #expect(!(r.allowance.contains("nan")))
    }

    @Test func justStartedBurstProjectsHonestly() throws {
        // 10% after 10 minutes of a 5h window projects the limit inside the window, as the average rate says
        let start = now.addingTimeInterval(-600)
        let r = try #require(PaceModel.reading(used: 10, start: start, reset: start.addingTimeInterval(5 * 3600), now: now, timeZone: tz))
        #expect(r.status == .overPace)
        #expect(r.projection == "limit 15:50 at this rate")
    }

    @Test func usedIsClampedAndFractional() throws {
        // a float arrives and may exceed 100
        let r = try #require(PaceModel.reading(used: 123.5, start: d(2026, 10, 11, 18, 0), reset: d(2026, 10, 18, 18, 0), now: now, timeZone: tz))
        #expect(r.status == .overPace)
        #expect(r.projection == nil)   // at 100 there is nothing left to project
        #expect(r.allowance == "0.0% an hour left")
        let f = try #require(PaceModel.reading(used: 23.5, start: d(2026, 10, 15, 12, 45), reset: d(2026, 10, 15, 17, 45), now: now, timeZone: tz))
        #expect(f.projection == "74% by reset at this rate")
    }

    @Test func subHourResetPrintsTheMinuteAsGiven() throws {
        let r = try #require(PaceModel.reading(used: 24, start: d(2026, 10, 15, 12, 59), reset: d(2026, 10, 15, 17, 59), now: now, timeZone: tz))
        #expect(r.resetText == "Resets 17:59")
    }

    @Test func dSTWindowCountsRealHours() throws {
        // a window spanning a clock change has 169 clock hours but 168 real ones; the arithmetic is epoch based.
        // The sample zone with a change inside the window: New York leaves daylight time on 1 November 2026.
        let ny = try #require(TimeZone(identifier: "America/New_York"))
        let reset = d(2026, 11, 4, 18, 0, in: ny)
        let start = reset.addingTimeInterval(-168 * 3600)
        #expect(ny.isDaylightSavingTime(for: start) != ny.isDaylightSavingTime(for: reset))
        let r = try #require(PaceModel.reading(used: 50, start: start, reset: reset, now: start.addingTimeInterval(84 * 3600), timeZone: ny))
        #expect(abs((r.elapsedShare) - (50)) <= 0.001)
        #expect(r.status == .onPace)
    }

    @Test func unknownKeyHasNoLength() {
        #expect(WindowKind.length(forKey: "three_day") == nil)
        #expect(WindowKind.length(forKey: "five_hour") == 5 * 3600.0)
        #expect(WindowKind.length(forKey: "seven_day") == 168 * 3600.0)
        var l = Limits(asOf: now)
        l.apply(["three_day": LimitWindow(key: "three_day", usedPercentage: 10, resetsAt: now.addingTimeInterval(3600))], at: now)
        #expect(l.isUnknown("three_day"))
    }

    @Test func contradictingResetYieldsUnknownWindow() {
        var l = Limits(asOf: now)
        let first = now.addingTimeInterval(3 * 3600)
        l.apply(["five_hour": LimitWindow(key: "five_hour", usedPercentage: 10, resetsAt: first)], at: now)
        #expect(!(l.isUnknown("five_hour")))
        // a second reset three hours after the first contradicts a five hour window
        l.apply(["five_hour": LimitWindow(key: "five_hour", usedPercentage: 2, resetsAt: first.addingTimeInterval(3 * 3600))], at: now.addingTimeInterval(4 * 3600))
        #expect(l.isUnknown("five_hour"))
        // a gap longer than the length is an idle gap, not a contradiction
        var ok = Limits(asOf: now)
        ok.apply(["five_hour": LimitWindow(key: "five_hour", usedPercentage: 10, resetsAt: first)], at: now)
        ok.apply(["five_hour": LimitWindow(key: "five_hour", usedPercentage: 2, resetsAt: first.addingTimeInterval(9 * 3600))], at: now.addingTimeInterval(8 * 3600))
        #expect(!(ok.isUnknown("five_hour")))
    }

    @Test func nudgeBody() throws {
        let r = try #require(PaceModel.reading(used: 80, start: d(2026, 10, 11, 18, 0), reset: d(2026, 10, 18, 18, 0), now: d(2026, 10, 16, 14, 0), timeZone: tz))
        #expect(PaceModel.nudgeBody(r, timeZone: tz).hasPrefix("2 days 4 h to the reset. At this pace the limit lands "))
    }

    @Test func countdownForms() {
        #expect(PaceModel.countdown(remainingHours: 75.67) == "in 3d 3h")
        #expect(PaceModel.countdown(remainingHours: 3.4167) == "in 3h 25m")
        #expect(PaceModel.countdown(remainingHours: 0.25) == "in 0h 15m")
    }
}
