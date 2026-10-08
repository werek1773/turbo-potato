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

    /// How many kinds of filter are on (grade, sector, colour, not done,
    /// new): the badge on the filter button. Three colours count as one.
    public var activeCount: Int {
        [gradeOrders != nil, !sectorIds.isEmpty, !colors.isEmpty, onlyNotTopped, setAfter != nil]
            .filter { $0 }.count
    }

    /// Back to every problem.
    public mutating func reset() {
        self = ProblemFilter()
    }

    public mutating func toggle(_ color: HoldColor) {
        if colors.contains(color) { colors.remove(color) } else { colors.insert(color) }
    }

    public mutating func toggleSector(_ id: UUID) {
        if sectorIds.contains(id) { sectorIds.remove(id) } else { sectorIds.insert(id) }
    }

    /// What the coverage counter counts: the filter without "not done by me",
    /// which would always leave 0 done.
    public var coverageScope: ProblemFilter {
        var scope = self
        scope.onlyNotTopped = false
        return scope
    }

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

/// "7 z 12": active problems and how many of them I topped.
public struct CoverageCount: Hashable, Sendable {
    public let active: Int
    public let topped: Int

    public init(active: Int, topped: Int) {
        self.active = active
        self.topped = topped
    }
}

public enum Coverage {
    /// The coverage counter under the filters ("4: 7 z 12 aktywnych"): the
    /// problems the filter shows, ignoring "not done by me".
    public static func count(
        problems: [ActiveProblem],
        grades: [UUID: Grade],
        toppedProblemIds: Set<UUID>,
        filter: ProblemFilter,
        timeZone: TimeZone
    ) -> CoverageCount {
        let shown = filter.coverageScope.apply(to: problems, grades: grades,
                                               toppedProblemIds: toppedProblemIds, timeZone: timeZone)
        return CoverageCount(active: shown.count, topped: shown.filter { toppedProblemIds.contains($0.id) }.count)
    }

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

/// Sectors of one area (room), in walking order.
public struct SectorArea: Hashable, Sendable, Identifiable {
    public let name: String?
    public let sectors: [Sector]

    public var id: String { name ?? "" }
}

extension Sector {
    /// Groups sectors by area keeping the walking order: areas appear in the
    /// order of their first sector, sectors in `sortOrder` within an area.
    public static func groupedByArea(_ sectors: [Sector]) -> [SectorArea] {
        let ordered = sectors.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        var areas: [SectorArea] = []
        var index: [String: Int] = [:]
        var buckets: [[Sector]] = []
        for sector in ordered {
            let key = sector.area ?? ""
            if let position = index[key] {
                buckets[position].append(sector)
            } else {
                index[key] = buckets.count
                buckets.append([sector])
            }
        }
        for bucket in buckets {
            areas.append(SectorArea(name: bucket[0].area, sectors: bucket))
        }
        return areas
    }
}

/// An announced reset coming up soon, with what I still have to do there.
public struct UpcomingReset: Hashable, Sendable, Identifiable {
    public let sector: Sector
    public let date: LocalDate
    /// 0 = today, 1 = tomorrow.
    public let daysLeft: Int
    public let activeProblems: Int
    public let notTopped: Int

    public var id: UUID { sector.id }
}

public enum Resets {
    public static func upcoming(
        sectors: [Sector],
        problems: [ActiveProblem],
        toppedProblemIds: Set<UUID>,
        today: LocalDate,
        withinDays: Int = 7
    ) -> [UpcomingReset] {
        let bySector = Dictionary(grouping: problems, by: \.sectorId)
        return sectors
            .compactMap { sector -> UpcomingReset? in
                guard let date = sector.nextResetOn else { return nil }
                let daysLeft = today.days(until: date)
                guard (0...withinDays).contains(daysLeft) else { return nil }
                let set = bySector[sector.id] ?? []
                let notTopped = set.filter { !toppedProblemIds.contains($0.id) }.count
                return UpcomingReset(sector: sector, date: date, daysLeft: daysLeft,
                                     activeProblems: set.count, notTopped: notTopped)
            }
            .sorted { ($0.daysLeft, $0.sector.sortOrder) < ($1.daysLeft, $1.sector.sortOrder) }
    }
}
