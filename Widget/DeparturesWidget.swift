import SwiftUI
import SLKit
import WidgetKit

@main
struct SLWidgetBundle: WidgetBundle {
    init() {
        // Same reason as the app: SLKit's own words follow the extension's
        // language, which is the one the tile is drawn in.
        SLLanguage.followSystem()
    }

    var body: some Widget {
        DeparturesWidget()
    }
}

struct DeparturesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: SLWidgetKind.departures,
            intent: DeparturesConfigurationIntent.self,
            provider: DeparturesProvider()
        ) { entry in
            DeparturesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        // Resolved here rather than handed over as LocalizedStringResource.
        // The gallery is drawn by another process, and a resource built from a
        // literal carries `bundle: .main` — which, over there, means *that*
        // process's bundle, where these keys are not found and the English key
        // itself is what gets drawn. Looking them up in the extension, whose
        // main bundle is the appex, is what puts Swedish in the gallery.
        .configurationDisplayName(String(localized: "SL Departures"))
        .description(String(localized: "Live departures for a Stockholm stop."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DeparturesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeparturesEntry

    /// The only thing the small family changes: how many departures fit.
    /// Everything else — title, hairline, destinations, footer — is the same
    /// board, narrower.
    private var visibleRows: [DepartureRow] {
        Array(entry.rows.prefix(family == .systemSmall ? 3 : 5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 4)

            if entry.rows.isEmpty {
                Spacer()
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleRows) { row in
                        DepartureLine(row: row)
                    }
                }
                Spacer(minLength: 4)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Titled header over a hairline, the way the app's own board — and the
    /// rest of macOS — separates a title from the list it names.
    private var header: some View {
        HStack(spacing: 4) {
            Text(entry.siteName.isEmpty ? String(localized: "SL Departures") : entry.siteName)
                .font(.headline)
                .lineLimit(1)
                .widgetAccentable()
            Spacer(minLength: 2)
            Button(intent: RefreshDeparturesIntent()) {
                Image(systemName: "arrow.clockwise").font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if let error = entry.error {
                Image(systemName: "wifi.slash")
                Text(error).lineLimit(1)
            } else if let deviation = entry.stopDeviations.first {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(deviation).lineLimit(1)
            } else if let fetchedAt = entry.fetchedAt {
                Text("Updated \(fetchedAt, format: .dateTime.hour().minute())")
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }

    private var emptyMessage: String {
        if entry.isPlaceholder { return String(localized: "Pick a stop in Edit Widget.") }
        if let error = entry.error { return error }
        return String(localized: "Nothing leaving soon.")
    }
}

private struct DepartureLine: View {
    let row: DepartureRow

    var body: some View {
        HStack(spacing: 6) {
            Text(row.line)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 22, alignment: .leading)
                .strikethrough(row.cancelled)

            Text(row.destination)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(row.cancelled)

            Spacer(minLength: 4)

            Text(row.cancelled ? "–" : row.waitText)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(row.cancelled ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                // In the small family the row runs out of width first. The
                // destination is the part that may truncate; the wait is not.
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
    }
}
