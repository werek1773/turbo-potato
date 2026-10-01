import Foundation

// Rows as returned by the Supabase Data API (snake_case columns).

public struct Gym: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var slug: String
    public var name: String
    public var city: String?
    public var address: String?
    public var timezone: String
    public var latitude: Double?
    public var longitude: Double?
    public var geofenceRadiusM: Int
    public var publishedAt: Date?

    public var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }
    public var isPublished: Bool { publishedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id, slug, name, city, address, timezone, latitude, longitude
        case geofenceRadiusM = "geofence_radius_m"
        case publishedAt = "published_at"
    }
}

public struct Grade: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let gymId: UUID
    public let label: String
    public let sortOrder: Int
    public var vEquivalent: Double?
    public var color: String?
    public var isActive: Bool

    public init(id: UUID, gymId: UUID, label: String, sortOrder: Int,
                vEquivalent: Double? = nil, color: String? = nil, isActive: Bool = true) {
        self.id = id
        self.gymId = gymId
        self.label = label
        self.sortOrder = sortOrder
        self.vEquivalent = vEquivalent
        self.color = color
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case id, label, color
        case gymId = "gym_id"
        case sortOrder = "sort_order"
        case vEquivalent = "v_equivalent"
        case isActive = "is_active"
    }
}

public struct Sector: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let gymId: UUID
    public var name: String
    public var sortOrder: Int
    public var currentPhotoId: UUID?
    public var lastResetAt: Date?
    public var archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case gymId = "gym_id"
        case sortOrder = "sort_order"
        case currentPhotoId = "current_photo_id"
        case lastResetAt = "last_reset_at"
        case archivedAt = "archived_at"
    }
}

public struct SectorPhoto: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let sectorId: UUID
    public let gymId: UUID
    public let storagePath: String
    public let width: Int
    public let height: Int

    public var aspectRatio: Double { Double(width) / Double(height) }

    enum CodingKeys: String, CodingKey {
        case id, width, height
        case sectorId = "sector_id"
        case gymId = "gym_id"
        case storagePath = "storage_path"
    }
}

/// Row of the `active_problems` view: an active problem with its pin on the
/// sector's current photo.
public struct ActiveProblem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let gymId: UUID
    public let sectorId: UUID
    public var gradeId: UUID
    public var holdColor: HoldColor
    public var name: String?
    public var styleTags: [StyleTag]
    public let setAt: Date
    public let photoId: UUID
    public var pinX: Double
    public var pinY: Double

    public init(id: UUID, gymId: UUID, sectorId: UUID, gradeId: UUID, holdColor: HoldColor,
                name: String? = nil, styleTags: [StyleTag] = [], setAt: Date,
                photoId: UUID, pinX: Double, pinY: Double) {
        self.id = id
        self.gymId = gymId
        self.sectorId = sectorId
        self.gradeId = gradeId
        self.holdColor = holdColor
        self.name = name
        self.styleTags = styleTags
        self.setAt = setAt
        self.photoId = photoId
        self.pinX = pinX
        self.pinY = pinY
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case gymId = "gym_id"
        case sectorId = "sector_id"
        case gradeId = "grade_id"
        case holdColor = "hold_color"
        case styleTags = "style_tags"
        case setAt = "set_at"
        case photoId = "photo_id"
        case pinX = "pin_x"
        case pinY = "pin_y"
    }
}

public struct Ascent: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let gymId: UUID
    public let problemId: UUID
    public let localDate: LocalDate
    public var result: AscentResult
    public var attempts: AttemptsBucket?
    public var perceivedGrade: PerceivedGrade?
    public var limiters: [Limiter]
    public var note: String?
    public let gradeIdSnapshot: UUID

    public init(id: UUID = UUID(), gymId: UUID, problemId: UUID, localDate: LocalDate,
                result: AscentResult, attempts: AttemptsBucket? = nil,
                perceivedGrade: PerceivedGrade? = nil, limiters: [Limiter] = [],
                note: String? = nil, gradeIdSnapshot: UUID) {
        self.id = id
        self.gymId = gymId
        self.problemId = problemId
        self.localDate = localDate
        self.result = result
        self.attempts = attempts
        self.perceivedGrade = perceivedGrade
        self.limiters = limiters
        self.note = note
        self.gradeIdSnapshot = gradeIdSnapshot
    }

    enum CodingKeys: String, CodingKey {
        case id, result, attempts, limiters, note
        case gymId = "gym_id"
        case problemId = "problem_id"
        case localDate = "local_date"
        case perceivedGrade = "perceived_grade"
        case gradeIdSnapshot = "grade_id_snapshot"
    }
}

public struct ClimbingSession: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let gymId: UUID
    public let localDate: LocalDate
    public var startedAt: Date?
    public var endedAt: Date?
    public var source: SessionSource
    public var note: String?

    enum CodingKeys: String, CodingKey {
        case id, source, note
        case gymId = "gym_id"
        case localDate = "local_date"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

public struct Profile: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var displayName: String
    public var statsOptOut: Bool
    public var healthDataConsentAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case statsOptOut = "stats_opt_out"
        case healthDataConsentAt = "health_data_consent_at"
    }
}

/// Anonymous daily snapshot; nil means "fewer than 5 climbers".
public struct ProblemStats: Hashable, Codable, Sendable {
    public let problemId: UUID
    public let climbers: Int?
    public let tops: Int?
    public let flashes: Int?
    public let perceivedSoft: Int?
    public let perceivedOk: Int?
    public let perceivedHard: Int?
    public let limiters: [String: Int]

    enum CodingKeys: String, CodingKey {
        case climbers, tops, flashes, limiters
        case problemId = "problem_id"
        case perceivedSoft = "perceived_soft"
        case perceivedOk = "perceived_ok"
        case perceivedHard = "perceived_hard"
    }

    /// The community's verdict when one bucket clearly dominates.
    public var communityGrade: PerceivedGrade? {
        let buckets: [(PerceivedGrade, Int)] = [
            (.soft, perceivedSoft ?? 0), (.ok, perceivedOk ?? 0), (.hard, perceivedHard ?? 0),
        ]
        let sorted = buckets.sorted { $0.1 > $1.1 }
        guard sorted[0].1 > 0, sorted[0].1 > sorted[1].1 else { return nil }
        return sorted[0].0
    }
}

/// Result of the `my_access` RPC.
public struct Access: Hashable, Codable, Sendable {
    public struct Membership: Hashable, Codable, Sendable {
        public let gymId: UUID
        public let role: GymRole

        enum CodingKeys: String, CodingKey {
            case role
            case gymId = "gym_id"
        }
    }

    public let isPlatformAdmin: Bool
    public let gymRoles: [Membership]

    public init(isPlatformAdmin: Bool, gymRoles: [Membership]) {
        self.isPlatformAdmin = isPlatformAdmin
        self.gymRoles = gymRoles
    }

    public static let none = Access(isPlatformAdmin: false, gymRoles: [])

    public func role(in gymId: UUID) -> GymRole? {
        gymRoles.first { $0.gymId == gymId }?.role
    }

    public func isStaff(of gymId: UUID) -> Bool { isPlatformAdmin || role(in: gymId) != nil }
    public func isManager(of gymId: UUID) -> Bool { isPlatformAdmin || role(in: gymId) == .manager }

    enum CodingKeys: String, CodingKey {
        case isPlatformAdmin = "is_platform_admin"
        case gymRoles = "gym_roles"
    }
}

/// Result of the `accept_invite` RPC.
public struct InviteAcceptance: Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case ok, invalid
        case rateLimited = "rate_limited"
    }

    public let status: Status
    public let gymId: UUID?
    public let role: GymRole?

    enum CodingKeys: String, CodingKey {
        case status, role
        case gymId = "gym_id"
    }
}

/// Row returned by the `create_invite` RPC.
public struct CreatedInvite: Hashable, Codable, Sendable {
    public let inviteId: UUID
    public let code: String
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case code
        case inviteId = "invite_id"
        case expiresAt = "expires_at"
    }
}
