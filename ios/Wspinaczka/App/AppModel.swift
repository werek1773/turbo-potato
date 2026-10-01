import BoulderKit
import Foundation
import Observation
import Supabase

struct PendingInvite: Identifiable {
    let id = UUID()
    let code: String
}

/// App-wide state: who is signed in and what they are allowed to do.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn(UUID)
    }

    let backend: Backend
    private(set) var phase: Phase = .launching
    private(set) var profile: Profile?
    private(set) var access: Access = .none
    private(set) var gyms: [Gym] = []
    var pendingInvite: PendingInvite?
    var errorMessage: String?
    var isShowingError = false

    private var authTask: Task<Void, Never>?

    init(backend: Backend = .shared) {
        self.backend = backend
    }

    var userId: UUID? {
        if case let .signedIn(id) = phase { id } else { nil }
    }

    func start() {
        guard authTask == nil else { return }
        let auth = backend.client.auth
        authTask = Task { [weak self] in
            for await (_, session) in auth.authStateChanges {
                await self?.apply(userId: session?.user.id)
            }
        }
    }

    private func apply(userId: UUID?) async {
        guard let userId else {
            phase = .signedOut
            profile = nil
            access = .none
            gyms = []
            return
        }
        guard phase != .signedIn(userId) else { return }
        phase = .signedIn(userId)
        await refresh()
    }

    func refresh() async {
        do {
            async let profile = backend.myProfile()
            async let access = backend.myAccess()
            async let gyms = backend.visibleGyms()
            self.profile = try await profile
            self.access = try await access
            self.gyms = try await gyms
        } catch {
            report(error)
        }
    }

    // MARK: Sign in / out

    func signIn(with credential: AppleCredential) async {
        do {
            try await backend.signInWithApple(idToken: credential.idToken, nonce: credential.rawNonce)
            // Apple shares the name only on the very first authorization.
            if let name = credential.fullName, !name.isEmpty {
                try await backend.updateDisplayName(name)
                profile = try await backend.myProfile()
            }
        } catch {
            report(error)
        }
    }

    func signOut() async {
        do {
            try await backend.signOut()
        } catch {
            report(error)
        }
    }

    func deleteAccount(confirmedWith credential: AppleCredential) async -> Bool {
        do {
            try await backend.deleteAccount(authorizationCode: credential.authorizationCode)
            try? await backend.signOut()
            return true
        } catch {
            report(error)
            return false
        }
    }

    // MARK: Profile & privacy

    func updateDisplayName(_ name: String) async {
        do {
            try await backend.updateDisplayName(name)
            profile = try await backend.myProfile()
        } catch {
            report(error)
        }
    }

    func setStatsOptOut(_ optOut: Bool) async {
        do {
            try await backend.setStatsOptOut(optOut)
            profile = try await backend.myProfile()
        } catch {
            report(error)
        }
    }

    func setHealthDataConsent(_ consent: Bool) async {
        do {
            try await backend.setHealthDataConsent(consent)
            profile = try await backend.myProfile()
        } catch {
            report(error)
        }
    }

    // MARK: Errors

    func report(_ error: any Error) {
        if error is CancellationError { return }
        errorMessage = UserFacingError.message(for: error)
        isShowingError = true
    }
}
