import SwiftUI
import SLKit
import WidgetKit

@main
struct SLWidgetBundle: WidgetBundle {
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
        .configurationDisplayName("SL Departures")
        .description("Live departures for a Stockholm stop.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DeparturesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeparturesEntry

    private var visibleRows: [DepartureRow] {
        Array(entry.rows.prefix(family == .systemSmall ? 3 : 5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : 4) {
            header

            if entry.rows.isEmpty {
                Spacer()
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(visibleRows) { row in
                    DepartureLine(row: row, showDestination: family != .systemSmall)
                }
                Spacer(minLength: 0)
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(entry.siteName.isEmpty ? "SL Departures" : entry.siteName)
                .font(.caption.weight(.semibold))
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
            } else if let deviation = entry.stopDeviations.first, family != .systemSmall {
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
        if entry.isPlaceholder { return "Pick a stop in Edit Widget." }
        if let error = entry.error { return error }
        return "Nothing leaving soon."
    }
}

private struct DepartureLine: View {
    let row: DepartureRow
    let showDestination: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(row.line)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 22, alignment: .leading)
                .strikethrough(row.cancelled)

            if showDestination {
                Text(row.destination)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(row.cancelled)
            }

            Spacer(minLength: 4)

            Text(row.cancelled ? "–" : row.waitText)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(row.cancelled ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        }
    }
}
