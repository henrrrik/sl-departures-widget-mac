import Foundation

/// SL's open "Transport" API. No account, no key, no rate-limit header — the
/// same two endpoints the Omarchy widget reads. There is a quota all the same,
/// answered with a bare 429; see `SLBackoff`.
///
///   https://transport.integration.sl.se/v1/sites?expand=false
///   https://transport.integration.sl.se/v1/sites/{id}/departures
///
/// Responses are Swedish-language and Europe/Stockholm-local throughout; see
/// `SLClock` for what that costs us.
public enum SLAPI {
    public static let base = URL(string: "https://transport.integration.sl.se/v1")!

    /// Server-side filters keep the payload small. `lines` and `walkMinutes`
    /// have no API equivalent and are applied client-side in `filterRows`.
    public static func departuresURL(for config: StopConfig) -> URL {
        var components = URLComponents(
            url: base.appendingPathComponent("sites/\(config.siteId)/departures"),
            resolvingAgainstBaseURL: false
        )!
        var query = [URLQueryItem(name: "forecast", value: String(config.forecastMinutes))]
        if !config.transport.isEmpty {
            query.append(URLQueryItem(name: "transport", value: config.transport))
        }
        if config.direction != 0 {
            query.append(URLQueryItem(name: "direction", value: String(config.direction)))
        }
        components.queryItems = query
        return components.url!
    }

    public static let sitesURL = URL(string: "https://transport.integration.sl.se/v1/sites?expand=false")!
}

// MARK: - Wire types

public struct Deviation: Codable, Hashable, Sendable {
    public var message: String?
    public var consequence: String?
    public var importanceLevel: Int?

    private enum CodingKeys: String, CodingKey {
        case message, consequence
        case importanceLevel = "importance_level"
    }
}

public struct Departure: Codable, Hashable, Sendable {
    public struct Line: Codable, Hashable, Sendable {
        public var designation: String?
        public var transportMode: String?
        private enum CodingKeys: String, CodingKey {
            case designation
            case transportMode = "transport_mode"
        }
    }

    public struct Journey: Codable, Hashable, Sendable {
        public var id: Int?
    }

    public struct StopPoint: Codable, Hashable, Sendable {
        /// The berth letter — the useful half of `stop_point`; its `name` just
        /// repeats the site you already asked for.
        public var designation: String?
    }

    public var destination: String?
    public var direction: String?
    public var directionCode: Int?
    public var state: String?
    /// SL's own relative rendering: "Nu", "4 min", or a clock time "23:45".
    public var display: String?
    /// Naive Europe/Stockholm wall-clock strings, e.g. "2026-08-31T22:11:00".
    public var scheduled: String?
    public var expected: String?
    public var line: Line?
    public var journey: Journey?
    public var stopPoint: StopPoint?
    public var deviations: [Deviation]?

    private enum CodingKeys: String, CodingKey {
        case destination, direction, state, display, scheduled, expected, line, journey, deviations
        case directionCode = "direction_code"
        case stopPoint = "stop_point"
    }
}

public struct StopDeviation: Codable, Hashable, Sendable {
    public var message: String?
    public var importanceLevel: Int?
    private enum CodingKeys: String, CodingKey {
        case message
        case importanceLevel = "importance_level"
    }
}

public struct DeparturesResponse: Codable, Hashable, Sendable {
    public var departures: [Departure]
    public var stopDeviations: [StopDeviation]

    private enum CodingKeys: String, CodingKey {
        case departures
        case stopDeviations = "stop_deviations"
    }

    public init(departures: [Departure] = [], stopDeviations: [StopDeviation] = []) {
        self.departures = departures
        self.stopDeviations = stopDeviations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        departures = try c.decode([Departure].self, forKey: .departures)
        stopDeviations = try c.decodeIfPresent([StopDeviation].self, forKey: .stopDeviations) ?? []
    }
}

public struct RawSite: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String?
    public var note: String?
}

// MARK: - Client

public enum SLError: Error, LocalizedError, Equatable {
    case unreachable(String)
    case httpStatus(Int)
    case rateLimited
    case tooLarge
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .unreachable: t("No response from SL")
        case .httpStatus(let code): t("SL replied \(code)")
        case .rateLimited: t("SL rate limit reached")
        case .tooLarge: t("SL response larger than expected, refusing")
        case .unreadable: t("Unreadable response from SL")
        }
    }
}

/// Bounded reads of the two endpoints. Both the timeout and the byte cap are
/// carried over from the shell widget: a stalled or runaway response must not
/// be able to hang a status item or fill memory in a widget extension.
public struct SLClient: Sendable {
    public static let departuresCap = 4 * 1024 * 1024
    public static let sitesCap = 8 * 1024 * 1024

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config)
        }
    }

    public func departures(for config: StopConfig) async throws -> DeparturesResponse {
        let data = try await load(SLAPI.departuresURL(for: config), timeout: 15, cap: Self.departuresCap)
        guard let decoded = try? JSONDecoder().decode(DeparturesResponse.self, from: data) else {
            throw SLError.unreadable
        }
        return decoded
    }

    public func sites() async throws -> Data {
        try await load(SLAPI.sitesURL, timeout: 30, cap: Self.sitesCap)
    }

    /// Accumulates bounded chunks, including responses without Content-Length.
    private func load(_ url: URL, timeout: TimeInterval, cap: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let receiver = BoundedRequest(cap: cap)
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    receiver.start(session: session, request: request, continuation: continuation)
                }
            } onCancel: {
                receiver.cancel()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SLError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SLError.unreachable(error.localizedDescription)
        }
    }
}

/// Delegate callbacks and task cancellation can run on different queues.
/// All mutable state is protected by the lock; completion resumes exactly once.
private final class BoundedRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let cap: Int
    private let lock = NSLock()
    private var data = Data()
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<Data, any Error>?
    private var failure: SLError?
    private var cancelled = false

    init(cap: Int) { self.cap = cap }

    func start(session: URLSession, request: URLRequest,
               continuation: CheckedContinuation<Data, any Error>) {
        lock.withLock {
            guard !cancelled else {
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            let task = session.dataTask(with: request)
            task.delegate = self
            self.task = task
            task.resume()
        }
    }

    func cancel() {
        let task = lock.withLock {
            cancelled = true
            return self.task
        }
        task?.cancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let disposition: URLSession.ResponseDisposition = lock.withLock {
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                failure = .rateLimited
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                failure = .httpStatus(http.statusCode)
            } else if response.expectedContentLength > Int64(cap) {
                failure = .tooLarge
            }
            return failure == nil && !cancelled ? .allow : .cancel
        }
        completionHandler(disposition)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let shouldCancel = lock.withLock {
            guard failure == nil, !cancelled else { return true }
            guard chunk.count <= cap - data.count else {
                failure = .tooLarge
                return true
            }
            data.append(chunk)
            return false
        }
        if shouldCancel { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let completion = lock.withLock { () -> (CheckedContinuation<Data, any Error>?, Result<Data, any Error>) in
            let result: Result<Data, any Error>
            if cancelled { result = .failure(CancellationError()) }
            else if let failure { result = .failure(failure) }
            else if let error { result = .failure(error) }
            else { result = .success(data) }
            let continuation = self.continuation
            self.continuation = nil
            self.task = nil
            data = Data()
            return (continuation, result)
        }
        completion.0?.resume(with: completion.1)
    }
}
