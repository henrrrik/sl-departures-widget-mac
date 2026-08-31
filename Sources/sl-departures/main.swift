import Foundation
import SLKit

// Terminal access to the same model the app and the widget render, so a stop id
// can be found without opening anything, and so what the menu bar claims can be
// checked against the API by hand.
//
//   sl-departures search slussen        # stop ids matching "slussen"
//   sl-departures board 9192 [METRO]    # what is leaving, as the popup shows it
//   sl-departures bar 9192 [METRO]      # the menu bar label for that stop
//   sl-departures refresh               # re-download the stop list

let usage = """
Usage:
  sl-departures search <query>          Find stop ids by name
  sl-departures board <siteId> [mode]   The departure board
  sl-departures bar <siteId> [mode]     The menu bar label
  sl-departures refresh                 Re-download the stop list
"""

/// Columns by hand: `String(format:)` and Swift strings disagree about what a
/// character is the moment a destination has an å in it.
func pad(_ value: String, _ width: Int, alignRight: Bool = false) -> String {
    let padding = String(repeating: " ", count: max(0, width - value.count))
    return alignRight ? padding + value : value + padding
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func config(_ arguments: [String]) -> StopConfig {
    guard let siteId = Int(arguments.first ?? "") else { fail("expected a site id") }
    return StopConfig(
        siteId: siteId,
        transport: arguments.count > 1 ? arguments[1] : "",
        forecastMinutes: 90
    )
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail(usage) }
let rest = Array(arguments.dropFirst())

switch command {
case "search":
    guard let query = rest.first else { fail("expected something to search for") }
    let sites = try await SiteDirectory().sites()
    let hits = SLSites.search(sites, query: query, limit: 40)
    if hits.isEmpty { fail("no stop matches \(query)") }
    for site in hits {
        print(String(format: "%-8d %@", site.id, site.label))
    }

case "refresh":
    let sites = try await SiteDirectory().refresh()
    print("Cached \(sites.count) stops in \(SiteDirectory.defaultCacheURL().path)")

case "board", "bar":
    let stop = config(rest)
    var resolved = stop
    if let site = SLSites.find(try await SiteDirectory().sites(), id: stop.siteId) {
        resolved = StopConfig(rebuilding: stop, siteName: site.name)
    }
    let outcome = await BoardLoader().load(config: resolved)
    if let error = outcome.error { fail(error) }
    let rows = outcome.snapshot.rows(config: resolved)

    if command == "bar" {
        let label = SLFormat.barLabel(SLRows.barRows(rows, config: resolved), config: resolved)
        print("\(label.symbol ?? "-")  \(label.text)")
    } else {
        print(resolved.siteName.isEmpty ? "Site \(resolved.siteId)" : resolved.siteName)
        for row in rows.prefix(resolved.panelCount) {
            let wait = row.cancelled ? "CANCELLED" : row.waitLabel
            print(
                pad(row.mode, 6) + pad(row.line, 5) + pad(String(row.destination.prefix(28)), 30)
                    + pad(row.berth, 4) + pad(wait, 10, alignRight: true)
                    + (row.deviationText.isEmpty ? "" : "  ! " + row.deviationText)
            )
        }
        for message in outcome.snapshot.stopDeviations { print("! \(message)") }
    }

default:
    fail(usage)
}
