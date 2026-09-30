import Foundation
import Testing
import SLKit
@testable import WidgetSupport

struct TimelineTests {
    @Test func lastEntryRetiresCountdowns() async throws {
        let now = Date()
        let future = SLClock.stockholmNow(now.addingTimeInterval(60 * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = .gmt
        let data = try JSONSerialization.data(withJSONObject: ["departures": [["expected": formatter.string(from: future)]]])
        let response = try JSONDecoder().decode(DeparturesResponse.self, from: data)
        var outcome = await BoardLoader().load(config: StopConfig())
        outcome.snapshot = DepartureSnapshot(departures: response.departures, fetchedAt: now)
        let entries = DeparturesProvider.entries(at: now, config: StopConfig(siteId: 9192), outcome: outcome)
        #expect(entries.count == SLWidgetKind.timelineMinutes + 1)
        #expect(entries.dropLast().allSatisfy { !$0.rows.isEmpty && !$0.isStale })
        let last = try #require(entries.last)
        #expect(last.date == now.addingTimeInterval(25 * 60))
        #expect(last.rows.isEmpty)
        #expect(last.isStale)
        #expect(last.fetchedAt == now)
    }
}
