import Foundation
import Testing
@testable import SLKit

@Suite("Board")
struct BoardTests {
    /// A machine running two hours behind the API's frame — the everyday case
    /// this whole clock dance exists for — with the offset stated rather than
    /// learned, so the arithmetic under test is the board's and not the anchor's.
    /// (`ClockTests` covers the learning.)
    static let serverNow = naive("2026-08-31T22:00:00")
    static let fetchedAt = serverNow.addingTimeInterval(-7200)

    func snapshot() -> DepartureSnapshot {
        DepartureSnapshot(
            departures: [
                departure(line: "13", display: "1 min", expected: "2026-08-31T22:01:00", journeyId: 1),
                departure(line: "14", display: "5 min", expected: "2026-08-31T22:05:00", journeyId: 2),
                departure(line: "17", display: "12 min", expected: "2026-08-31T22:12:00", journeyId: 3),
                departure(line: "18", display: "20 min", expected: "2026-08-31T22:20:00", journeyId: 4)
            ],
            stopDeviations: ["Hiss ur funktion"],
            clock: SLClock(offset: 7200),
            fetchedAt: Self.fetchedAt
        )
    }

    @Test("One fetch renders correctly at any later minute")
    func recomputesWithoutRefetching() {
        let fetchedAt = Self.fetchedAt
        let board = snapshot()
        let config = StopConfig(siteId: 9192, panelCount: 12)

        #expect(board.rows(at: fetchedAt, config: config).map(\.minutes) == [1, 5, 12, 20])
        #expect(board.rows(at: fetchedAt.addingTimeInterval(240), config: config).map(\.minutes) == [1, 8, 16])
    }

    @Test("Departed services drop off and the later ones slide up")
    func dropsDepartedServices() {
        // The behaviour a widget depends on: the OS renders precomputed entries
        // for the next 25 minutes without waking the extension, so a departed
        // train has to leave the board on its own rather than pile up at "now".
        let fetchedAt = Self.fetchedAt
        let board = snapshot()
        let config = StopConfig(siteId: 9192)

        #expect(board.rows(at: fetchedAt.addingTimeInterval(6 * 60), config: config).map(\.line) == ["17", "18"])
        #expect(board.rows(at: fetchedAt.addingTimeInterval(25 * 60), config: config).isEmpty)
    }

    @Test("Filters apply at every point in the timeline, not just at fetch time")
    func appliesFiltersPerEntry() {
        let fetchedAt = Self.fetchedAt
        let board = snapshot()
        let config = StopConfig(siteId: 9192, lines: ["14", "17"], walkMinutes: 6)

        #expect(board.rows(at: fetchedAt, config: config).map(\.line) == ["17"],
                "line 14 is inside the six minute walk")
        #expect(board.rows(at: fetchedAt.addingTimeInterval(120), config: config).map(\.line) == ["17"])
    }

    @Test("A failed refresh keeps the board on screen rather than blanking it")
    func keepsBoardThroughFailure() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefusingProtocol.self]
        let loader = BoardLoader(client: SLClient(session: URLSession(configuration: configuration)))

        let previous = snapshot()
        let outcome = await loader.load(config: StopConfig(siteId: 9192), previous: previous)

        #expect(outcome.state == .failed)
        #expect(outcome.error != nil)
        #expect(outcome.snapshot.departures.count == previous.departures.count,
                "the last good payload is still there to count down from")
    }

    @Test("An unconfigured stop is not a fetch")
    func skipsUnconfiguredStop() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefusingProtocol.self]
        let loader = BoardLoader(client: SLClient(session: URLSession(configuration: configuration)))

        let outcome = await loader.load(config: StopConfig())
        #expect(outcome.state == .ready)
        #expect(outcome.error == nil)
        #expect(outcome.snapshot.isEmpty)
    }
}
