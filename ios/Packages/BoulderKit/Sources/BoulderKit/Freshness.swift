import Foundation

/// Whether a problem is worth a second look: set or changed since my last
/// visit (or, without one, within the last week).
public enum Freshness: Hashable, Sendable {
    case new
    case changed(ChangeKind, at: Date)

    /// Without a visit to compare with, a mark lasts this long.
    public static let window: TimeInterval = 7 * 24 * 3600

    public static func of(_ problem: ActiveProblem, lastVisit: LocalDate?, now: Date,
                          timeZone: TimeZone) -> Freshness? {
        func isRecent(_ date: Date) -> Bool {
            if let lastVisit {
                return ClimbingDay.localDate(for: date, in: timeZone) > lastVisit
            }
            return now.timeIntervalSince(date) < window
        }
        if isRecent(problem.setAt) { return .new }
        if let changedAt = problem.changedAt, let kind = problem.changeKind, isRecent(changedAt) {
            return .changed(kind, at: changedAt)
        }
        return nil
    }

    /// Changed after the day I topped it: what I did may not be the problem
    /// that is on the wall now.
    public static func changedSince(_ problem: ActiveProblem, toppedOn day: LocalDate, timeZone: TimeZone) -> Bool {
        guard let changedAt = problem.changedAt else { return false }
        return ClimbingDay.localDate(for: changedAt, in: timeZone) > day
    }
}
