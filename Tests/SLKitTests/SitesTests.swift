import Foundation
import Testing
@testable import SLKit

@Suite("Stop search")
struct SitesTests {
    @Test("The stop list parses into searchable sites")
    func parsesSites() throws {
        let sites = try Fixture.sites()
        #expect(sites.count >= 7)
        let slussen = try #require(SLSites.find(sites, id: 9192))
        #expect(slussen.name == "Slussen")
        #expect(slussen.label == "Slussen")

        let radmansgatan = try #require(SLSites.find(sites, name: "Rådmansgatan"))
        #expect(radmansgatan.label == "Rådmansgatan (Sveavägen)")
    }

    @Test("A malformed list is an empty result, not a crash")
    func survivesMalformedInput() {
        #expect(SLSites.parse(Data("not json".utf8)).isEmpty)
        #expect(SLSites.parse(Data(#"{"sites": []}"#.utf8)).isEmpty)
        #expect(SLSites.parse(Data("[]".utf8)).isEmpty)
        #expect(SLSites.parse(Data(#"[{"id": 1}]"#.utf8)).isEmpty, "a stop with no name is not searchable")
    }

    @Test("A prefix match outranks a mere substring")
    func ranksPrefixFirst() throws {
        let sites = try Fixture.sites()
        let hits = SLSites.search(sites, query: "slu")
        #expect(hits.first?.name == "Slussen", "the shortest prefix match leads")
        #expect(hits.map(\.name).contains("Slussen/Stadsgården"))
    }

    @Test("Diacritics fold, so a stop is reachable from the keyboard you have")
    func foldsDiacritics() throws {
        let sites = try Fixture.sites()
        #expect(SLSites.search(sites, query: "radmans").first?.name == "Rådmansgatan")
        #expect(SLSites.search(sites, query: "RÅDMANS").first?.name == "Rådmansgatan")
        #expect(SLSites.search(sites, query: "sodermalmstorg").first?.name == "Slussen/Södermalmstorg")
    }

    @Test("A note is searchable, but ranks below every name match")
    func searchesNotesLast() throws {
        let sites = try Fixture.sites()
        #expect(SLSites.search(sites, query: "sveavagen").first?.name == "Rådmansgatan",
                "the note is the only thing that matches")

        // A name match wins even when it is the longer, later-sorting name.
        let synthetic = [
            Site(id: 1, name: "Aaa Gatan", note: "Sveavägen"),
            Site(id: 2, name: "Norra Sveavägen")
        ]
        #expect(SLSites.search(synthetic, query: "sveavagen").map(\.id) == [2, 1])
    }

    @Test("An empty query matches nothing, and the limit is honoured")
    func boundsResults() throws {
        let sites = try Fixture.sites()
        #expect(SLSites.search(sites, query: "").isEmpty)
        #expect(SLSites.search(sites, query: "   ").isEmpty)
        #expect(SLSites.search(sites, query: "zzzzz").isEmpty)
        #expect(SLSites.search(sites, query: "s", limit: 2).count == 2)
    }

    @Test("A stale cache still answers when the download fails")
    func servesStaleCacheOnFailure() async throws {
        let cacheURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sl-sites-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        try Fixture.data("sites-sample").write(to: cacheURL)
        // Ten days old, so the directory tries to refresh before serving it.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-10 * 24 * 3600)],
            ofItemAtPath: cacheURL.path
        )

        // A client pointed at a session that refuses every request.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefusingProtocol.self]
        let directory = SiteDirectory(
            cacheURL: cacheURL,
            client: SLClient(session: URLSession(configuration: configuration))
        )

        let sites = try await directory.sites()
        #expect(SLSites.find(sites, id: 9192)?.name == "Slussen")
    }
}

/// Fails every request, so a test can exercise the offline path without one.
final class RefusingProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
