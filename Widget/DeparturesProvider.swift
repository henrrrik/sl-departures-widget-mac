import SLKit
import WidgetKit

struct DeparturesEntry: TimelineEntry {
    var date: Date
    var siteName: String
    var rows: [DepartureRow]
    var stopDeviations: [String]
    var fetchedAt: Date?
    var error: String?
    var isPlaceholder = false
    var isStale = false
}

/// One fetch per reload, rendered as a whole run of entries.
///
/// WidgetKit budgets how often it will wake this extension — on the order of
/// once every 15 minutes or worse — but it renders precomputed entries for
/// free, without waking anything. So a single fetch is expanded into an entry
/// per minute: the tile counts down correctly the whole time, departed services
/// drop off, and the ones behind them slide up. What a reload actually buys is
/// *new* information — a cancellation, a delay — not the arithmetic.
struct DeparturesProvider: AppIntentTimelineProvider {
    private static let loader = WidgetBoardLoader()

    func placeholder(in context: Context) -> DeparturesEntry {
        DeparturesEntry(
            date: Date(),
            siteName: "Slussen",
            rows: [],
            stopDeviations: [],
            fetchedAt: nil,
            error: nil,
            isPlaceholder: true
        )
    }

    func snapshot(for configuration: DeparturesConfigurationIntent, in context: Context) async -> DeparturesEntry {
        let config = configuration.stopConfig()
        guard config.isConfigured else { return placeholder(in: context) }
        let result = await Self.loader.load(config: config)
        return Self.entry(at: Date(), config: config, outcome: result.outcome)
    }

    func timeline(for configuration: DeparturesConfigurationIntent, in context: Context) async -> Timeline<DeparturesEntry> {
        let config = configuration.stopConfig()
        guard config.isConfigured else {
            return Timeline(entries: [placeholder(in: context)], policy: .never)
        }

        let result = await Self.loader.load(config: config)
        let now = Date()
        let entries = Self.entries(at: now, config: config, outcome: result.outcome)
        let retryAt = result.retryAt ?? now.addingTimeInterval(result.outcome.error == nil ? 15 * 60 : 5 * 60)
        return Timeline(entries: entries, policy: .after(retryAt))
    }

    static func entries(at now: Date, config: StopConfig, outcome: BoardLoader.Outcome) -> [DeparturesEntry] {
        var entries = (0..<SLWidgetKind.timelineMinutes).map { minute in
            entry(at: now.addingTimeInterval(TimeInterval(minute) * 60), config: config, outcome: outcome)
        }
        // Reload dates are requests, not deadlines. Once these countdowns run
        // out, explicitly retire them even if WidgetKit postpones our fetch.
        var expired = entry(at: now.addingTimeInterval(TimeInterval(SLWidgetKind.timelineMinutes) * 60),
                            config: config, outcome: outcome)
        expired.rows = []
        expired.stopDeviations = []
        expired.isStale = outcome.error == nil
        entries.append(expired)
        return entries
    }

    private static func entry(at date: Date, config: StopConfig, outcome: BoardLoader.Outcome) -> DeparturesEntry {
        DeparturesEntry(
            date: date,
            siteName: config.siteName,
            rows: Array(outcome.snapshot.rows(at: date, config: config).prefix(config.panelCount)),
            stopDeviations: outcome.snapshot.stopDeviations,
            fetchedAt: outcome.snapshot.isEmpty ? nil : outcome.snapshot.fetchedAt,
            error: outcome.error
        )
    }
}
