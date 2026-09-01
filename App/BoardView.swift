import SwiftUI
import SLKit

/// The popup departure board: line, destination, berth, wait, cancellations,
/// and any service messages for the station.
struct BoardView: View {
    let config: StopConfig
    @Bindable var stream: StopStream
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void
    var onClose: () -> Void

    @FocusState private var focused: Bool
    @State private var scrollTarget: String?

    private var rows: [DepartureRow] {
        Array(stream.rows(for: config).prefix(config.panelCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if !config.isConfigured {
                emptyState(
                    "No stop picked yet",
                    detail: "Choose a stop to start showing departures.",
                    action: "Pick a stop…"
                )
            } else if rows.isEmpty {
                emptyState(
                    stream.state == .loading ? "Loading…" : "Nothing leaving",
                    detail: stream.state == .loading
                        ? "Asking SL for departures."
                        : "No departures in the next \(config.forecastMinutes) minutes match these filters.",
                    action: nil
                )
            } else {
                board
            }

            Divider()
            footer
        }
        .frame(width: 380)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress("r") { onRefresh(); return .handled }
        .onKeyPress("s") { onOpenSettings(); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress("j") { scroll(by: 1); return .handled }
        .onKeyPress("k") { scroll(by: -1); return .handled }
        .onKeyPress(.downArrow) { scroll(by: 1); return .handled }
        .onKeyPress(.upArrow) { scroll(by: -1); return .handled }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.siteName.isEmpty ? String(localized: "SL Departures") : config.siteName)
                    .font(.headline)
                let summary = SLFormat.filterSummary(config)
                if !summary.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh (r)")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Stops and settings (s)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Board

    private var board: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        DepartureRowView(row: row)
                            .id(row.id)
                        if row.id != rows.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    private func scroll(by delta: Int) {
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == scrollTarget } ?? 0
        let next = (current + delta).clamped(to: 0...(rows.count - 1))
        scrollTarget = rows[next].id
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(stream.snapshot.stopDeviations, id: \.self) { message in
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 6) {
                if let error = stream.error {
                    Image(systemName: "wifi.slash").foregroundStyle(.secondary)
                    Text(error)
                } else if stream.snapshot.fetchedAt.timeIntervalSince1970 > 0, !stream.snapshot.isEmpty {
                    Text("Updated \(stream.snapshot.fetchedAt, format: .dateTime.hour().minute())")
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// Taken as LocalizedStringKey rather than String: a literal that passes
    /// through a String parameter reaches Text already resolved, and Text draws
    /// it verbatim instead of looking it up.
    private func emptyState(
        _ title: LocalizedStringKey, detail: LocalizedStringKey, action: LocalizedStringKey?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).bold()
            Text(detail).font(.caption).foregroundStyle(.secondary)
            if let action {
                Button(action, action: onOpenSettings)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
}

private struct DepartureRowView: View {
    let row: DepartureRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: row.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(row.line)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 34, alignment: .leading)

                Text(row.destination)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(row.cancelled)

                Spacer(minLength: 8)

                if !row.berth.isEmpty {
                    Text(row.berth)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }

                Text(row.cancelled ? String(localized: "Cancelled") : row.waitLabel)
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(row.cancelled ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .frame(minWidth: 58, alignment: .trailing)
            }
            if !row.deviationText.isEmpty {
                Text(row.deviationText)
                    .font(.caption)
                    .foregroundStyle(row.deviationLevel >= 5 ? .orange : .secondary)
                    .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
