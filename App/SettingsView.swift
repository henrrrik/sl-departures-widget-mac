import SwiftUI
import SLKit

/// Stops and their filters. The list on the left is the set of status items;
/// the form on the right is one entry of the settings file.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var search = SiteSearch()
    @State private var selection: StopConfig.ID?

    private var selectedStop: StopConfig? {
        settings.stops.first { $0.id == selection } ?? settings.stops.first
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(settings.stops) { stop in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stop.siteName.isEmpty ? String(localized: "No stop picked") : stop.siteName)
                        let summary = SLFormat.filterSummary(stop)
                        if !summary.isEmpty {
                            Text(summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(stop.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        let stop = StopConfig()
                        settings.add(stop)
                        selection = stop.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add a stop — each one gets its own menu bar item")

                    Button {
                        guard let stop = selectedStop, settings.stops.count > 1 else { return }
                        settings.remove(stop)
                        selection = settings.stops.first?.id
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(settings.stops.count <= 1)
                    .help("Remove this stop")

                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        } detail: {
            if let stop = selectedStop {
                StopEditor(
                    stop: Binding(
                        get: { settings.stops.first { $0.id == stop.id } ?? stop },
                        set: { settings.update($0) }
                    ),
                    search: search
                )
            } else {
                Text("No stops").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .task { await search.load() }
        .onAppear { if selection == nil { selection = settings.stops.first?.id } }
    }
}

private struct StopEditor: View {
    @Binding var stop: StopConfig
    @Bindable var search: SiteSearch

    private static let transports = ["", "BUS", "METRO", "TRAM", "TRAIN", "SHIP", "FERRY"]

    var body: some View {
        Form {
            Section("Stop") {
                StopPicker(stop: $stop, search: search)
            }

            Section("Filters") {
                Picker("Transport", selection: transportBinding) {
                    ForEach(Self.transports, id: \.self) { mode in
                        Text(mode.isEmpty ? String(localized: "All modes") : SLFormat.modeName(mode)).tag(mode)
                    }
                }
                Picker("Direction", selection: directionBinding) {
                    Text("Both").tag(0)
                    Text("1").tag(1)
                    Text("2").tag(2)
                }
                .pickerStyle(.segmented)

                TextField("Lines", text: linesBinding, prompt: Text("All lines, or e.g. 13, 14"))

                LabeledContent("Walk") {
                    Stepper(
                        stop.walkMinutes == 0
                            ? String(localized: "No head start")
                            : String(localized: "\(stop.walkMinutes) min"),
                        value: intBinding(\.walkMinutes, range: 0...120)
                    )
                }
                Text("Hides departures leaving sooner than your walk, so the board only shows what you could still catch.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Display") {
                LabeledContent("In the menu bar") {
                    Stepper(String(localized: "\(stop.barCount) departures"), value: intBinding(\.barCount, range: 1...6))
                }
                LabeledContent("In the popup") {
                    Stepper(String(localized: "\(stop.panelCount) departures"), value: intBinding(\.panelCount, range: 1...40))
                }
                TextField("Menu bar format", text: formatBinding)
                Text("Tokens: {line} {wait} {min} {clock} {display} {destination}")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show the mode icon", isOn: boolBinding(\.showIcon))
            }

            Section("Fetching") {
                LabeledContent("Look ahead") {
                    Stepper(String(localized: "\(stop.forecastMinutes) min"), value: intBinding(\.forecastMinutes, range: 10...360, step: 10))
                }
                LabeledContent("Refresh every") {
                    Stepper(String(localized: "\(stop.refreshIntervalSec) s"), value: intBinding(\.refreshIntervalSec, range: 15...600, step: 5))
                }
                Text("Stops sharing a site and filters share one request, however many menu bar items show them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // Every edit goes back through StopConfig's initializer, so the bounds are
    // applied in one place no matter which control moved.
    private func intBinding(
        _ path: WritableKeyPath<StopConfig, Int>, range: ClosedRange<Int>, step: Int = 1
    ) -> Binding<Int> {
        Binding(
            get: { stop[keyPath: path] },
            set: { value in
                var updated = stop
                updated[keyPath: path] = value
                stop = StopConfig(rebuilding: updated)
            }
        )
    }

    private func boolBinding(_ path: WritableKeyPath<StopConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { stop[keyPath: path] },
            set: { value in
                var updated = stop
                updated[keyPath: path] = value
                stop = updated
            }
        )
    }

    private var transportBinding: Binding<String> {
        Binding(get: { stop.transport }, set: { stop = StopConfig(rebuilding: stop, transport: $0) })
    }

    private var directionBinding: Binding<Int> {
        Binding(get: { stop.direction }, set: { stop = StopConfig(rebuilding: stop, direction: $0) })
    }

    private var linesBinding: Binding<String> {
        Binding(
            get: { stop.linesText },
            set: { stop = StopConfig(rebuilding: stop, lines: StopConfig.parseLineFilter($0)) }
        )
    }

    private var formatBinding: Binding<String> {
        Binding(get: { stop.barFormat }, set: { stop = StopConfig(rebuilding: stop, barFormat: $0) })
    }
}

/// Search-as-you-type over the whole SL stop list, so a stop id never has to be
/// looked up by hand.
private struct StopPicker: View {
    @Binding var stop: StopConfig
    @Bindable var search: SiteSearch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search stops", text: $search.query, prompt: Text("Slussen, T-Centralen, …"))
                    .textFieldStyle(.plain)
                if search.isLoading { ProgressView().controlSize(.small) }
            }

            if let error = search.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            if !search.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(search.results) { site in
                        Button {
                            stop = StopConfig(rebuilding: stop, siteId: site.id, siteName: site.name)
                            search.query = ""
                        } label: {
                            HStack {
                                Text(site.label)
                                Spacer()
                                Text(String(site.id))
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }

            if stop.isConfigured {
                LabeledContent("Showing") {
                    Text("\(stop.siteName) · id \(String(stop.siteId))").foregroundStyle(.secondary)
                }
            }
        }
    }
}
