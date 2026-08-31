import Foundation
import Observation
import SLKit

/// The stop directory, held for the lifetime of the settings window.
///
/// Loading is deferred until something actually needs a name — the picker being
/// opened, or a config that names a stop without an id — so the app does not
/// download 6500 stops just to sit in the menu bar.
@MainActor
@Observable
final class SiteSearch {
    var query = "" {
        didSet { updateResults() }
    }
    private(set) var results: [Site] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    private let directory = SiteDirectory()
    private var sites: [Site] = []

    func load() async {
        guard sites.isEmpty, !isLoading else { return }
        isLoading = true
        loadError = nil
        do {
            sites = try await directory.sites()
        } catch {
            loadError = (error as? SLError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
        updateResults()
    }

    func refresh() async {
        isLoading = true
        loadError = nil
        do {
            sites = try await directory.refresh()
        } catch {
            loadError = (error as? SLError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
        updateResults()
    }

    func site(id: Int) -> Site? { SLSites.find(sites, id: id) }

    /// Resolves `"siteName": "Slussen"` with no id, so naming a stop is a
    /// working configuration on its own.
    func site(named name: String) -> Site? { SLSites.find(sites, name: name) }

    private func updateResults() {
        results = SLSites.search(sites, query: query, limit: 12)
    }
}
