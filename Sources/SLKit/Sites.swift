import Foundation

/// One SL stop, with its search keys precomputed.
///
/// The folding happens once per list load rather than inside the search loop:
/// the picker searches all ~6500 stops on every keystroke, and folding in the
/// loop would redo a few million character comparisons per keypress.
public struct Site: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let note: String
    let folded: String
    let foldedNote: String

    public init(id: Int, name: String, note: String = "") {
        self.id = id
        self.name = name
        self.note = note
        self.folded = SLSites.fold(name)
        self.foldedNote = note.isEmpty ? "" : SLSites.fold(note)
    }

    /// Name plus the disambiguating note SL attaches to stops that share one.
    public var label: String { note.isEmpty ? name : "\(name) (\(note))" }
}

public enum SLSites {
    public static func parse(_ data: Data) -> [Site] {
        guard let raw = try? JSONDecoder().decode([RawSite].self, from: data) else { return [] }
        return raw.compactMap { site in
            let name = SLRows.clip(site.name)
            guard !name.isEmpty else { return nil }
            return Site(id: site.id, name: name, note: SLRows.clip(site.note))
        }
    }

    /// Diacritic folding, so a stop can be found from a keyboard the typist
    /// actually has: "sodermalm" reaches Södermalm, "radmans" reaches
    /// Rådmansgatan.
    public static func fold(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Ranked substring search. Prefix matches come first, because typing "slu"
    /// should surface Slussen ahead of every stop that merely contains "slu";
    /// a match found only in the note ranks below every name match.
    public static func search(_ sites: [Site], query: String, limit: Int = 8) -> [Site] {
        let needle = fold(query.trimmed())
        guard !needle.isEmpty else { return [] }

        var scored: [(site: Site, score: Int)] = []
        for site in sites {
            var position: Int
            if let range = site.folded.range(of: needle) {
                position = site.folded.distance(from: site.folded.startIndex, to: range.lowerBound)
            } else if !site.foldedNote.isEmpty, site.foldedNote.contains(needle) {
                position = 100
            } else {
                continue
            }
            scored.append((site, position * 1000 + site.folded.count))
        }
        scored.sort { left, right in
            left.score == right.score
                ? left.site.name.localizedCompare(right.site.name) == .orderedAscending
                : left.score < right.score
        }
        return scored.prefix(max(0, limit)).map(\.site)
    }

    public static func find(_ sites: [Site], id: Int) -> Site? {
        sites.first { $0.id == id }
    }

    /// Used when a config names a stop but not an id, so `"siteName": "Slussen"`
    /// alone is a working configuration.
    public static func find(_ sites: [Site], name: String) -> Site? {
        let needle = fold(name.trimmed())
        guard !needle.isEmpty else { return nil }
        return sites.first { $0.folded == needle }
    }
}

/// The stop list, cached on disk and refreshed weekly.
///
/// The app and the widget extension keep separate caches — the extension is
/// sandboxed into its own container, and staying out of an App Group is what
/// keeps this project free of provisioning-profile entitlements. The list is
/// ~6500 stops that change on the order of never, so the duplication costs one
/// download a week per surface.
public actor SiteDirectory {
    public static let maxAge: TimeInterval = 7 * 24 * 3600

    private let cacheURL: URL
    private let client: SLClient
    private var cached: [Site] = []

    public init(cacheURL: URL? = nil, client: SLClient = SLClient()) {
        self.cacheURL = cacheURL ?? SiteDirectory.defaultCacheURL()
        self.client = client
    }

    public static func defaultCacheURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("io.github.henrrrik.sl-departures", isDirectory: true)
            .appendingPathComponent("sl-sites.json")
    }

    /// Parsed once per process. Serves the cache when it is fresh, downloads
    /// when it is missing or a week old, and falls back to a stale cache when
    /// the download fails — a stop list that is a week out of date still finds
    /// Slussen.
    public func sites() async throws -> [Site] {
        if !cached.isEmpty { return cached }

        if let data = readCache(), let age = cacheAge(), age < Self.maxAge {
            cached = SLSites.parse(data)
            if !cached.isEmpty { return cached }
        }
        do {
            return try await refresh()
        } catch {
            if let data = readCache() {
                cached = SLSites.parse(data)
                if !cached.isEmpty { return cached }
            }
            throw error
        }
    }

    @discardableResult
    public func refresh() async throws -> [Site] {
        let data = try await client.sites()
        let sites = SLSites.parse(data)
        guard !sites.isEmpty else { throw SLError.unreadable }
        writeCache(data)
        cached = sites
        return sites
    }

    // MARK: - Cache file

    /// Refuses anything that is not a plain regular file under the cap, so a
    /// symlink or an oversized file planted in the cache directory is a
    /// declined read rather than an unbounded one.
    private func readCache() -> Data? {
        let path = cacheURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, size <= SLClient.sitesCap, size > 0
        else { return nil }
        return try? Data(contentsOf: cacheURL, options: [.mappedIfSafe, .uncached])
    }

    private func cacheAge() -> TimeInterval? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return Date().timeIntervalSince(modified)
    }

    private func writeCache(_ data: Data) {
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}
