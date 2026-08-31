import Foundation
import Observation
import ServiceManagement
import SLKit

/// The configured stops, in a JSON file meant to be opened and edited by hand.
///
/// The Omarchy widget kept its settings inline in `~/.config/omarchy/shell.json`;
/// this is the same idea in the place macOS keeps such things. A plain file
/// rather than UserDefaults because being able to read — and fix — the
/// configuration in a text editor is worth more here than defaults integration.
@MainActor
@Observable
final class SettingsStore {
    private(set) var stops: [StopConfig]

    private let fileURL: URL

    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? SettingsStore.defaultURL()
        self.stops = SettingsStore.read(from: self.fileURL)
        startWatching()
    }

    /// Picks up hand edits to the settings file without a restart — the point
    /// of keeping it a plain file at all.
    ///
    /// Two watches, because one kind of write is invisible to each: writing
    /// into the existing file never touches the directory, and replacing it
    /// atomically — which is what this app, `vim` and most editors do — leaves
    /// the file watch holding a descriptor on an inode nothing will write to
    /// again. So the directory catches the replacements and re-arms the file
    /// watch, and the file watch catches the writes in place.
    private func startWatching() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        directoryWatcher = watch(path: directory.path, events: [.write]) { [weak self] in
            self?.reloadIfChanged()
            self?.watchFile()
        }
        watchFile()
    }

    private func watchFile() {
        fileWatcher?.cancel()
        fileWatcher = watch(path: fileURL.path, events: [.write, .extend, .delete, .rename]) { [weak self] in
            self?.reloadIfChanged()
        }
    }

    private func watch(
        path: String,
        events: DispatchSource.FileSystemEvent,
        handler: @escaping @MainActor () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: .main
        )
        source.setEventHandler { MainActor.assumeIsolated { handler() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    /// Compares before assigning, so the app's own `save()` does not bounce
    /// back through the watcher and interrupt whatever is being edited.
    private func reloadIfChanged() {
        let onDisk = SettingsStore.read(from: fileURL)
        guard onDisk != stops else { return }
        stops = onDisk
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("io.github.henrrrik.sl-departures", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    var settingsPath: String { fileURL.path }

    // MARK: - Editing

    func add(_ stop: StopConfig) {
        stops.append(stop)
        save()
    }

    func update(_ stop: StopConfig) {
        guard let index = stops.firstIndex(where: { $0.id == stop.id }) else { return }
        stops[index] = stop
        save()
    }

    func remove(_ stop: StopConfig) {
        stops.removeAll { $0.id == stop.id }
        save()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(Document(stops: stops)) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Login item

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("SL Departures: could not change the login item: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - File

    private struct Document: Codable {
        var stops: [StopConfig]
    }

    /// A missing file is a first run, and a broken one is not worth losing the
    /// menu bar over: either way the app starts with a single unconfigured stop
    /// whose status item invites you to pick one.
    private static func read(from url: URL) -> [StopConfig] {
        guard let data = try? Data(contentsOf: url) else { return [StopConfig()] }
        if let document = try? JSONDecoder().decode(Document.self, from: data), !document.stops.isEmpty {
            return document.stops
        }
        // Also accept a bare array, which is what someone hand-writing the file
        // is most likely to produce.
        if let stops = try? JSONDecoder().decode([StopConfig].self, from: data), !stops.isEmpty {
            return stops
        }
        return [StopConfig()]
    }
}
