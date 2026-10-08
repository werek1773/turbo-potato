import BoulderKit
import Foundation
import Supabase

/// Reads for the statistics screens.
extension Backend {
    /// My sessions in a gym (private rows, RLS: owner only), newest first.
    func mySessions(gymId: UUID) async throws -> [ClimbingSession] {
        try await client.from("sessions")
            .select()
            .eq("gym_id", value: gymId)
            .order("local_date", ascending: false)
            .execute()
            .value
    }

    /// The gym's anonymous daily snapshot. Every count is already k ≥ 5 and
    /// rounded down to 5 on the server; hidden cells come back as null.
    func problemStats(gymId: UUID) async throws -> [ProblemStats] {
        try await client.from("problem_stats")
            .select("problem_id, computed_at, climbers, tops, flashes, perceived_soft, perceived_ok, perceived_hard, limiters")
            .eq("gym_id", value: gymId)
            .execute()
            .value
    }
}
