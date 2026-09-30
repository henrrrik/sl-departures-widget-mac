import Foundation
import Testing
import SLKit
@testable import AppSupport

@MainActor
struct SettingsAndPollingTests {
    @Test func invalidEditsPreserveStopsAndCannotBeOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        let initial = StopConfig(siteId: 9192, siteName: "Slussen")
        try JSONEncoder().encode([initial]).write(to: url)
        let store = SettingsStore(fileURL: url)
        let broken = Data("{\"stops\":".utf8)
        try broken.write(to: url)
        store.reloadIfChanged()
        #expect(store.stops == [initial])
        #expect(store.loadError != nil)
        store.update(StopConfig(rebuilding: initial, siteId: 9189))
        store.save()
        #expect(try Data(contentsOf: url) == broken)
        #expect(store.stops == [initial])

        let repaired = StopConfig(rebuilding: initial, siteId: 9189)
        try JSONEncoder().encode([repaired]).write(to: url, options: .atomic)
        store.reloadIfChanged()
        #expect(store.stops == [repaired])
        #expect(store.loadError == nil)

        try FileManager.default.removeItem(at: url)
        store.reloadIfChanged()
        #expect(store.stops == [repaired])
        #expect(store.loadError != nil)
    }

    @Test func firstLaunchAllowsSaving() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        #expect(store.loadError == nil)
        let stop = StopConfig(rebuilding: store.stops[0], siteId: 9192)
        store.update(stop)
        #expect(store.saveError == nil)
        store.reloadIfChanged()
        #expect(store.stops == [stop])
    }

    @Test func pollingTracksUpdatedAndRemovedSubscribers() {
        let hub = DepartureHub()
        let slow = StopConfig(refreshIntervalSec: 600)
        let fast = StopConfig(refreshIntervalSec: 30)
        let stream = hub.stream(for: slow)
        #expect(hub.stream(for: fast) === stream)
        defer { hub.release(slow); hub.release(fast) }
        #expect(stream.refreshIntervalSec == 30)
        stream.register(StopConfig(rebuilding: fast, refreshIntervalSec: 120))
        #expect(stream.refreshIntervalSec == 120)
        stream.register(StopConfig(rebuilding: fast, refreshIntervalSec: 15))
        #expect(stream.refreshIntervalSec == 15)
        hub.release(fast)
        #expect(stream.refreshIntervalSec == 600)
    }
}
