import Foundation

/// Everything one status item — or one widget instance — is configured to show.
///
/// The defaults and bounds here are the single authority, exactly as
/// `Model.resolveConfig` was in the Omarchy widget: nothing else in the app or
/// the extension repeats a default or re-clamps a value. Clamping lives in the
/// initializer so a hand-edited settings file and an AppIntent-configured
/// widget land on the same rules.
public struct StopConfig: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var siteId: Int
    public var siteName: String
    /// `""` for every mode, or one of BUS / METRO / TRAM / TRAIN / SHIP / FERRY.
    public var transport: String
    /// `0` for both, or SL's direction code `1` / `2` for the stop.
    public var direction: Int
    /// Line designations to keep; empty keeps every line.
    public var lines: [String]
    /// Hides departures leaving sooner than this, so the board only shows what
    /// you could still catch.
    public var walkMinutes: Int
    public var barCount: Int
    public var panelCount: Int
    public var forecastMinutes: Int
    public var refreshIntervalSec: Int
    public var barFormat: String
    public var showIcon: Bool

    public init(
        id: UUID = UUID(),
        siteId: Int = 0,
        siteName: String = "",
        transport: String = "",
        direction: Int = 0,
        lines: [String] = [],
        walkMinutes: Int = 0,
        barCount: Int = 2,
        panelCount: Int = 12,
        forecastMinutes: Int = 90,
        refreshIntervalSec: Int = 30,
        barFormat: String = "{line} {wait}",
        showIcon: Bool = true
    ) {
        self.id = id
        self.siteId = max(0, siteId)
        self.siteName = siteName.trimmed()
        self.transport = transport.trimmed().uppercased()
        self.direction = direction.clamped(to: 0...2)
        self.lines = lines
        self.walkMinutes = walkMinutes.clamped(to: 0...120)
        self.barCount = barCount.clamped(to: 1...6)
        self.panelCount = panelCount.clamped(to: 1...40)
        self.forecastMinutes = forecastMinutes.clamped(to: 10...360)
        self.refreshIntervalSec = refreshIntervalSec.clamped(to: 15...600)
        self.barFormat = barFormat
        self.showIcon = showIcon
    }

    /// A copy with some fields changed, re-clamped on the way through.
    ///
    /// Every control in the settings window edits a config this way, so a
    /// bound value can never sidestep the rules in the initializer above —
    /// there is one authority, not one per control.
    public init(
        rebuilding base: StopConfig,
        siteId: Int? = nil,
        siteName: String? = nil,
        transport: String? = nil,
        direction: Int? = nil,
        lines: [String]? = nil,
        walkMinutes: Int? = nil,
        barCount: Int? = nil,
        panelCount: Int? = nil,
        forecastMinutes: Int? = nil,
        refreshIntervalSec: Int? = nil,
        barFormat: String? = nil,
        showIcon: Bool? = nil
    ) {
        self.init(
            id: base.id,
            siteId: siteId ?? base.siteId,
            siteName: siteName ?? base.siteName,
            transport: transport ?? base.transport,
            direction: direction ?? base.direction,
            lines: lines ?? base.lines,
            walkMinutes: walkMinutes ?? base.walkMinutes,
            barCount: barCount ?? base.barCount,
            panelCount: panelCount ?? base.panelCount,
            forecastMinutes: forecastMinutes ?? base.forecastMinutes,
            refreshIntervalSec: refreshIntervalSec ?? base.refreshIntervalSec,
            barFormat: barFormat ?? base.barFormat,
            showIcon: showIcon ?? base.showIcon
        )
    }

    /// Splits `"13, 14"` — the way lines are written by hand and by the settings
    /// UI — into the whitelist `filterRows` applies.
    public static func parseLineFilter(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.trimmed().uppercased() }
            .filter { !$0.isEmpty }
    }

    public var linesText: String { lines.joined(separator: ", ") }

    /// True once the config names a stop to fetch.
    public var isConfigured: Bool { siteId > 0 }

    // MARK: - Codable

    // The settings file is meant to be opened and edited by hand, so `lines`
    // decodes from either the comma string a person would type or the array a
    // previous encode produced, and every key is optional — a file naming only
    // a siteId is a working configuration. Values still pass through init(),
    // which is what re-applies the bounds to whatever was typed.
    private enum CodingKeys: String, CodingKey {
        case id, siteId, siteName, transport, direction, lines, walkMinutes
        case barCount, panelCount, forecastMinutes, refreshIntervalSec, barFormat, showIcon
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lines: [String]
        if let text = try? c.decode(String.self, forKey: .lines) {
            lines = Self.parseLineFilter(text)
        } else if let list = try? c.decode([String].self, forKey: .lines) {
            lines = Self.parseLineFilter(list.joined(separator: ","))
        } else {
            lines = []
        }
        let defaults = StopConfig()
        self.init(
            id: (try? c.decode(UUID.self, forKey: .id)) ?? UUID(),
            siteId: (try? c.decode(Int.self, forKey: .siteId)) ?? defaults.siteId,
            siteName: (try? c.decode(String.self, forKey: .siteName)) ?? defaults.siteName,
            transport: (try? c.decode(String.self, forKey: .transport)) ?? defaults.transport,
            direction: (try? c.decode(Int.self, forKey: .direction)) ?? defaults.direction,
            lines: lines,
            walkMinutes: (try? c.decode(Int.self, forKey: .walkMinutes)) ?? defaults.walkMinutes,
            barCount: (try? c.decode(Int.self, forKey: .barCount)) ?? defaults.barCount,
            panelCount: (try? c.decode(Int.self, forKey: .panelCount)) ?? defaults.panelCount,
            forecastMinutes: (try? c.decode(Int.self, forKey: .forecastMinutes)) ?? defaults.forecastMinutes,
            refreshIntervalSec: (try? c.decode(Int.self, forKey: .refreshIntervalSec)) ?? defaults.refreshIntervalSec,
            barFormat: (try? c.decode(String.self, forKey: .barFormat)) ?? defaults.barFormat,
            showIcon: (try? c.decode(Bool.self, forKey: .showIcon)) ?? defaults.showIcon
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(siteId, forKey: .siteId)
        try c.encode(siteName, forKey: .siteName)
        try c.encode(transport, forKey: .transport)
        try c.encode(direction, forKey: .direction)
        // As the comma string, so the file keeps reading the way a person writes it.
        try c.encode(linesText, forKey: .lines)
        try c.encode(walkMinutes, forKey: .walkMinutes)
        try c.encode(barCount, forKey: .barCount)
        try c.encode(panelCount, forKey: .panelCount)
        try c.encode(forecastMinutes, forKey: .forecastMinutes)
        try c.encode(refreshIntervalSec, forKey: .refreshIntervalSec)
        try c.encode(barFormat, forKey: .barFormat)
        try c.encode(showIcon, forKey: .showIcon)
    }
}

// MARK: - Small shared helpers

extension String {
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Substring {
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
