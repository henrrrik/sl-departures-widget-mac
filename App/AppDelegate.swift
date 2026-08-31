import AppKit
import Observation
import SwiftUI
import SLKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private var controllers: [StopConfig.ID: StatusItemController] = [:]
    private var settingsWindow: NSWindow?

    private let directory = SiteDirectory()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The model renders words of its own — "now", the modes, the filter
        // summary — and they follow the language this UI is drawn in.
        SLLanguage.followSystem()
        syncStatusItems()
        observeSettings()
    }

    /// A stop named but not numbered — `"siteName": "Slussen"` with no
    /// `siteId` — is resolved to an id and written back, so naming a stop is a
    /// working configuration on its own. Only reached when such a stop exists,
    /// so the stop list is not downloaded just to sit in the menu bar.
    private func resolveNamedStops() async {
        let unresolved = settings.stops.filter { !$0.siteName.isEmpty && $0.siteId == 0 }
        guard !unresolved.isEmpty, let sites = try? await directory.sites() else { return }

        for stop in unresolved {
            guard let site = SLSites.find(sites, name: stop.siteName) else { continue }
            settings.update(StopConfig(rebuilding: stop, siteId: site.id, siteName: site.name))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for controller in controllers.values { controller.tearDown() }
    }

    // MARK: - Status items

    /// One status item per configured stop. Reconciled rather than rebuilt, so
    /// editing a setting does not make every menu bar item flicker away and
    /// come back.
    private func syncStatusItems() {
        let stops = settings.stops
        for stop in stops {
            if let controller = controllers[stop.id] {
                controller.update(config: stop)
            } else {
                controllers[stop.id] = StatusItemController(
                    config: stop,
                    openSettings: { [weak self] in self?.showSettings() }
                )
            }
        }
        let live = Set(stops.map(\.id))
        for (id, controller) in controllers where !live.contains(id) {
            controller.tearDown()
            controllers.removeValue(forKey: id)
        }
        // Here rather than only at launch, so a stop named by hand in the
        // settings file resolves whenever it is written, not just on restart.
        Task { await resolveNamedStops() }
    }

    /// Re-arms itself after every change, which is how `withObservationTracking`
    /// is meant to be used for a long-lived observer.
    private func observeSettings() {
        withObservationTracking {
            _ = settings.stops
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncStatusItems()
                self?.observeSettings()
            }
        }
    }

    // MARK: - Settings window

    func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "SL Departures")
        window.contentViewController = NSHostingController(rootView: SettingsView(settings: settings))
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
