import Foundation

/// All widget instances share this loader. The persisted deadline also survives
/// extension restarts, so an explicit reload cannot bypass an SL cooldown.
public actor WidgetBoardLoader {
    private let loader: BoardLoader
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private static let cooldownKey = "sl.departures.widget.rateLimitUntil"

    public init(
        loader: BoardLoader = BoardLoader(),
        defaultsSuiteName: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.loader = loader
        self.defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.now = now
    }

    public func load(config: StopConfig) async -> (outcome: BoardLoader.Outcome, retryAt: Date?) {
        let date = now()
        let deadline = Date(timeIntervalSince1970: defaults.double(forKey: Self.cooldownKey))
        if config.isConfigured, deadline > date {
            return (
                BoardLoader.Outcome(snapshot: DepartureSnapshot(), error: SLError.rateLimited.errorDescription,
                                    state: .failed, rateLimited: true),
                deadline
            )
        }
        let outcome = await loader.load(config: config, wallNow: date)
        if outcome.rateLimited {
            let deadline = max(defaults.double(forKey: Self.cooldownKey), now().addingTimeInterval(SLBackoff.cap).timeIntervalSince1970)
            defaults.set(deadline, forKey: Self.cooldownKey)
        }
        // A successful request that was already in flight must not clear a
        // cooldown established by a different widget's response.
        let retry = Date(timeIntervalSince1970: defaults.double(forKey: Self.cooldownKey))
        return (outcome, retry > now() ? retry : nil)
    }
}
