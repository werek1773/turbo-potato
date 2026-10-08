import BoulderKit
import SwiftUI

/// A titled paper card for one block of statistics.
struct StatsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.display(.title3))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
    }
}

/// One big number with a caption ("12 · topy").
struct StatTile: View {
    let value: String
    let caption: String
    var pictogram: Pictogram.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let pictogram {
                    Pictogram(kind: pictogram, size: 22)
                }
                Text(value)
                    .font(.display(.title2).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 14, radius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(value)")
    }
}

/// A short empty-state line inside a card.
struct StatsEmptyNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Pictogram(kind: .chalkBag, size: 26)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Polish counted nouns used across the statistics screens.
enum Counted {
    static func tops(_ n: Int) -> String { PolishPlural.format(n, one: "top", few: "topy", many: "topów") }
    static func flashes(_ n: Int) -> String { PolishPlural.format(n, one: "flash", few: "flashe", many: "flashy") }
    static func projects(_ n: Int) -> String { PolishPlural.format(n, one: "projekt", few: "projekty", many: "projektów") }
    static func weeks(_ n: Int) -> String { PolishPlural.format(n, one: "tydzień", few: "tygodnie", many: "tygodni") }
    static func sessions(_ n: Int) -> String { PolishPlural.format(n, one: "sesja", few: "sesje", many: "sesji") }
    static func problems(_ n: Int) -> String { PolishPlural.format(n, one: "problem", few: "problemy", many: "problemów") }
    static func people(_ n: Int) -> String { PolishPlural.format(n, one: "osoba", few: "osoby", many: "osób") }
    static func newSends(_ n: Int) -> String {
        PolishPlural.format(n, one: "nowe przejście", few: "nowe przejścia", many: "nowych przejść")
    }
}

extension LocalDate {
    /// "8 października".
    func dayAndMonth(in timeZone: TimeZone) -> String {
        formatted(.dateTime.day().month(.wide), in: timeZone)
    }

    /// "8.10".
    func shortDay(in timeZone: TimeZone) -> String {
        formatted(.dateTime.day().month(.twoDigits), in: timeZone)
    }

    private func formatted(_ style: Date.FormatStyle, in timeZone: TimeZone) -> String {
        var style = style
        style.timeZone = timeZone
        style.locale = .app
        return date(in: timeZone).formatted(style)
    }
}

extension Double {
    /// "64%".
    var percentText: String { formatted(.percent.precision(.fractionLength(0)).locale(.app)) }
}

extension Locale {
    /// The language the UI is written in (Polish; no translations yet), so
    /// dates and numbers do not switch to the phone's language mid-sentence.
    static let app = Locale(identifier: "pl_PL")
}
