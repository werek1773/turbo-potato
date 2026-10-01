import BoulderKit
import Foundation
import Supabase

/// The private climbing journal: sessions, ascents, wellbeing.
extension Backend {
    /// Upserts (or with `result == nil` clears) my record of a problem on a
    /// climbing day. Idempotent, so safe to retry.
    @discardableResult
    func setAscent(
        problemId: UUID,
        on day: LocalDate,
        result: AscentResult?,
        attempts: AttemptsBucket? = nil,
        perceivedGrade: PerceivedGrade? = nil,
        limiters: [Limiter] = [],
        note: String? = nil
    ) async throws -> UUID? {
        struct Params: Encodable, Sendable {
            let p_problem_id: UUID
            let p_local_date: LocalDate
            let p_result: AscentResult?
            let p_attempts: AttemptsBucket?
            let p_perceived_grade: PerceivedGrade?
            let p_limiters: [Limiter]
            let p_note: String?

            enum CodingKeys: String, CodingKey {
                case p_problem_id, p_local_date, p_result, p_attempts, p_perceived_grade, p_limiters, p_note
            }

            // Every parameter is sent (nulls included) to match the RPC signature.
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(p_problem_id, forKey: .p_problem_id)
                try container.encode(p_local_date, forKey: .p_local_date)
                try container.encode(p_result, forKey: .p_result)
                try container.encode(p_attempts, forKey: .p_attempts)
                try container.encode(p_perceived_grade, forKey: .p_perceived_grade)
                try container.encode(p_limiters, forKey: .p_limiters)
                try container.encode(p_note, forKey: .p_note)
            }
        }
        return try await client.rpc("set_ascent", params: Params(
            p_problem_id: problemId,
            p_local_date: day,
            p_result: result,
            p_attempts: attempts,
            p_perceived_grade: perceivedGrade,
            p_limiters: limiters,
            p_note: note
        ))
        .execute()
        .value
    }

    func session(gymId: UUID, on day: LocalDate) async throws -> ClimbingSession? {
        let rows: [ClimbingSession] = try await client.from("sessions")
            .select()
            .eq("gym_id", value: gymId)
            .eq("local_date", value: day.description)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func upsertSession(gymId: UUID, on day: LocalDate) async throws -> UUID {
        struct Params: Encodable, Sendable {
            let p_gym_id: UUID
            let p_local_date: LocalDate
        }
        return try await client.rpc("upsert_session", params: Params(p_gym_id: gymId, p_local_date: day))
            .execute()
            .value
    }

    func wellbeing(sessionId: UUID) async throws -> SessionWellbeing? {
        let rows: [SessionWellbeing] = try await client.from("session_wellbeing")
            .select()
            .eq("session_id", value: sessionId)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func setWellbeing(_ wellbeing: SessionWellbeing) async throws {
        struct Params: Encodable, Sendable {
            let p_session_id: UUID
            let p_energy: Int?
            let p_rpe: Int?
            let p_skin: SkinState?
            let p_pain_areas: [BodyArea]

            enum CodingKeys: String, CodingKey {
                case p_session_id, p_energy, p_rpe, p_skin, p_pain_areas
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(p_session_id, forKey: .p_session_id)
                try container.encode(p_energy, forKey: .p_energy)
                try container.encode(p_rpe, forKey: .p_rpe)
                try container.encode(p_skin, forKey: .p_skin)
                try container.encode(p_pain_areas, forKey: .p_pain_areas)
            }
        }
        try await client.rpc("set_session_wellbeing", params: Params(
            p_session_id: wellbeing.sessionId,
            p_energy: wellbeing.energy,
            p_rpe: wellbeing.rpe,
            p_skin: wellbeing.skin,
            p_pain_areas: wellbeing.painAreas
        ))
        .execute()
    }
}
