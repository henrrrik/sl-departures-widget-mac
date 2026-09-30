import Foundation
import Synchronization
import Testing
@testable import SLKit

/// Each session supplies its own script ID, so tests can run concurrently.
private final class Script: Sendable {
    struct State {
        var requests = 0
        var sentBytes = 0
        var stopped = false
        var stopWaiters: [CheckedContinuation<Void, Never>] = []
    }
    func waitForStop() async {
        await withCheckedContinuation { continuation in
            let alreadyStopped = state.withLock { state in
                if state.stopped { return true }
                state.stopWaiters.append(continuation)
                return false
            }
            if alreadyStopped { continuation.resume() }
        }
    }
    func stop() {
        let waiters = state.withLock { state in
            state.stopped = true
            let waiters = state.stopWaiters
            state.stopWaiters = []
            return waiters
        }
        for waiter in waiters { waiter.resume() }
    }
    let state = Mutex(State())
    let status: Int
    let body: Data
    let declaredLength: Int?
    let repeats: Int
    init(status: Int = 200, body: Data = Data(), declaredLength: Int? = nil, repeats: Int = 1) {
        self.status = status
        self.body = body
        self.declaredLength = declaredLength
        self.repeats = repeats
    }
}

private final class ScriptProtocol: URLProtocol, @unchecked Sendable {
    static let scripts = Mutex<[String: Script]>([:])
    private var script: Script? {
        guard let id = request.value(forHTTPHeaderField: "X-Test-Script") else { return nil }
        return Self.scripts.withLock { $0[id] }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let script else { return }
        script.state.withLock { $0.requests += 1 }
        let headers = script.declaredLength.map { ["Content-Length": String($0)] }
        let response = HTTPURLResponse(url: request.url!, statusCode: script.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        send(script, remaining: script.repeats)
    }
    private func send(_ script: Script, remaining: Int) {
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(5)) { [self] in
            guard !script.state.withLock({ $0.stopped }) else { return }
            guard remaining > 0 else {
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            script.state.withLock { $0.sentBytes += script.body.count }
            client?.urlProtocol(self, didLoad: script.body)
            send(script, remaining: remaining - 1)
        }
    }
    override func stopLoading() { script?.stop() }
}

private func withClient<T: Sendable>(_ script: Script, operation: (SLClient) async throws -> T) async rethrows -> T {
    let id = UUID().uuidString
    ScriptProtocol.scripts.withLock { $0[id] = script }
    defer { _ = ScriptProtocol.scripts.withLock { $0.removeValue(forKey: id) } }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ScriptProtocol.self]
    configuration.httpAdditionalHeaders = ["X-Test-Script": id]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    return try await operation(SLClient(session: session))
}

struct ClientTests {
    @Test(arguments: [#"{}"#, #"{"departures":null}"#, #"{"departures":"bad"}"#,
                      #"{"departures":[{"destination":"Valid"},{"direction_code":"bad"}]}"#])
    func malformedPayloadPreservesBoard(json: String) async {
        await withClient(Script(body: Data(json.utf8))) { client in
            let previous = DepartureSnapshot(departures: [departure(line: "13")])
            let outcome = await BoardLoader(client: client).load(config: StopConfig(siteId: 9192), previous: previous)
            #expect(outcome.state == .failed)
            #expect(outcome.error == SLError.unreadable.errorDescription)
            #expect(outcome.snapshot.departures == previous.departures)
        }
    }

    @Test func emptyBoardIsValid() async throws {
        try await withClient(Script(body: Data(#"{"departures":[]}"#.utf8))) { client in
            let response = try await client.departures(for: StopConfig(siteId: 9192))
            #expect(response.departures.isEmpty)
        }
    }

    @Test(.timeLimit(.minutes(1))) func oversizedDeclaredResponseIsRejectedEarly() async {
        let script = Script(body: Data(repeating: 0, count: 1024), declaredLength: SLClient.sitesCap + 1, repeats: 100)
        await withClient(script) { client in
            await #expect(throws: SLError.tooLarge) { try await client.sites() }
            await script.waitForStop()
            #expect(script.state.withLock { $0.sentBytes } < script.body.count * script.repeats)
            #expect(script.state.withLock { $0.stopped })
        }
    }

    @Test(.timeLimit(.minutes(1))) func unknownLengthResponseStopsBeforeWholeBodyIsBuffered() async {
        let chunkSize = 256 * 1024
        let script = Script(body: Data(repeating: 0, count: chunkSize), repeats: 256)
        await withClient(script) { client in
            await #expect(throws: SLError.tooLarge) { try await client.sites() }
            await script.waitForStop()
            let sent = script.state.withLock { $0.sentBytes }
            #expect(sent > SLClient.sitesCap)
            #expect(sent < chunkSize * script.repeats)
            #expect(script.state.withLock { $0.stopped })
        }
    }

    @Test func callerCancellationIsNotReportedAsOversize() async throws {
        let script = Script(body: Data(repeating: 0, count: 1), repeats: 10_000)
        try await withClient(script) { client in
            let request = Task { try await client.sites() }
            try await Task.sleep(for: .milliseconds(25))
            request.cancel()
            await #expect(throws: CancellationError.self) { try await request.value }
        }
    }

    @Test func widgetCooldownSurvivesNewLoaderAndExpires() async {
        let suite = "WidgetCooldownTest.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        await withClient(Script(status: 429)) { limitedClient in
            let loader = WidgetBoardLoader(loader: BoardLoader(client: limitedClient), defaultsSuiteName: suite, now: { date })
            let result = await loader.load(config: StopConfig(siteId: 9192))
            #expect(result.outcome.rateLimited)
            #expect(result.retryAt == date.addingTimeInterval(SLBackoff.cap))
        }
        let script = Script(body: Data(#"{"departures":[]}"#.utf8))
        await withClient(script) { client in
            let loader = WidgetBoardLoader(loader: BoardLoader(client: client), defaultsSuiteName: suite, now: { date.addingTimeInterval(30) })
            for id in [9192, 9189] {
                let blocked = await loader.load(config: StopConfig(siteId: id))
                #expect(blocked.outcome.rateLimited)
                #expect(blocked.retryAt == date.addingTimeInterval(SLBackoff.cap))
            }
            #expect(script.state.withLock { $0.requests } == 0)
            let later = WidgetBoardLoader(loader: BoardLoader(client: client), defaultsSuiteName: suite, now: { date.addingTimeInterval(SLBackoff.cap) })
            let result = await later.load(config: StopConfig(siteId: 9192))
            #expect(result.outcome.error == nil)
            #expect(result.retryAt == nil)
            #expect(script.state.withLock { $0.requests } == 1)
        }
    }
}
