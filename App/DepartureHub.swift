import Foundation
import Observation
import SLKit
import WidgetKit

/// One fetch loop per distinct departures URL, shared by every status item that
/// wants it.
///
/// Two stops configured on the same site and filters — a duplicate status item,
/// or the same stop shown twice with different bar formats — cost exactly one
/// request between them, because the per-instance settings (`barCount`,
/// `lines`, `walkMinutes`, `barFormat`) are applied when a view renders the
/// snapshot rather than when it is fetched. This is `SlHub.qml`'s arrangement,
/// unchanged.
@MainActor
@Observable
final class DepartureHub {
    static let shared = DepartureHub()

    private var streams: [String: StopStream] = [:]
    private let loader: BoardLoader

    init(loader: BoardLoader = BoardLoader()) {
        self.loader = loader
    }

    /// The stream for a config's fetch parameters, started on first use.
    func stream(for config: StopConfig) -> StopStream {
        let key = Self.key(for: config)
        if let existing = streams[key] {
            existing.register(config)
            return existing
        }
        let stream = StopStream(config: config, loader: loader)
        streams[key] = stream
        stream.start()
        return stream
    }

    func release(_ config: StopConfig) {
        let key = Self.key(for: config)
        guard let stream = streams[key] else { return }
        stream.unregister(config)
        if stream.isIdle {
            stream.stop()
            streams.removeValue(forKey: key)
        }
    }

    func refreshAll() {
        for stream in streams.values { stream.refreshNow() }
    }

    /// The URL is the identity: it already encodes the site and every filter the
    /// API applies server-side, and nothing else changes what comes back.
    static func key(for config: StopConfig) -> String {
        SLAPI.departuresURL(for: config).absoluteString
    }
}

/// The departures for one URL, refetched on a timer and recounted between
/// fetches.
@MainActor
@Observable
final class StopStream {
    private(set) var snapshot = DepartureSnapshot()
    private(set) var state: SLFormat.LoadState = .loading
    private(set) var error: String?
    /// Bumped every countdown tick. Views read it so a redraw is driven by the
    /// clock moving, not by a fetch — which is what keeps the minutes honest
    /// between the 30 second refreshes.
    private(set) var tick = Date()

    /// How often a *rendered* minute can change. Independent of the fetch
    /// interval: the countdown comes from timestamps, not from the payload.
    static let countdownInterval: TimeInterval = 15

    private let loader: BoardLoader
    private let url: String
    private var fetchConfig: StopConfig
    private var subscribers: [UUID: StopConfig] = [:]
    private var fetchTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    init(config: StopConfig, loader: BoardLoader) {
        self.loader = loader
        self.url = DepartureHub.key(for: config)
        self.fetchConfig = config
        self.subscribers = [config.id: config]
    }

    var isIdle: Bool { subscribers.isEmpty }

    func register(_ config: StopConfig) {
        subscribers[config.id] = config
        // The most frequent subscriber sets the pace for everyone on this URL.
        if config.refreshIntervalSec < fetchConfig.refreshIntervalSec {
            fetchConfig = config
            restartTimer()
        }
    }

    func unregister(_ config: StopConfig) {
        subscribers.removeValue(forKey: config.id)
    }

    func start() {
        guard fetchTask == nil else { return }
        restartTimer()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.countdownInterval))
                guard let self else { return }
                self.tick = Date()
            }
        }
    }

    func stop() {
        fetchTask?.cancel()
        tickTask?.cancel()
        fetchTask = nil
        tickTask = nil
    }

    func refreshNow() {
        restartTimer()
    }

    private func restartTimer() {
        fetchTask?.cancel()
        let interval = TimeInterval(fetchConfig.refreshIntervalSec)
        fetchTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchOnce()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func fetchOnce() async {
        let outcome = await loader.load(config: fetchConfig, previous: snapshot.isEmpty ? nil : snapshot)
        guard !Task.isCancelled else { return }

        snapshot = outcome.snapshot
        error = outcome.error
        // A failed refresh with a board already on screen is not an error state:
        // the countdown is still correct, it is just not getting newer.
        state = outcome.state == .failed && !snapshot.isEmpty ? .ready : outcome.state
        tick = Date()

        // The app is running anyway, and a reload it asks for is treated far
        // more favourably than one the widget's own timeline requests — this is
        // the only real lever on the widget's refresh cadence.
        if outcome.error == nil {
            WidgetCenter.shared.reloadTimelines(ofKind: SLWidgetKind.departures)
        }
    }

    /// The board as one subscriber should see it right now.
    func rows(for config: StopConfig) -> [DepartureRow] {
        _ = tick  // observed, so a countdown tick redraws the caller
        return snapshot.rows(at: Date(), config: config)
    }
}
