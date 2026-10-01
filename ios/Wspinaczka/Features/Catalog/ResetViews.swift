import BoulderKit
import SwiftUI

/// "Przykrętka jutro · 3 niezrobione" on a sector card.
struct ResetBadge: View {
    let reset: UpcomingReset

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(reset.daysLeft <= 2 ? .orange : .secondary)
    }

    private var text: String {
        var parts = ["Przykrętka \(Self.relative(reset.daysLeft, date: reset.date))"]
        if reset.activeProblems > 0 {
            parts.append(reset.notTopped == 0 ? "wszystko zrobione" : "\(reset.notTopped) niezrobionych")
        }
        return parts.joined(separator: " · ")
    }

    static func relative(_ daysLeft: Int, date: LocalDate) -> String {
        switch daysLeft {
        case 0: "dziś"
        case 1: "jutro"
        case 2: "pojutrze"
        default: "za \(daysLeft) dni (\(dayText(date)))"
        }
    }

    static func dayText(_ date: LocalDate) -> String {
        date.date(in: .current).formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Top of the gym screen: what is about to disappear.
struct UpcomingResetsBanner: View {
    let resets: [UpcomingReset]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Wkrótce przykrętki", systemImage: "calendar.badge.exclamationmark")
                .font(.headline)
            ForEach(resets) { reset in
                HStack {
                    Text(reset.sector.name).fontWeight(.medium)
                    Spacer()
                    Text(ResetBadge.relative(reset.daysLeft, date: reset.date))
                        .foregroundStyle(reset.daysLeft <= 2 ? .orange : .secondary)
                    if reset.notTopped > 0 {
                        Text("· \(reset.notTopped) do zrobienia")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

/// Staff: pick or clear the announced reset date of a sector.
struct NextResetSheet: View {
    let sector: Sector
    let timeZone: TimeZone
    /// Returns true when saved.
    let save: (LocalDate?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var isSaving = false

    init(sector: Sector, timeZone: TimeZone, save: @escaping (LocalDate?) async -> Bool) {
        self.sector = sector
        self.timeZone = timeZone
        self.save = save
        let initial = sector.nextResetOn ?? ClimbingDay.today(in: timeZone).adding(days: 7)
        _date = State(initialValue: initial.date(in: timeZone))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Przykrętka",
                        selection: $date,
                        in: ClimbingDay.today(in: timeZone).date(in: timeZone)...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                } footer: {
                    Text("Wspinacze zobaczą datę przy sektorze i liczbę swoich niezrobionych problemów.")
                }
                if sector.nextResetOn != nil {
                    Button("Usuń zapowiedź", role: .destructive) { submit(nil) }
                }
            }
            .navigationTitle(sector.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") { submit(LocalDate(date, in: timeZone)) }
                        .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func submit(_ value: LocalDate?) {
        isSaving = true
        Task {
            let saved = await save(value)
            isSaving = false
            if saved { dismiss() }
        }
    }
}
