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

    init(config: StopConfig, openSettings: @escaping () -> Void) {
        self.config = config
        self.openSettings = openSettings
        self.stream = DepartureHub.shared.stream(for: config)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.behavior = .transient
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
        guard config.isConfigured else { return "SL Departures — click to pick a stop" }
        let name = config.siteName.isEmpty ? "SL" : config.siteName
        guard !rows.isEmpty else { return "\(name) — no departures" }
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
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        popover.contentViewController = NSHostingController(
            rootView: BoardView(
                config: config,
                stream: stream,
                onRefresh: { [weak self] in self?.stream.refreshNow() },
                onOpenSettings: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.openSettings()
                },
                onClose: { [weak self] in self?.popover.performClose(nil) }
            )
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // The popover has to be key for its keyboard shortcuts to reach it.
        popover.contentViewController?.view.window?.makeKey()
    }
}
