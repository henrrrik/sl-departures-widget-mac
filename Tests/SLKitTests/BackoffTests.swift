import Foundation
import Testing
@testable import SLKit

@Suite("Backoff")
struct BackoffTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Starts at a minute and doubles on each consecutive 429")
    func doubles() {
        var backoff = SLBackoff()
        #expect(!backoff.isActive(at: Self.now))

        backoff.rateLimited(at: Self.now)
        #expect(backoff.wait == 60)
        #expect(backoff.isActive(at: Self.now.addingTimeInterval(59)))
        #expect(!backoff.isActive(at: Self.now.addingTimeInterval(60)))

        let later = Self.now.addingTimeInterval(60)
        backoff.rateLimited(at: later)
        #expect(backoff.wait == 120)
        #expect(backoff.remaining(at: later.addingTimeInterval(20)) == 100)
    }

    @Test("Caps at ten minutes")
    func caps() {
        var backoff = SLBackoff()
        var now = Self.now
        for _ in 0..<10 {
            backoff.rateLimited(at: now)
            now = backoff.until
        }
        #expect(backoff.wait == 600)
        #expect(backoff.message == "SL rate limit reached, retrying in 10 min")
    }

    @Test("A success clears it, so the next 429 starts over")
    func resets() {
        var backoff = SLBackoff()
        backoff.rateLimited(at: Self.now)
        backoff.rateLimited(at: backoff.until)
        backoff.succeeded()
        #expect(!backoff.isActive(at: Self.now))
        #expect(backoff.remaining(at: Self.now) == 0)

        backoff.rateLimited(at: Self.now)
        #expect(backoff.wait == 60)
    }

    @Test("429s from requests already in flight count as one trip")
    func concurrentTrips() {
        var backoff = SLBackoff()
        backoff.rateLimited(at: Self.now)
        backoff.rateLimited(at: Self.now.addingTimeInterval(1))
        backoff.rateLimited(at: Self.now.addingTimeInterval(2))
        #expect(backoff.wait == 60)
        #expect(backoff.until == Self.now.addingTimeInterval(60))
    }
}
