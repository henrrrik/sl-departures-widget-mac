import AppIntents
import SLKit
import WidgetKit

enum TransportOption: String, AppEnum {
    case all, bus, metro, tram, train, ship, ferry

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Transport")
    static let caseDisplayRepresentations: [TransportOption: DisplayRepresentation] = [
        .all: "All modes", .bus: "Bus", .metro: "Metro", .tram: "Tram",
        .train: "Train", .ship: "Ship", .ferry: "Ferry"
    ]

    var apiValue: String { self == .all ? "" : rawValue.uppercased() }
}

enum DirectionOption: Int, AppEnum {
    case both = 0, one = 1, two = 2

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Direction")
    static let caseDisplayRepresentations: [DirectionOption: DisplayRepresentation] = [
        .both: "Both directions", .one: "Direction 1", .two: "Direction 2"
    ]
}

/// Everything one widget instance is configured with — the same knobs a status
/// item has, minus the ones only a menu bar label needs.
struct DeparturesConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "SL Departures"
    static let description = IntentDescription("Live departures for a Stockholm stop.")

    @Parameter(title: "Stop")
    var stop: SiteEntity?

    @Parameter(title: "Transport", default: .all)
    var transport: TransportOption

    @Parameter(title: "Direction", default: .both)
    var direction: DirectionOption

    @Parameter(title: "Lines", description: "All lines, or e.g. 13, 14")
    var lines: String?

    @Parameter(title: "Walk (minutes)", default: 0, inclusiveRange: (0, 120))
    var walkMinutes: Int

    /// Folds the widget's configuration into the same type the app and the
    /// model work in, so there is one set of rules for both surfaces.
    func stopConfig() -> StopConfig {
        StopConfig(
            siteId: stop?.id ?? 0,
            siteName: stop?.name ?? "",
            transport: transport.apiValue,
            direction: direction.rawValue,
            lines: StopConfig.parseLineFilter(lines ?? ""),
            walkMinutes: walkMinutes,
            panelCount: 8,
            forecastMinutes: 90
        )
    }
}

/// The tile's own refresh button. A reload a person asked for is not subject to
/// the budget that paces the timeline, which is why this is worth having.
struct RefreshDeparturesIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh departures"

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: SLWidgetKind.departures)
        return .result()
    }
}
