import Foundation

/// How long to stay off the API after SL answers 429.
///
/// SL's quota is enforced on the caller, not per endpoint — every URL answers
/// 429 once it trips — so one backoff covers every stop the app polls. Each
/// consecutive 429 doubles the wait up to the cap; any successful fetch clears
/// it. The same numbers the Omarchy widget's SlHub uses.
public struct SLBackoff: Sendable, Equatable {
    public static let floor: TimeInterval = 60
    public static let cap: TimeInterval = 600

    /// The wait the last 429 imposed, zero when not backing off.
    public private(set) var wait: TimeInterval = 0
    public private(set) var until: Date = .distantPast

    public init() {}

    public func isActive(at now: Date = Date()) -> Bool {
        now < until
    }

    /// Time left before fetching may resume, zero once it has lapsed.
    public func remaining(at now: Date = Date()) -> TimeInterval {
        max(0, until.timeIntervalSince(now))
    }

    /// A 429 that lands while the backoff already runs was sent before it
    /// started — requests for several stops can be in flight at once — so it
    /// is the same trip, not a further one, and does not double the wait.
    public mutating func rateLimited(at now: Date = Date()) {
        guard !isActive(at: now) else { return }
        wait = wait > 0 ? min(wait * 2, Self.cap) : Self.floor
        until = now.addingTimeInterval(wait)
    }

    public mutating func succeeded() {
        wait = 0
        until = .distantPast
    }

    /// What to show in place of the bare 429 while the backoff runs.
    public var message: String {
        t("SL rate limit reached, retrying in \(Int((wait / 60).rounded())) min")
    }
}
