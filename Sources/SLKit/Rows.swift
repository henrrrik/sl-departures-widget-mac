import Foundation

/// One departure, flattened into exactly what a view binds to — so no SwiftUI
/// row has to reach through `departure.line.designation` and friends, and the
/// minute arithmetic happens once per tick rather than once per redraw.
public struct DepartureRow: Identifiable, Hashable, Sendable {
    public var id: String
    public var line: String
    /// SL's `transport_mode`, uppercased: BUS, METRO, TRAM, TRAIN, SHIP, FERRY.
    public var mode: String
    /// SF Symbol name for `mode` — a plain string, so SLKit stays free of any
    /// UI framework and stays testable with `swift test`.
    public var symbol: String
    public var destination: String
    public var direction: Int
    /// Minutes until departure, or nil when the payload gave nothing to count.
    public var minutes: Int?
    public var clock: String
    /// SL's own words for the wait, e.g. "Nu" or "4 min".
    public var display: String
    public var atStop: Bool
    public var cancelled: Bool
    /// The berth letter, e.g. "D".
    public var berth: String
    public var deviationText: String
    public var deviationLevel: Int

    public var minutesText: String { SLFormat.minutesText(minutes) }
    public var waitText: String { SLFormat.waitText(minutes) }
    public var waitLabel: String { SLFormat.waitLabel(minutes) }
}

public enum SLRows {
    /// API strings reach a status item title, where a pathological length would
    /// be a usability problem rather than a security one. Cheap to bound.
    static let maxFieldLength = 120

    public static func rows(from departures: [Departure], now: Date) -> [DepartureRow] {
        departures.enumerated().map { index, departure in
            let line = departure.line
            let deviations = departure.deviations ?? []
            let state = (departure.state ?? "").uppercased()
            let cancelled = state == "CANCELLED"
                || deviations.contains { ($0.consequence ?? "").uppercased() == "CANCELLED" }
            let mode = (line?.transportMode ?? "").uppercased()

            return DepartureRow(
                id: "\(departure.journey?.id ?? index):\(departure.scheduled ?? String(index))",
                line: clip(line?.designation),
                mode: mode,
                symbol: SLFormat.symbol(for: mode),
                destination: clip(departure.destination ?? departure.direction),
                direction: departure.directionCode ?? 0,
                minutes: SLClock.minutes(until: departure, now: now),
                clock: SLClock.clockText(departure),
                display: clip(departure.display),
                atStop: state == "ATSTOP",
                cancelled: cancelled,
                berth: clip(departure.stopPoint?.designation),
                deviationText: deviationText(deviations),
                deviationLevel: deviations.map { $0.importanceLevel ?? 0 }.max() ?? 0
            )
        }
    }

    /// Client-side narrowing the API has no equivalent for: the line whitelist,
    /// and dropping departures that leave before you could physically get
    /// there. Sorted because a line filter can interleave modes the API
    /// returned in separate blocks.
    public static func filter(_ rows: [DepartureRow], config: StopConfig) -> [DepartureRow] {
        rows.filter { row in
            if !config.lines.isEmpty, !config.lines.contains(row.line.uppercased()) { return false }
            if let minutes = row.minutes, minutes < config.walkMinutes { return false }
            return true
        }
        .sorted { ($0.minutes ?? .max) < ($1.minutes ?? .max) }
    }

    /// What the status item shows. Cancellations are dropped here because the
    /// bar is a list of what you can actually board; the popup still lists
    /// them, struck through, because a cancellation is exactly the thing you
    /// open the popup to find out about.
    public static func barRows(_ rows: [DepartureRow], config: StopConfig) -> [DepartureRow] {
        Array(rows.lazy.filter { !$0.cancelled }.prefix(config.barCount))
    }

    static func deviationText(_ deviations: [Deviation]) -> String {
        var seen: [String] = []
        for deviation in deviations {
            let message = clip(deviation.message)
            if !message.isEmpty, !seen.contains(message) { seen.append(message) }
        }
        return seen.joined(separator: " · ")
    }

    static func clip(_ value: String?) -> String {
        let text = (value ?? "").trimmed()
        return text.count <= maxFieldLength ? text : String(text.prefix(maxFieldLength))
    }
}
