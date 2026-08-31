import AppIntents
import SLKit

/// A stop, as something the widget's edit sheet can search for.
///
/// The query is the whole reason the widget needs no App Group: the stop lives
/// in the widget's own configuration, chosen from a list the extension fetches
/// and caches for itself, so nothing has to be handed across from the app.
struct SiteEntity: AppEntity, Identifiable {
    let id: Int
    let name: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Stop", numericFormat: "\(placeholder: .int) stops"
    )
    static let defaultQuery = SiteQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(String(id))")
    }
}

struct SiteQuery: EntityStringQuery {
    private static let directory = SiteDirectory()

    func entities(for identifiers: [Int]) async throws -> [SiteEntity] {
        let sites = try await Self.directory.sites()
        return identifiers.compactMap { id in
            SLSites.find(sites, id: id).map { SiteEntity(id: $0.id, name: $0.label) }
        }
    }

    /// Search-as-you-type in the widget's edit sheet, with the same prefix-first
    /// ranking and diacritic folding the app's picker uses.
    func entities(matching string: String) async throws -> [SiteEntity] {
        let sites = try await Self.directory.sites()
        return SLSites.search(sites, query: string, limit: 12)
            .map { SiteEntity(id: $0.id, name: $0.label) }
    }

    func suggestedEntities() async throws -> [SiteEntity] {
        let sites = try await Self.directory.sites()
        // A handful of the stops most people mean, so the sheet is not empty
        // before a single character is typed.
        return [9001, 9192, 9117, 9189, 9302]
            .compactMap { SLSites.find(sites, id: $0) }
            .map { SiteEntity(id: $0.id, name: $0.label) }
    }
}
