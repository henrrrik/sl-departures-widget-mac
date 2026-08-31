import Foundation

/// One fetch's worth of data, kept in its raw form so the board can be
/// recomputed at any later moment without touching the network.
///
/// This is what lets both surfaces count down between fetches — the status item
/// on a 15 second tick, and the widget by precomputing an entry per minute for
/// the OS to render while the extension is asleep.
public struct DepartureSnapshot: Sendable {
    public var departures: [Departure]
    public var stopDeviations: [String]
    /// The clock learned from this payload, carried forward across fetches.
    public var clock: SLClock
    /// Real-clock instant the payload arrived, for the "updated HH:MM" line.
    public var fetchedAt: Date

    public init(
        departures: [Departure] = [],
        stopDeviations: [String] = [],
        clock: SLClock = SLClock(),
        fetchedAt: Date = Date()
    ) {
        self.departures = departures
        self.stopDeviations = stopDeviations
        self.clock = clock
        self.fetchedAt = fetchedAt
    }

    public var isEmpty: Bool { departures.isEmpty }

    /// The board as it should read at `wallNow`, filters applied.
    ///
    /// Departures already gone are dropped rather than pinned at "now": with
    /// the app's 30 second refresh they would never accumulate, but a widget
    /// renders precomputed entries for the next 25 minutes, and without this
    /// the tile would slowly fill with departed trains instead of letting the
    /// later ones slide up into view.
    public func rows(at wallNow: Date = Date(), config: StopConfig) -> [DepartureRow] {
        let now = clock.now(wallNow)
        let live = departures.filter { departure in
            guard let stamp = SLClock.parseNaive(departure.expected ?? departure.scheduled) else { return true }
            return (stamp.timeIntervalSince(now) / 60).rounded() >= 0
        }
        return SLRows.filter(SLRows.rows(from: live, now: now), config: config)
    }
}

/// Fetches one stop and folds the result into a snapshot.
///
/// A failed refresh returns the previous snapshot rather than an empty one, so
/// the board keeps counting down through an outage instead of blanking — the
/// behaviour the Omarchy widget's SlHub had, and the reason `previous` is an
/// argument rather than something the caller patches up afterwards.
public struct BoardLoader: Sendable {
    private let client: SLClient

    public init(client: SLClient = SLClient()) {
        self.client = client
    }

    public struct Outcome: Sendable {
        public var snapshot: DepartureSnapshot
        public var error: String?
        public var state: SLFormat.LoadState
    }

    public func load(
        config: StopConfig,
        previous: DepartureSnapshot? = nil,
        wallNow: Date = Date()
    ) async -> Outcome {
        guard config.isConfigured else {
            return Outcome(snapshot: DepartureSnapshot(), error: nil, state: .ready)
        }
        do {
            let response = try await client.departures(for: config)
            var clock = previous?.clock ?? SLClock()
            clock.anchor(with: response.departures, wallNow: wallNow)
            let snapshot = DepartureSnapshot(
                departures: response.departures,
                stopDeviations: response.stopDeviations.compactMap {
                    let message = SLRows.clip($0.message)
                    return message.isEmpty ? nil : message
                },
                clock: clock,
                fetchedAt: wallNow
            )
            return Outcome(snapshot: snapshot, error: nil, state: .ready)
        } catch {
            let message = (error as? SLError)?.errorDescription ?? error.localizedDescription
            return Outcome(
                snapshot: previous ?? DepartureSnapshot(),
                error: message,
                state: .failed
            )
        }
    }
}

/// The widget kind, named in one place because the app pushes reloads to it and
/// the extension declares it.
public enum SLWidgetKind {
    public static let departures = "SLDeparturesWidget"
    /// How far ahead the widget precomputes entries. WidgetKit renders each one
    /// without waking the extension, so this is the window over which the tile
    /// stays arithmetically correct without a reload.
    public static let timelineMinutes = 25
}
