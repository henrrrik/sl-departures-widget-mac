import Foundation
import Testing
@testable import SLKit

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    static func departures(_ name: String = "departures-slussen") throws -> DeparturesResponse {
        try JSONDecoder().decode(DeparturesResponse.self, from: data(name))
    }

    static func sites(_ name: String = "sites-sample") throws -> [Site] {
        SLSites.parse(try data(name))
    }
}

/// A wall-clock reading built in the API's frame, so tests can talk in the same
/// terms the payloads do.
func naive(_ text: String) -> Date {
    SLClock.parseNaive(text)!
}

/// A departure with only the fields the model actually reads.
func departure(
    line: String = "13",
    mode: String = "METRO",
    destination: String = "Norsborg",
    display: String? = nil,
    expected: String? = nil,
    scheduled: String? = nil,
    state: String? = nil,
    berth: String? = nil,
    journeyId: Int? = nil,
    deviations: [Deviation] = []
) -> Departure {
    var value = Departure()
    value.line = Departure.Line(designation: line, transportMode: mode)
    value.destination = destination
    value.display = display
    value.expected = expected
    value.scheduled = scheduled
    value.state = state
    value.stopPoint = Departure.StopPoint(designation: berth)
    value.journey = Departure.Journey(id: journeyId)
    value.deviations = deviations
    return value
}

extension Departure {
    init() {
        self.init(
            destination: nil, direction: nil, directionCode: nil, state: nil, display: nil,
            scheduled: nil, expected: nil, line: nil, journey: nil, stopPoint: nil, deviations: nil
        )
    }
}
