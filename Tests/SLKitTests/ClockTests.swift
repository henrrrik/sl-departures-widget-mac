import Foundation
import Testing
@testable import SLKit

@Suite("Clock anchoring")
struct ClockTests {
    @Test("A naive timestamp is read as a wall clock, with no zone applied")
    func parsesNaive() {
        let stamp = SLClock.parseNaive("2026-08-31T22:11:00")
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 31
        components.hour = 22; components.minute = 11; components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        #expect(stamp == calendar.date(from: components))

        #expect(SLClock.parseNaive("2026-08-31 22:11") != nil, "space separator is accepted")
        #expect(SLClock.parseNaive("2026-08-31") == nil)
        #expect(SLClock.parseNaive("not a time at all") == nil)
        #expect(SLClock.parseNaive(nil) == nil)
    }

    @Test("The clock anchors to the server, not the machine")
    func anchorsToServer() {
        // A machine whose clock is an hour and a half behind the API's frame.
        let serverNow = naive("2026-08-31T22:00:00")
        let wallNow = serverNow.addingTimeInterval(-5400)

        let payload = [
            departure(display: "Nu", expected: "2026-08-31T22:00:00"),
            departure(display: "4 min", expected: "2026-08-31T22:04:30"),
            departure(display: "9 min", expected: "2026-08-31T22:09:30")
        ]
        var clock = SLClock()
        clock.anchor(with: payload, wallNow: wallNow)

        let offset = try! #require(clock.offset)
        #expect(abs(offset - 5400) < 1, "learns the 90 minute gap between the two clocks")
        #expect(abs(clock.now(wallNow).timeIntervalSince(serverNow)) < 1)
    }

    @Test("A payload with nothing relative in it leaves the previous anchor alone")
    func keepsPreviousAnchor() {
        let wallNow = naive("2026-08-31T22:00:00")
        var clock = SLClock()
        clock.anchor(with: [departure(display: "Nu", expected: "2026-08-31T22:30:00")], wallNow: wallNow)
        let learned = clock.offset

        // Every departure far enough out that SL renders a clock time.
        clock.anchor(with: [departure(display: "23:45", expected: "2026-08-31T23:45:00")], wallNow: wallNow)
        #expect(clock.offset == learned)
    }

    @Test("A garbage anchor is refused rather than slinging the clock")
    func refusesGarbageAnchor() {
        let wallNow = naive("2026-08-31T22:00:00")
        var clock = SLClock()
        clock.anchor(with: [departure(display: "1 min", expected: "2050-01-01T00:00:00")], wallNow: wallNow)
        #expect(clock.offset == nil, "23 years is not a timezone")
        #expect(SLClock.isSane(25 * 3600))
        #expect(!SLClock.isSane(27 * 3600))
    }

    @Test("Minutes come from the timestamp, so the board counts down between fetches")
    func countsDownBetweenFetches() {
        let fetched = naive("2026-08-31T22:00:00")
        let train = departure(display: "5 min", expected: "2026-08-31T22:05:00")

        #expect(SLClock.minutes(until: train, now: fetched) == 5)
        #expect(SLClock.minutes(until: train, now: fetched.addingTimeInterval(120)) == 3)
        #expect(SLClock.minutes(until: train, now: fetched.addingTimeInterval(600)) == 0,
                "never counts below zero")
    }

    @Test("The relative display is the fallback when a payload carries no timestamp")
    func fallsBackToDisplay() {
        let now = naive("2026-08-31T22:00:00")
        #expect(SLClock.minutes(until: departure(display: "7 min"), now: now) == 7)
        #expect(SLClock.minutes(until: departure(display: "Nu"), now: now) == 0)
        #expect(SLClock.minutes(until: departure(display: "23:45"), now: now) == nil)
        #expect(SLClock.minutes(until: departure(), now: now) == nil)
    }

    @Test("The expected clock time is read straight out of the wall-clock string")
    func readsClockText() {
        #expect(SLClock.clockText(departure(expected: "2026-08-31T22:11:00")) == "22:11")
        #expect(SLClock.clockText(departure(scheduled: "2026-08-31T06:05:00")) == "06:05")
        #expect(SLClock.clockText(departure()) == "")
    }

    @Test("With no anchor the clock falls back to Stockholm wall time")
    func fallsBackToStockholm() {
        let wall = Date(timeIntervalSince1970: 1_756_677_060)  // 2025-08-31T21:51:00Z
        let fallback = SLClock().now(wall)
        let zone = TimeZone(identifier: "Europe/Stockholm")!
        #expect(fallback == wall.addingTimeInterval(TimeInterval(zone.secondsFromGMT(for: wall))))
    }
}
