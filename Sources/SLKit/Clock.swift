import Foundation

/// SL reports departure times as naive `Europe/Stockholm` wall-clock strings,
/// so subtracting the machine's clock is only correct on a machine set to
/// Stockholm. Rather than assume that, the widget anchors itself to the API's
/// own clock: a departure reporting both a relative `display` ("4 min") and an
/// absolute `expected` pins down what "now" was when the server answered.
///
/// Every time in this type lives in one frame — a wall-clock reading parsed as
/// though it were UTC — so a naive timestamp and "now" are directly comparable.
public struct SLClock: Sendable, Hashable {
    /// The learned correction added to the real clock to land in the API's
    /// frame, or nil until a payload offers something to anchor on.
    public private(set) var offset: TimeInterval?

    public init(offset: TimeInterval? = nil) {
        self.offset = offset.flatMap { Self.isSane($0) ? $0 : nil }
    }

    /// Learns from a payload, keeping the previous anchor when this one carries
    /// no relative display to measure against — a stop whose departures are all
    /// far enough out that every `display` is a clock time never anchors, and
    /// runs on the Stockholm fallback instead.
    public mutating func anchor(with departures: [Departure], wallNow: Date = Date()) {
        guard let learned = Self.clockOffset(departures, wallNow: wallNow), Self.isSane(learned) else { return }
        offset = learned
    }

    /// "Now" in the API's frame — what every departure timestamp is measured
    /// against. Keeps ticking between fetches, which is what lets the board
    /// count down without touching the network.
    public func now(_ wallNow: Date = Date()) -> Date {
        if let offset { return wallNow.addingTimeInterval(offset) }
        return Self.stockholmNow(wallNow)
    }

    /// The no-anchor fallback: the machine's clock converted to Stockholm wall
    /// time. Foundation has a real timezone database, so unlike the QML engine
    /// this is exact — the anchoring above still earns its keep by surviving a
    /// machine whose clock is simply wrong.
    public static func stockholmNow(_ wallNow: Date = Date()) -> Date {
        let zone = TimeZone(identifier: "Europe/Stockholm") ?? .gmt
        return wallNow.addingTimeInterval(TimeInterval(zone.secondsFromGMT(for: wallNow)))
    }

    /// A legitimate anchor is bounded by how far a machine's clock can
    /// plausibly sit from Stockholm's — just over a day across the extremes of
    /// UTC-12 and UTC+14. Anything past that is a garbage anchor, not a clock.
    public static func isSane(_ offset: TimeInterval) -> Bool {
        abs(offset) < 26 * 3600
    }

    /// The median of every sample the payload offers, as the offset to add to
    /// the real clock. Returns nil when nothing in the payload is relative.
    public static func clockOffset(_ departures: [Departure], wallNow: Date) -> TimeInterval? {
        var samples: [TimeInterval] = []
        for departure in departures {
            guard let relative = relativeSeconds(departure.display),
                  let stamp = parseNaive(departure.expected ?? departure.scheduled)
            else { continue }
            // The server floors its minute counts, so each sample sits up to a
            // minute late; the half-minute correction centers them.
            let centering: TimeInterval = relative == 0 ? 0 : 30
            samples.append(stamp.timeIntervalSince1970 - relative - centering)
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return samples[samples.count / 2] - wallNow.timeIntervalSince1970
    }

    /// Seconds encoded by a relative `display` — "4 min" or "Nu"/"Now" — and
    /// nil for a clock time, which says nothing about the server's own clock.
    static func relativeSeconds(_ display: String?) -> TimeInterval? {
        let text = (display ?? "").trimmed()
        if text.isEmpty { return nil }
        if text.compare("nu", options: .caseInsensitive) == .orderedSame { return 0 }
        if text.compare("now", options: .caseInsensitive) == .orderedSame { return 0 }

        var digits = ""
        var rest = Substring(text)
        while let first = rest.first, first.isNumber {
            digits.append(first)
            rest = rest.dropFirst()
        }
        guard !digits.isEmpty, let minutes = Int(digits) else { return nil }
        guard rest.trimmed().compare("min", options: .caseInsensitive) == .orderedSame else { return nil }
        return TimeInterval(minutes) * 60
    }

    /// Parses "2026-08-31T22:11:00" as a wall-clock reading with no zone
    /// applied. Deliberately not an ISO8601 parser with a local-time default:
    /// what this returns is a point in the API's frame, not a real instant.
    public static func parseNaive(_ value: String?) -> Date? {
        guard let value, value.count >= 16 else { return nil }
        let c = Array(value)
        guard c[4] == "-", c[7] == "-", c[10] == "T" || c[10] == " ", c[13] == ":" else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            var out = 0
            for index in range {
                guard let digit = c[index].wholeNumberValue, c[index].isASCII, c[index].isNumber else { return nil }
                out = out * 10 + digit
            }
            return out
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16) else { return nil }
        var second = 0
        if c.count >= 19, c[16] == ":", let parsed = number(17..<19) { second = parsed }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: components)
    }

    /// Minutes until a departure, counted against the anchored clock.
    /// Timestamps lead because they keep ticking down between fetches; the
    /// relative `display` is only a fallback for a payload that somehow omits
    /// both times, and is frozen at whatever the last fetch said.
    public static func minutes(until departure: Departure, now: Date) -> Int? {
        if let stamp = parseNaive(departure.expected ?? departure.scheduled) {
            return max(0, Int((stamp.timeIntervalSince(now) / 60).rounded()))
        }
        if let relative = relativeSeconds(departure.display) {
            return Int(relative / 60)
        }
        return nil
    }

    /// The "HH:MM" a departure is expected at, straight out of the wall-clock
    /// string — no conversion, because it is already the local time of the stop.
    public static func clockText(_ departure: Departure) -> String {
        let stamp = departure.expected ?? departure.scheduled ?? ""
        guard stamp.count >= 16 else { return "" }
        let start = stamp.index(stamp.startIndex, offsetBy: 11)
        let end = stamp.index(start, offsetBy: 5)
        let text = String(stamp[start..<end])
        return text.count == 5 && text.dropFirst(2).first == ":" ? text : ""
    }
}
