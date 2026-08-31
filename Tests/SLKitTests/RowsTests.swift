import Foundation
import Testing
@testable import SLKit

@Suite("Rows")
struct RowsTests {
    /// A real captured payload, read at the moment its first departure leaves —
    /// so the assertions hold whenever the suite runs.
    func fixtureBoard() throws -> (rows: [DepartureRow], now: Date) {
        let response = try Fixture.departures()
        let now = try #require(SLClock.parseNaive(response.departures[0].expected))
        return (SLRows.rows(from: response.departures, now: now), now)
    }

    @Test("A live payload flattens into rows the UI can bind to directly")
    func flattensLivePayload() throws {
        let (rows, _) = try fixtureBoard()
        #expect(rows.count == 10)

        let first = rows[0]
        #expect(!first.line.isEmpty)
        #expect(!first.destination.isEmpty)
        #expect(first.minutes == 0)
        #expect(first.waitLabel == "now")
        #expect(["BUS", "METRO"].contains(first.mode))
        #expect(first.symbol == SLFormat.symbol(for: first.mode))
        #expect(first.clock.count == 5, "an HH:MM the stop's own clock would show")
        #expect(rows.map(\.id).count == Set(rows.map(\.id)).count, "ids are unique per departure")
    }

    @Test("A cancellation is read from the state or from a deviation's consequence")
    func detectsCancellations() {
        let now = naive("2026-08-31T22:00:00")
        let byState = departure(expected: "2026-08-31T22:05:00", state: "CANCELLED")
        let byConsequence = departure(
            expected: "2026-08-31T22:06:00",
            deviations: [Deviation(message: "Inställd", consequence: "CANCELLED", importanceLevel: 7)]
        )
        let running = departure(expected: "2026-08-31T22:00:00", state: "ATSTOP")

        let rows = SLRows.rows(from: [byState, byConsequence, running], now: now)
        #expect(rows[0].cancelled)
        #expect(rows[1].cancelled)
        #expect(rows[1].deviationText == "Inställd")
        #expect(rows[1].deviationLevel == 7)
        #expect(!rows[2].cancelled)
        #expect(rows[2].atStop)
    }

    @Test("Repeated deviation messages are joined once each")
    func dedupesDeviations() {
        let text = SLRows.deviationText([
            Deviation(message: "Hiss ur funktion", consequence: nil, importanceLevel: 3),
            Deviation(message: "Hiss ur funktion", consequence: nil, importanceLevel: 3),
            Deviation(message: "Rulltrappa avstängd", consequence: nil, importanceLevel: 5)
        ])
        #expect(text == "Hiss ur funktion · Rulltrappa avstängd")
    }

    @Test("walkMinutes hides what you could not physically catch")
    func appliesWalkMinutes() {
        let now = naive("2026-08-31T22:00:00")
        let rows = SLRows.rows(from: [
            departure(line: "13", expected: "2026-08-31T22:02:00"),
            departure(line: "14", expected: "2026-08-31T22:06:00"),
            departure(line: "13", expected: "2026-08-31T22:11:00")
        ], now: now)

        let config = StopConfig(siteId: 9192, walkMinutes: 5)
        let kept = SLRows.filter(rows, config: config)
        #expect(kept.map(\.minutes) == [6, 11])
    }

    @Test("The line whitelist is matched case-insensitively")
    func appliesLineFilter() {
        let now = naive("2026-08-31T22:00:00")
        let rows = SLRows.rows(from: [
            departure(line: "13", expected: "2026-08-31T22:02:00"),
            departure(line: "74", expected: "2026-08-31T22:03:00"),
            departure(line: "4x", expected: "2026-08-31T22:04:00")
        ], now: now)

        let config = StopConfig(siteId: 9192, lines: StopConfig.parseLineFilter("74, 4X"))
        #expect(SLRows.filter(rows, config: config).map(\.line) == ["74", "4x"])
    }

    @Test("Rows sort by wait, with an uncountable departure last")
    func sortsByWait() {
        let now = naive("2026-08-31T22:00:00")
        let rows = SLRows.rows(from: [
            departure(line: "A", display: "23:45"),
            departure(line: "B", expected: "2026-08-31T22:09:00"),
            departure(line: "C", expected: "2026-08-31T22:03:00")
        ], now: now)

        let sorted = SLRows.filter(rows, config: StopConfig(siteId: 9192))
        #expect(sorted.map(\.line) == ["C", "B", "A"])
        #expect(sorted.last?.minutes == nil)
        #expect(sorted.last?.minutesText == "?")
    }

    @Test("The bar drops cancellations and honours barCount; the board keeps them")
    func barRowsDropCancellations() {
        let now = naive("2026-08-31T22:00:00")
        let rows = SLRows.filter(SLRows.rows(from: [
            departure(line: "13", expected: "2026-08-31T22:02:00", state: "CANCELLED"),
            departure(line: "14", expected: "2026-08-31T22:04:00"),
            departure(line: "17", expected: "2026-08-31T22:06:00"),
            departure(line: "18", expected: "2026-08-31T22:08:00")
        ], now: now), config: StopConfig(siteId: 9192))

        #expect(rows.count == 4, "the board still lists the cancellation")
        let bar = SLRows.barRows(rows, config: StopConfig(siteId: 9192, barCount: 2))
        #expect(bar.map(\.line) == ["14", "17"])
    }

    @Test("Config bounds are applied wherever a value comes from")
    func clampsConfig() throws {
        let wild = StopConfig(
            siteId: -5, direction: 9, walkMinutes: 999, barCount: 99,
            panelCount: 0, forecastMinutes: 1, refreshIntervalSec: 2
        )
        #expect(wild.siteId == 0)
        #expect(wild.direction == 2)
        #expect(wild.walkMinutes == 120)
        #expect(wild.barCount == 6)
        #expect(wild.panelCount == 1)
        #expect(wild.forecastMinutes == 10)
        #expect(wild.refreshIntervalSec == 15)
        #expect(!wild.isConfigured)

        // A hand-edited settings file gets the same treatment.
        let json = #"{"siteId": 9192, "lines": "13, 14", "refreshIntervalSec": 1}"#
        let decoded = try JSONDecoder().decode(StopConfig.self, from: Data(json.utf8))
        #expect(decoded.siteId == 9192)
        #expect(decoded.lines == ["13", "14"])
        #expect(decoded.refreshIntervalSec == 15)
        #expect(decoded.barFormat == "{line} {wait}", "an absent key keeps its default")

        // And survives a round trip through the file it is written to.
        let round = try JSONDecoder().decode(StopConfig.self, from: JSONEncoder().encode(decoded))
        #expect(round.lines == ["13", "14"])
        #expect(round.siteId == 9192)
    }

    @Test("The departures URL carries the server-side filters and nothing else")
    func buildsDeparturesURL() {
        let plain = SLAPI.departuresURL(for: StopConfig(siteId: 9192))
        #expect(plain.absoluteString == "https://transport.integration.sl.se/v1/sites/9192/departures?forecast=90")

        let filtered = SLAPI.departuresURL(
            for: StopConfig(siteId: 9192, transport: "metro", direction: 1, lines: ["13"], walkMinutes: 5, forecastMinutes: 60)
        )
        #expect(filtered.absoluteString ==
                "https://transport.integration.sl.se/v1/sites/9192/departures?forecast=60&transport=METRO&direction=1",
                "lines and walkMinutes have no API equivalent and stay client-side")
    }
}
