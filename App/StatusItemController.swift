import AppKit
import Observation
import SwiftUI
import SLKit

/// One stop's menu bar item, and the popover behind it.
@MainActor
final class StatusItemController {
    private(set) var config: StopConfig
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let openSettings: () -> Void
    private var stream: StopStream
    private var observing = true
    private var dismissMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(config: StopConfig, openSettings: @escaping () -> Void) {
        self.config = config
        self.openSettings = openSettings
        self.stream = DepartureHub.shared.stream(for: config)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Dismissal is ours rather than AppKit's. A `.transient` popover
        // closes itself on any click outside the button's *bounds* — but the
        // menu bar is a couple of points taller than the button, so a click in
        // that top strip both closed the popover and fired this button's
        // action, which reopened what the same click had just put away. Owning
        // the dismissal makes one click one toggle wherever in the item it
        // lands; `watchForDismissal` is the rest of what `.transient` did.
        popover.behavior = .applicationDefined
        popover.animates = false

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(handleClick)
            // Right click refreshes and middle click opens the picker, the way
            // the Omarchy widget's bar button did.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
        }
        render()
        observe()
    }

    func update(config: StopConfig) {
        let wasKey = DepartureHub.key(for: self.config)
        let previous = self.config
        self.config = config

        if DepartureHub.key(for: config) != wasKey {
            DepartureHub.shared.release(previous)
            stream = DepartureHub.shared.stream(for: config)
            observe()
        }
        render()
    }

    func tearDown() {
        observing = false
        closePopover()
        DepartureHub.shared.release(config)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Rendering

    private func render() {
        guard let button = statusItem.button else { return }
        let rows = SLRows.barRows(stream.rows(for: config), config: config)
        let label = SLFormat.barLabel(rows, config: config, state: stream.state)

        // Monospaced digits, so a countdown ticking from 10 to 9 does not
        // reflow every item to its right.
        button.attributedTitle = NSAttributedString(
            string: label.text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            ]
        )
        if let symbol = label.symbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
        } else {
            button.image = nil
        }
        button.toolTip = tooltip(rows: rows)
    }

    private func tooltip(rows: [DepartureRow]) -> String {
        guard config.isConfigured else { return String(localized: "SL Departures — click to pick a stop") }
        let name = config.siteName.isEmpty ? "SL" : config.siteName
        guard !rows.isEmpty else { return String(localized: "\(name) — no departures") }
        let lines = rows.prefix(5).map { "\($0.line)  \($0.destination)  \($0.waitLabel)" }
        return ([name] + lines).joined(separator: "\n")
    }

    private func observe() {
        withObservationTracking {
            _ = stream.tick
            _ = stream.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observing else { return }
                self.render()
                self.observe()
            }
        }
    }

    // MARK: - Clicks

    @objc private func handleClick() {
        switch NSApp.currentEvent?.type {
        case .rightMouseUp:
            stream.refreshNow()
        case .otherMouseUp:
            openSettings()
        default:
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
            return
        }
        guard let button = statusItem.button else { return }
        popover.contentViewController = NSHostingController(
            rootView: BoardView(
                config: config,
                stream: stream,
                onRefresh: { [weak self] in self?.stream.refreshNow() },
                onOpenSettings: { [weak self] in
                    self?.closePopover()
                    self?.openSettings()
                },
                onClose: { [weak self] in self?.closePopover() }
            )
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // The popover has to be key for its keyboard shortcuts to reach it.
        popover.contentViewController?.view.window?.makeKey()
        watchForDismissal()
    }

    /// What `.transient` used to do for us, minus the part that fought the
    /// button: a click in another app, or the app losing focus, puts the board
    /// away. A global monitor never sees this app's own clicks, so the status
    /// item stays free to toggle.
    private func watchForDismissal() {
        endDismissalWatch()
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
    }

    private func closePopover() {
        endDismissalWatch()
        if popover.isShown { popover.performClose(nil) }
    }

    private func endDismissalWatch() {
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        dismissMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }
}
