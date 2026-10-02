import BoulderKit
import SwiftUI

/// Example data for the intro, shown before signing in (no network yet):
/// the plan of Volt Łódź with made-up problems along its walls.
enum IntroDemo {
    static let plan = FloorPlan(
        aspect: 0.7547,
        mats: [
            [p(0.04, 0.0396), p(0.0813, 0.0283), p(0.215, 0.0283), p(0.36, 0.0283), p(0.4537, 0.0283), p(0.5875, 0.034),
             p(0.645, 0.0368), p(0.9513, 0.0443), p(0.935, 0.1698), p(0.0537, 0.1509)],
            [p(0.3999, 0.8793), p(0.1937, 0.8793), p(0.075, 0.8085), p(0.0787, 0.6415), p(0.1237, 0.5349), p(0.2775, 0.5095),
             p(0.2775, 0.7736)],
            [p(0.2124, 0.3349), p(0.5212, 0.3378), p(0.625, 0.3868), p(0.7212, 0.3604), p(0.8187, 0.4227), p(0.7999, 0.5217),
             p(0.7212, 0.5925), p(0.8087, 0.6349), p(0.7212, 0.767), p(0.7687, 0.7953), p(0.6749, 0.8821), p(0.4749, 0.8821),
             p(0.5537, 0.7925), p(0.5125, 0.6321), p(0.5625, 0.5189), p(0.3374, 0.4528)],
        ],
        entrances: [p(0.03, 0.095), p(0.437, 0.93)]
    )

    private static let paths: [[MapPoint]] = [
        [p(0.04, 0.0396), p(0.0813, 0.0283), p(0.215, 0.0283)], [p(0.215, 0.0283), p(0.36, 0.0283)],
        [p(0.36, 0.0283), p(0.4537, 0.0283)], [p(0.4537, 0.0283), p(0.5875, 0.034)],
        [p(0.5875, 0.034), p(0.645, 0.0368)], [p(0.645, 0.0368), p(0.9513, 0.0443)],
        [p(0.3999, 0.8793), p(0.1937, 0.8793)], [p(0.1937, 0.8793), p(0.075, 0.8085)],
        [p(0.075, 0.8085), p(0.0787, 0.6415)], [p(0.0787, 0.6415), p(0.1237, 0.5349), p(0.2775, 0.5095)],
        [p(0.2124, 0.3349), p(0.5212, 0.3378)], [p(0.5212, 0.3378), p(0.625, 0.3868)],
        [p(0.625, 0.3868), p(0.7212, 0.3604)], [p(0.7212, 0.3604), p(0.8187, 0.4227), p(0.7999, 0.5217)],
        [p(0.7999, 0.5217), p(0.7212, 0.5925), p(0.8087, 0.6349)], [p(0.8087, 0.6349), p(0.7212, 0.767)],
        [p(0.7212, 0.767), p(0.7687, 0.7953), p(0.6749, 0.8821)], [p(0.6749, 0.8821), p(0.4749, 0.8821)],
    ]

    /// Each sector's field of mat, in the same order as `paths`.
    private static let zones: [[MapPoint]] = [
        [p(0.04, 0.0396), p(0.0813, 0.0283), p(0.215, 0.0283), p(0.2579, 0.1553), p(0.0537, 0.1509)],
        [p(0.215, 0.0283), p(0.36, 0.0283), p(0.4285, 0.1589), p(0.2579, 0.1553)],
        [p(0.36, 0.0283), p(0.4537, 0.0283), p(0.4285, 0.1589)],
        [p(0.4537, 0.0283), p(0.5875, 0.034), p(0.6339, 0.1633), p(0.4285, 0.1589)],
        [p(0.5875, 0.034), p(0.645, 0.0368), p(0.6339, 0.1633)],
        [p(0.645, 0.0368), p(0.9513, 0.0443), p(0.935, 0.1698), p(0.6339, 0.1633)],
        [p(0.3999, 0.8793), p(0.1937, 0.8793), p(0.2775, 0.7736)],
        [p(0.1937, 0.8793), p(0.075, 0.8085), p(0.2775, 0.7736)],
        [p(0.075, 0.8085), p(0.0787, 0.6415), p(0.2775, 0.7736)],
        [p(0.0787, 0.6415), p(0.1237, 0.5349), p(0.2775, 0.5095), p(0.2775, 0.7736)],
        [p(0.2124, 0.3349), p(0.5212, 0.3378), p(0.3374, 0.4528)],
        [p(0.5212, 0.3378), p(0.625, 0.3868), p(0.5625, 0.5189), p(0.3374, 0.4528)],
        [p(0.625, 0.3868), p(0.7212, 0.3604), p(0.5625, 0.5189)],
        [p(0.7212, 0.3604), p(0.8187, 0.4227), p(0.7999, 0.5217), p(0.5625, 0.5189)],
        [p(0.7999, 0.5217), p(0.7212, 0.5925), p(0.8087, 0.6349), p(0.5125, 0.6321), p(0.5625, 0.5189)],
        [p(0.8087, 0.6349), p(0.7212, 0.767), p(0.5537, 0.7925), p(0.5125, 0.6321)],
        [p(0.7212, 0.767), p(0.7687, 0.7953), p(0.6749, 0.8821), p(0.5537, 0.7925)],
        [p(0.6749, 0.8821), p(0.4749, 0.8821), p(0.5537, 0.7925)],
    ]

    private static let gymId = UUID()

    static let sectors: [Sector] = paths.enumerated().map { index, path in
        Sector(id: UUID(), gymId: gymId, name: "Sektor \(index + 1)", sortOrder: index + 1,
               mapPath: path, mapZone: zones[index])
    }

    struct Problem {
        let id = UUID()
        let fraction: Double
        let grade: Int
        let color: HoldColor
        let isTopped: Bool
    }

    /// 4–10 problems per wall, the same every launch.
    static let problems: [UUID: [Problem]] = {
        var generator = SeededGenerator(seed: 42)
        let colors: [HoldColor] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .black, .white]
        var result: [UUID: [Problem]] = [:]
        for sector in sectors {
            let count = 4 + Int(generator.next() * 7)
            result[sector.id] = (0..<count).map { index in
                Problem(fraction: (Double(index) + 0.5 + (generator.next() - 0.5) * 0.5) / Double(count),
                        grade: 1 + Int(generator.next() * 9),
                        color: colors[Int(generator.next() * Double(colors.count))],
                        isTopped: generator.next() < 0.35)
            }
        }
        return result
    }()

    static func dots(for sector: Sector, grade: Int?) -> [MapDot] {
        (problems[sector.id] ?? []).map { problem in
            MapDot(id: problem.id, fraction: problem.fraction, color: problem.color,
                   isTopped: problem.isTopped, isMatching: grade == nil || problem.grade == grade)
        }
    }

    private static func p(_ x: Double, _ y: Double) -> MapPoint { MapPoint(x: x, y: y) }
}

/// Park–Miller generator, so the example looks the same every time.
private struct SeededGenerator {
    private var state: Int

    init(seed: Int) { state = seed }

    mutating func next() -> Double {
        state = (state * 16807) % 2_147_483_647
        return Double(state - 1) / 2_147_483_646
    }
}
