import Foundation

// Raw values match the Postgres enums exactly.

public enum GymRole: String, Codable, Sendable, CaseIterable {
    case manager
    case routesetter
}

public enum HoldColor: String, Codable, Sendable, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, black, white, grey, brown, multi
}

public enum StyleTag: String, Codable, Sendable, CaseIterable {
    case slab, vertical, overhang, roof
    case crimps, slopers, pinches, pockets, jugs, volumes
    case `dynamic`, `static`, coordination, compression, balance
}

public enum AscentResult: String, Codable, Sendable, CaseIterable {
    case flash, top, project

    /// Tap cycle on a pin in "Podsumuj sesję": none → top → flash → project → none.
    /// Flash is skipped when the problem was already tried on an earlier day.
    public static func next(after current: AscentResult?, canFlash: Bool = true) -> AscentResult? {
        let candidate: AscentResult? = switch current {
        case nil: .top
        case .top: .flash
        case .flash: .project
        case .project: nil
        }
        if candidate == .flash && !canFlash { return .project }
        return candidate
    }

    public var isTop: Bool { self != .project }

    /// Higher is better; used to pick the best result for a problem.
    public var rank: Int {
        switch self {
        case .project: 0
        case .top: 1
        case .flash: 2
        }
    }
}

public enum AttemptsBucket: String, Codable, Sendable, CaseIterable {
    case one = "1"
    case twoToThree = "2-3"
    case fourToTen = "4-10"
    case moreThanTen = "10+"
}

public enum PerceivedGrade: String, Codable, Sendable, CaseIterable {
    case soft, ok, hard
}

/// What stopped you on a project. Deliberately non-medical.
public enum Limiter: String, Codable, Sendable, CaseIterable {
    case fingerStrength = "finger_strength"
    case power, endurance, core, flexibility
    case footwork, balance, coordination, beta
    case fear, commitment, conditions
}

public enum SessionSource: String, Codable, Sendable {
    case geofence, manual
}

public enum SkinState: String, Codable, Sendable, CaseIterable {
    case fresh, ok, thin, split
}

public enum BodyArea: String, Codable, Sendable, CaseIterable {
    case fingers, wrists, elbows, shoulders, back, knees, ankles, other
}
