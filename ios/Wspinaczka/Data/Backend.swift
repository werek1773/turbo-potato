import BoulderKit
import Foundation
import Supabase

/// Typed access to the Supabase API. All writes that need validation go
/// through RPCs defined in `supabase/migrations`.
struct Backend: Sendable {
    let client: SupabaseClient

    init() {
        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabasePublishableKey,
            options: SupabaseClientOptions(
                // Start from the stored session at once, even when it has
                // expired: the SDK refreshes it in the background, requests
                // wait for the fresh token, and a revoked one ends in
                // `.signedOut`. The old behaviour (logged as a warning on
                // every launch) goes away in supabase-swift 3.
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }

    // MARK: Auth

    func signInWithApple(idToken: String, nonce: String) async throws {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }

    #if DEBUG
    /// Debug-only email + password auth for the simulator. Returns false when
    /// the new account still has to confirm its email before signing in.
    func signInForTesting(email: String, password: String, createAccount: Bool) async throws -> Bool {
        if createAccount {
            return try await client.auth.signUp(email: email, password: password).session != nil
        }
        try await client.auth.signIn(email: email, password: password)
        return true
    }
    #endif

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func deleteAccount(authorizationCode: String?) async throws {
        struct Body: Encodable, Sendable { let authorizationCode: String? }
        try await client.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(body: Body(authorizationCode: authorizationCode))
        )
    }

    // MARK: Me

    func myProfile() async throws -> Profile? {
        guard let userId = client.auth.currentUser?.id else { return nil }
        let rows: [Profile] = try await client.from("profiles")
            .select()
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func myAccess() async throws -> Access {
        try await client.rpc("my_access").execute().value
    }

    func updateDisplayName(_ name: String) async throws {
        guard let userId = client.auth.currentUser?.id else { return }
        try await client.from("profiles")
            .update(["display_name": String(name.prefix(40))])
            .eq("id", value: userId)
            .execute()
    }

    func setStatsOptOut(_ optOut: Bool) async throws {
        try await client.rpc("set_stats_opt_out", params: ["p_opt_out": optOut]).execute()
    }

    func setHealthDataConsent(_ consent: Bool) async throws {
        try await client.rpc("set_health_data_consent", params: ["p_consent": consent]).execute()
    }

    /// GDPR export as pretty-printed JSON.
    func exportMyData() async throws -> Data {
        let response = try await client.rpc("export_my_data").execute()
        let object = try JSONSerialization.jsonObject(with: response.data)
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: Invites & staff

    func acceptInvite(code: String) async throws -> InviteAcceptance {
        try await client.rpc("accept_invite", params: ["p_code": code]).execute().value
    }

    func createInvite(gymId: UUID, role: GymRole, maxUses: Int = 1) async throws -> CreatedInvite {
        struct Params: Encodable, Sendable {
            let p_gym_id: UUID
            let p_role: GymRole
            let p_max_uses: Int
        }
        let rows: [CreatedInvite] = try await client
            .rpc("create_invite", params: Params(p_gym_id: gymId, p_role: role, p_max_uses: maxUses))
            .execute()
            .value
        guard let invite = rows.first else { throw URLError(.badServerResponse) }
        return invite
    }

    func setGymPublished(gymId: UUID, published: Bool) async throws {
        struct Params: Encodable, Sendable {
            let p_gym_id: UUID
            let p_published: Bool
        }
        try await client.rpc("set_gym_published", params: Params(p_gym_id: gymId, p_published: published)).execute()
    }

    // MARK: Catalog

    func visibleGyms() async throws -> [Gym] {
        try await client.from("gyms").select().order("name").execute().value
    }

    func grades(gymId: UUID) async throws -> [Grade] {
        try await client.from("grades")
            .select()
            .eq("gym_id", value: gymId)
            .order("sort_order")
            .execute()
            .value
    }

    func sectors(gymId: UUID) async throws -> [Sector] {
        try await client.from("sectors")
            .select()
            .eq("gym_id", value: gymId)
            .is("archived_at", value: nil)
            .order("sort_order")
            .execute()
            .value
    }

    func currentPhotos(gymId: UUID, photoIds: [UUID]) async throws -> [SectorPhoto] {
        guard !photoIds.isEmpty else { return [] }
        return try await client.from("sector_photos")
            .select()
            .eq("gym_id", value: gymId)
            .in("id", values: photoIds)
            .execute()
            .value
    }

    func activeProblems(gymId: UUID) async throws -> [ActiveProblem] {
        try await client.from("active_problems")
            .select()
            .eq("gym_id", value: gymId)
            .execute()
            .value
    }

    func myAscents(gymId: UUID) async throws -> [Ascent] {
        try await client.from("ascents")
            .select()
            .eq("gym_id", value: gymId)
            .order("local_date", ascending: false)
            .execute()
            .value
    }

    func photoURL(for photo: SectorPhoto) -> URL? {
        try? client.storage.from(AppConfig.sectorPhotosBucket).getPublicURL(path: photo.storagePath)
    }
}

extension Backend {
    func addSector(gymId: UUID, name: String, area: String?, sortOrder: Int) async throws {
        struct NewSector: Encodable, Sendable {
            let gym_id: UUID
            let name: String
            let area: String?
            let sort_order: Int
        }
        try await client.from("sectors")
            .insert(NewSector(gym_id: gymId, name: name, area: area, sort_order: sortOrder))
            .execute()
    }
}

extension Backend {
    /// One client for the whole app (it owns the auth session).
    static let shared = Backend()
}

extension Backend {
    /// Announce (or clear with nil) the next reset of a sector.
    func setNextReset(sectorId: UUID, on date: LocalDate?) async throws {
        struct Params: Encodable, Sendable {
            let p_sector_id: UUID
            let p_date: LocalDate?

            enum CodingKeys: String, CodingKey {
                case p_sector_id, p_date
            }

            // Send an explicit null to clear the date (the synthesized
            // encoder would omit the key and miss the RPC signature).
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(p_sector_id, forKey: .p_sector_id)
                try container.encode(p_date, forKey: .p_date)
            }
        }
        try await client.rpc("set_next_reset", params: Params(p_sector_id: sectorId, p_date: date)).execute()
    }
}
