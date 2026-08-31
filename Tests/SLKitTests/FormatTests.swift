import Foundation
import Testing
@testable import SLKit

@Suite("Formatting")
struct FormatTests {
    func row(line: String = "13", minutes: Int?, destination: String = "Norsborg") -> DepartureRow {
        DepartureRow(
            id: "\(line)-\(minutes ?? -1)", line: line, mode: "METRO",
            symbol: SLFormat.symbol(for: "METRO"), destination: destination, direction: 1,
            minutes: minutes, clock: "22:11", display: "\(minutes ?? 0) min",
            atStop: false, cancelled: false, berth: "1", deviationText: "", deviationLevel: 0
        )
    }

    @Test("A wait reads three ways, and 'now' rather than zero")
    func rendersWaits() {
        #expect(SLFormat.minutesText(nil) == "?")
        #expect(SLFormat.minutesText(0) == "now")
        #expect(SLFormat.minutesText(7) == "7")
        #expect(SLFormat.waitText(0) == "now")
        #expect(SLFormat.waitText(7) == "7′")
        #expect(SLFormat.waitLabel(0) == "now")
        #expect(SLFormat.waitLabel(7) == "7 min")
    }

    @Test("barFormat tokens resolve against the row")
    func substitutesTokens() {
        let sample = row(minutes: 4)
        #expect(SLFormat.segment("{line} {wait}", row: sample) == "13 4′")
        #expect(SLFormat.segment("{line} to {destination} at {clock}", row: sample) == "13 to Norsborg at 22:11")
        #expect(SLFormat.segment("{min}m", row: sample) == "4m")
        #expect(SLFormat.segment("in {display}", row: sample) == "in 4 min")
    }

    @Test("A field containing a token is not substituted a second time")
    func substitutesInOnePass() {
        // The destination is API-derived text. A chain of replacements would
        // reach back into what an earlier replacement had already produced.
        let sneaky = row(minutes: 4, destination: "{wait} {line}")
        #expect(SLFormat.segment("{destination}", row: sneaky) == "{wait} {line}")
        #expect(SLFormat.segment("{destination} in {wait}", row: sneaky) == "{wait} {line} in 4′")
    }

    @Test("Replacement text is taken literally, dollars and all")
    func treatsReplacementsLiterally() {
        let dollars = row(minutes: 4, destination: "$& $$ $1")
        #expect(SLFormat.segment("{destination}", row: dollars) == "$& $$ $1")
    }

    @Test("An unknown or unclosed token stays on screen as written")
    func leavesUnknownTokensVisible() {
        let sample = row(minutes: 4)
        #expect(SLFormat.segment("{line} {nope}", row: sample) == "13 {nope}")
        #expect(SLFormat.segment("{line} {unclosed", row: sample) == "13 {unclosed")
        #expect(SLFormat.segment("no tokens", row: sample) == "no tokens")
        #expect(SLFormat.segment("{icon}{line}", row: sample) == "13", "the icon is drawn, not spelled")
    }

    @Test("The bar label joins the segments and names a symbol for the soonest departure")
    func buildsBarLabel() {
        let config = StopConfig(siteId: 9192, barCount: 2)
        let rows = [row(line: "18", minutes: 3), row(line: "19", minutes: 7)]

        let label = SLFormat.barLabel(rows, config: config)
        #expect(label.text == "18 3′ · 19 7′")
        #expect(label.symbol == "tram.fill.tunnel")

        let bare = SLFormat.barLabel(rows, config: StopConfig(siteId: 9192, showIcon: false))
        #expect(bare.symbol == nil)
    }

    @Test("Every empty state says which one it is")
    func labelsEmptyStates() {
        let config = StopConfig(siteId: 9192)
        #expect(SLFormat.barLabel([], config: StopConfig()).text == "SL", "no stop picked yet")
        #expect(SLFormat.barLabel([], config: config, state: .loading).text == "SL …")
        #expect(SLFormat.barLabel([], config: config, state: .failed).text == "SL ✗")
        #expect(SLFormat.barLabel([], config: config, state: .ready).text == "–")

        // A failure with a board already on screen keeps the board.
        let rows = [row(line: "13", minutes: 2)]
        #expect(SLFormat.barLabel(rows, config: config, state: .failed).text == "13 2′")
    }

    @Test("The filter summary says what is being shown, not just where")
    func summarisesFilters() {
        #expect(SLFormat.filterSummary(StopConfig(siteId: 9192)) == "")
        let config = StopConfig(
            siteId: 9192, transport: "METRO", direction: 1,
            lines: ["13", "14"], walkMinutes: 5
        )
        #expect(SLFormat.filterSummary(config) == "Metro · Line 13, 14 · Direction 1 · 5 min walk")
        #expect(SLFormat.modeName("SHIP") == "Ship")
        #expect(SLFormat.modeName("SOMETHING_NEW") == "Something_new", "an unknown mode still reads as a word")
        #expect(SLFormat.symbol(for: "SOMETHING_NEW") == "clock")
    }

    @Test("Swedish reaches the words SLKit renders itself")
    func swedishCatalog() {
        let sv = Locale(identifier: "sv")
        #expect(localized("now", in: sv) == "nu")
        #expect(localized("Bus", in: sv) == "Buss")
        #expect(localized("Line \("13, 14")", in: sv) == "Linje 13, 14")
        #expect(localized("\(5) min walk", in: sv) == "5 min gångväg")
        // English is the default, so the model says the same thing wherever
        // `swift test` runs.
        #expect(SLFormat.waitLabel(0) == "now")
    }
}
