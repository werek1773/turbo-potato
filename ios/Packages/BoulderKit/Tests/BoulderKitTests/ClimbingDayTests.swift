import Foundation
import Testing
@testable import BoulderKit

@Suite("Climbing day")
struct ClimbingDayTests {
    let warsaw = TimeZone(identifier: "Europe/Warsaw")!

    func instant(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    @Test func eveningBelongsToTheSameDay() {
        #expect(ClimbingDay.localDate(for: instant("2026-10-01T19:30:00Z"), in: warsaw) == LocalDate("2026-10-01"))
    }

    @Test func lateNightBelongsToThePreviousDay() {
        // 01:30 local on 2 Oct is still the climbing day of 1 Oct.
        #expect(ClimbingDay.localDate(for: instant("2026-10-01T23:30:00Z"), in: warsaw) == LocalDate("2026-10-01"))
    }

    @Test func fourAmStartsTheNextDay() {
        // 04:00 local (CEST, UTC+2) on 2 Oct.
        #expect(ClimbingDay.localDate(for: instant("2026-10-02T02:00:00Z"), in: warsaw) == LocalDate("2026-10-02"))
    }

    @Test func localDateRoundTripsThroughJSON() throws {
        let date = LocalDate(year: 2026, month: 3, day: 9)
        let data = try JSONEncoder().encode(date)
        #expect(String(decoding: data, as: UTF8.self) == "\"2026-03-09\"")
        #expect(try JSONDecoder().decode(LocalDate.self, from: data) == date)
    }

    @Test func addingDaysCrossesMonths() {
        #expect(LocalDate("2026-10-01")!.adding(days: -1) == LocalDate("2026-09-30"))
        #expect(LocalDate("2026-12-31")!.adding(days: 1) == LocalDate("2027-01-01"))
    }
}
