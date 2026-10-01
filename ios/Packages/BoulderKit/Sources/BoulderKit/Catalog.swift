import Foundation

/// Combinable filters for the catalog ("show me every 4 I have not done yet").
public struct ProblemFilter: Hashable, Sendable {
    /// Inclusive range of grade sort orders, nil = any grade.
    public var gradeOrders: ClosedRange<Int>?
    public var sectorIds: Set<UUID>
    public var colors: Set<HoldColor>
    public var onlyNotTopped: Bool
    /// Only problems set after this climbing day (e.g. the last visit).
    public var setAfter: LocalDate?

    public init(gradeOrders: ClosedRange<Int>? = nil, sectorIds: Set<UUID> = [],
                colors: Set<HoldColor> = [], onlyNotTopped: Bool = false, setAfter: LocalDate? = nil) {
        self.gradeOrders = gradeOrders
        self.sectorIds = sectorIds
        self.colors = colors
        self.onlyNotTopped = onlyNotTopped
        self.setAfter = setAfter
    }

    public var isEmpty: Bool { self == ProblemFilter() }

    public func matches(
        _ problem: ActiveProblem,
        grades: [UUID: Grade],
        toppedProblemIds: Set<UUID>,
        timeZone: TimeZone
    ) -> Bool {
        if let gradeOrders {
            guard let grade = grades[problem.gradeId], gradeOrders.contains(grade.sortOrder) else { return false }
        }
        if !sectorIds.isEmpty, !sectorIds.contains(problem.sectorId) { return false }
        if !colors.isEmpty, !colors.contains(problem.holdColor) { return false }
        if onlyNotTopped, toppedProblemIds.contains(problem.id) { return false }
        if let setAfter, ClimbingDay.localDate(for: problem.setAt, in: timeZone) <= setAfter { return false }
        return true
    }

    public func apply(
        to problems: [ActiveProblem],
        grades: [UUID: Grade],
        toppedProblemIds: Set<UUID>,
        timeZone: TimeZone
    ) -> [ActiveProblem] {
        problems.filter {
            matches($0, grades: grades, toppedProblemIds: toppedProblemIds, timeZone: timeZone)
        }
    }
}

/// "4: 7 z 12" — how many of the currently set problems of a grade I topped.
public struct GradeCoverage: Hashable, Sendable, Identifiable {
    public let grade: Grade
    public let active: Int
    public let topped: Int

    public var id: UUID { grade.id }
    public var fraction: Double { active == 0 ? 0 : Double(topped) / Double(active) }
}

public enum Coverage {
    public static func byGrade(
        problems: [ActiveProblem],
        grades: [Grade],
        toppedProblemIds: Set<UUID>
    ) -> [GradeCoverage] {
        let grouped = Dictionary(grouping: problems, by: \.gradeId)
        return grades
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { grade in
                guard let set = grouped[grade.id], !set.isEmpty else { return nil }
                let topped = set.filter { toppedProblemIds.contains($0.id) }.count
                return GradeCoverage(grade: grade, active: set.count, topped: topped)
            }
    }
}

public enum InviteCode {
    private static let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Same normalization as `private.normalize_invite_code`: case and
    /// separators are ignored, O/I/L read as 0/1/1.
    public static func normalize(_ raw: String) -> String {
        let mapped = raw.uppercased().compactMap { character -> Character? in
            switch character {
            case "O": "0"
            case "I", "L": "1"
            default: character.isLetter || character.isNumber ? character : nil
            }
        }
        return String(mapped)
    }

    /// True when the input can be a complete code (12 valid symbols).
    public static func isComplete(_ raw: String) -> Bool {
        let normalized = normalize(raw)
        return normalized.count == 12 && normalized.allSatisfy { alphabet.contains($0) }
    }

    /// XXXX-XXXX-XXXX for display.
    public static func formatted(_ raw: String) -> String {
        let normalized = Array(normalize(raw))
        return stride(from: 0, to: normalized.count, by: 4)
            .map { String(normalized[$0..<min($0 + 4, normalized.count)]) }
            .joined(separator: "-")
    }

    /// Extracts the code from `wspinaczka://invite?code=...`.
    public static func code(from url: URL) -> String? {
        guard url.scheme == "wspinaczka", url.host == "invite",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        return items.first { $0.name == "code" }?.value
    }

    public static func url(for code: String) -> URL {
        var components = URLComponents()
        components.scheme = "wspinaczka"
        components.host = "invite"
        components.queryItems = [URLQueryItem(name: "code", value: formatted(code))]
        return components.url!
    }
}
