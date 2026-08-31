import Foundation

public enum SLFormat {
    /// SL's `transport_mode` values mapped to SF Symbols. The Omarchy widget
    /// used Nerd Font glyphs because the bar font was a monospace it shipped;
    /// on macOS the system symbol set is the equivalent guarantee.
    static let modeSymbols: [String: String] = [
        "BUS": "bus.fill",
        "METRO": "tram.fill.tunnel",
        "TRAIN": "train.side.front.car",
        "TRAM": "tram.fill",
        "SHIP": "ferry.fill",
        "FERRY": "ferry.fill",
        "TAXI": "car.fill"
    ]
    static let defaultSymbol = "clock"

    static let modeNames: [String: String] = [
        "BUS": "Bus", "METRO": "Metro", "TRAIN": "Train", "TRAM": "Tram",
        "SHIP": "Ship", "FERRY": "Ferry", "TAXI": "Taxi"
    ]

    public static func symbol(for mode: String?) -> String {
        modeSymbols[(mode ?? "").uppercased()] ?? defaultSymbol
    }

    public static func modeName(_ mode: String?) -> String {
        let key = (mode ?? "").uppercased()
        if let name = modeNames[key] { return name }
        guard let first = key.first else { return "" }
        return String(first) + key.dropFirst().lowercased()
    }

    // MARK: - Waits
    //
    // Three renderings, because the unit belongs in a different place in each:
    // bare for user templates that supply their own unit, primed for the status
    // item where width is scarce, and spelled out for the popup rows. Under a
    // minute reads "now" rather than "0" — the number is the wait, and there
    // isn't one.

    public static func minutesText(_ minutes: Int?) -> String {
        guard let minutes else { return "?" }
        return minutes <= 0 ? "now" : String(minutes)
    }

    public static func waitText(_ minutes: Int?) -> String {
        guard let minutes else { return "?" }
        return minutes <= 0 ? "now" : "\(minutes)′"
    }

    public static func waitLabel(_ minutes: Int?) -> String {
        guard let minutes else { return "?" }
        return minutes <= 0 ? "now" : "\(minutes) min"
    }

    // MARK: - Bar label

    public enum LoadState: Sendable, Hashable {
        case loading, ready, failed
    }

    /// What a status item draws: an optional SF Symbol, taken from the soonest
    /// departure so a mixed stop shows whatever is actually next, and the text.
    /// Kept apart because a symbol is an image on macOS, not a codepoint that
    /// can be concatenated into the string.
    public struct BarLabel: Hashable, Sendable {
        public var symbol: String?
        public var text: String
    }

    public static func barLabel(
        _ rows: [DepartureRow],
        config: StopConfig,
        state: LoadState = .ready
    ) -> BarLabel {
        guard config.isConfigured else { return BarLabel(symbol: nil, text: "SL") }
        if rows.isEmpty {
            switch state {
            case .loading: return BarLabel(symbol: nil, text: "SL …")
            case .failed: return BarLabel(symbol: nil, text: "SL ✗")
            case .ready:
                return BarLabel(symbol: config.showIcon ? defaultSymbol : nil, text: "–")
            }
        }
        let segments = rows.map { segment(config.barFormat, row: $0) }.filter { !$0.isEmpty }
        return BarLabel(
            symbol: config.showIcon ? rows[0].symbol : nil,
            text: segments.joined(separator: " · ")
        )
    }

    /// One pass over the template, not a chain of replacements: a row field
    /// comes from the API and may itself contain a brace, and a chain would
    /// happily substitute into text it had already produced.
    public static func segment(_ template: String, row: DepartureRow) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[rest.startIndex..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else {
                // An unclosed brace is literal text, not a broken token.
                out += rest[open...]
                return out.trimmed()
            }
            let key = String(rest[afterOpen..<close])
            // An unknown token stays on screen as written, so a typo in
            // barFormat is visible rather than silently swallowing itself.
            out += field(key, of: row) ?? String(rest[open...close])
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return out.trimmed()
    }

    static func field(_ key: String, of row: DepartureRow) -> String? {
        switch key {
        case "line": row.line
        case "wait": row.waitText
        case "min": row.minutesText
        case "clock": row.clock
        case "display": row.display
        case "destination": row.destination
        // `{icon}` has no text form on macOS — the symbol is drawn beside the
        // label — so it resolves to nothing rather than to a stray glyph.
        case "icon": ""
        default: nil
        }
    }

    /// A one-line summary of what is currently being shown, for the popup
    /// header: the filters in force, not just the stop name.
    public static func filterSummary(_ config: StopConfig) -> String {
        var parts: [String] = []
        if !config.transport.isEmpty { parts.append(modeName(config.transport)) }
        if !config.lines.isEmpty { parts.append("Line " + config.lines.joined(separator: ", ")) }
        if config.direction != 0 { parts.append("Direction \(config.direction)") }
        if config.walkMinutes > 0 { parts.append("\(config.walkMinutes) min walk") }
        return parts.joined(separator: " · ")
    }
}
