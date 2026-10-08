import BoulderKit
import SwiftUI

/// Polish counted nouns: "1 problem", "3 problemy", "7 problemów".
enum Polish {
    static func count(_ count: Int, one: String, few: String, many: String) -> String {
        let lastTwo = count % 100, last = count % 10
        if count == 1 { return "1 \(one)" }
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "\(count) \(few)" }
        return "\(count) \(many)"
    }

    static func problems(_ count: Int) -> String {
        Self.count(count, one: "problem", few: "problemy", many: "problemów")
    }
}

extension ProblemPin {
    /// What VoiceOver reads for a pin: "Problem 5, kolor żółty, sektor Grota".
    static func accessibilityLabel(grade: String?, color: HoldColor, sector: String?) -> String {
        var parts = [grade.map { "Problem \($0)" } ?? "Problem", "kolor \(color.polishName)"]
        if let sector { parts.append("sektor \(sector)") }
        return parts.joined(separator: ", ")
    }
}

extension TimelineSchedule where Self == AnimationTimelineSchedule {
    /// The 8 fps clock of the drawings; stands still with Reduce Motion.
    static func stopMotion(paused: Bool) -> AnimationTimelineSchedule {
        .animation(minimumInterval: 1 / StopMotion.fps, paused: paused)
    }
}
