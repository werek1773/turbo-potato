import BoulderKit
import Foundation
import Observation
import Supabase
import UIKit

/// Journal writes (pin taps, wellbeing) made on the device: applied locally at
/// once, persisted, and sent to the server in order in the background —
/// retried with backoff, and at once when the app comes to the foreground or
/// the network comes back.
@MainActor
@Observable
final class JournalOutbox {
    static let shared = JournalOutbox(backend: .shared)

    enum Status: Equatable {
        /// Nothing waiting.
        case saved
        case sending(pending: Int)
        case waitingForNetwork(pending: Int)
        /// The server answered with an error; retried with backoff.
        case failing(pending: Int, message: String)
    }

    private(set) var queue: Outbox
    private(set) var isSending = false
    /// The last send failed because the network was unreachable.
    private(set) var isOffline = false
    /// Message of the last failed send that will be retried.
    private(set) var failure: String?
    /// A write the server refused for good (e.g. the problem was taken
    /// down); shown until dismissed.
    private(set) var rejection: String?
    /// Incremented whenever the queue empties after sending: time to
    /// reconcile what is shown with the server.
    private(set) var drainCount = 0
    /// Number of writes sent so far in this launch.
    @ObservationIgnored private(set) var sentSequence = 0
    /// Ascent writes recently sent, by sequence number: a download started
    /// before they arrived must not undo them on screen.
    @ObservationIgnored private var recentlySent: [(sequence: Int, write: PendingAscent)] = []

    @ObservationIgnored private let backend: Backend
    private var userId: UUID?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    /// Bumped to tell a running flush loop that it has been replaced.
    @ObservationIgnored private var flushGeneration = 0
    @ObservationIgnored private var isBackingOff = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    private init(backend: Backend) {
        self.backend = backend
        queue = LocalStore.read(Outbox.self, from: LocalStore.outboxURL) ?? Outbox()
    }

    /// Starts watching the account, the network and the app's lifecycle.
    /// Safe to call more than once.
    func start() {
        guard !started else { return }
        started = true
        userId = backend.client.auth.currentUser?.id

        let auth = backend.client.auth
        Task { [weak self] in
            for await (_, session) in auth.authStateChanges {
                self?.accountChanged(to: session?.user.id)
            }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushNow() }
        })
        withObservationTracking { _ = Connectivity.shared.isOnline } onChange: { [weak self] in
            Task { @MainActor in self?.networkChanged() }
        }
        flush()
    }

    // MARK: Reading

    var pending: [OutboxEntry] {
        guard let userId else { return [] }
        return queue.entries(for: userId)
    }

    var status: Status {
        let count = pending.count
        guard count > 0 else { return .saved }
        if isOffline || !Connectivity.shared.isOnline { return .waitingForNetwork(pending: count) }
        if let failure { return .failing(pending: count, message: failure) }
        return .sending(pending: count)
    }

    func pendingAscents(gymId: UUID) -> [PendingAscent] {
        guard let userId else { return [] }
        return queue.pendingAscents(userId: userId, gymId: gymId)
    }

    /// Ascent writes of a gym confirmed after `sequence` (a `sentSequence`
    /// read before a download), oldest first.
    func ascentsSent(after sequence: Int, gymId: UUID) -> [PendingAscent] {
        recentlySent.filter { $0.sequence > sequence && $0.write.gymId == gymId }.map(\.write)
    }

    func pendingWellbeing(gymId: UUID, on day: LocalDate) -> PendingWellbeing? {
        guard let userId else { return nil }
        return queue.pendingWellbeing(userId: userId, gymId: gymId, on: day)
    }

    // MARK: Writing

    func enqueue(_ write: PendingWrite) {
        guard let userId = userId ?? backend.client.auth.currentUser?.id else { return }
        self.userId = userId
        queue.enqueue(write, userId: userId)
        persist()
        // A fresh tap is a good moment to try again, unless clearly offline.
        if Connectivity.shared.isOnline { flushNow() } else { flush() }
    }

    func dismissRejection() {
        rejection = nil
    }

    /// Retries at once, skipping any backoff in progress.
    func flushNow() {
        if isBackingOff { cancelFlush() }
        flush()
    }

    // MARK: Flushing

    private func flush() {
        guard flushTask == nil, userId != nil, !pending.isEmpty else { return }
        flushGeneration += 1
        let generation = flushGeneration
        flushTask = Task { [weak self] in
            await self?.drain(generation: generation)
        }
    }

    private func cancelFlush() {
        flushTask?.cancel()
        flushTask = nil
        flushGeneration += 1
        isBackingOff = false
        isSending = false
    }

    private func drain(generation: Int) async {
        var sentSomething = false
        defer {
            if generation == flushGeneration {
                flushTask = nil
                isSending = false
                isBackingOff = false
            }
        }
        while generation == flushGeneration, let userId, let entry = queue.next(for: userId) {
            isSending = true
            let outcome = await send(entry.write)
            guard generation == flushGeneration else { return }
            switch outcome {
            case .sent:
                sentSomething = true
                sentSequence += 1
                if case let .ascent(write) = entry.write {
                    recentlySent.append((sentSequence, write))
                    if recentlySent.count > 200 { recentlySent.removeFirst(recentlySent.count - 200) }
                }
                queue.remove(id: entry.id)
                isOffline = false
                failure = nil
            case let .retryAs(write):
                queue.replace(id: entry.id, with: write)
            case let .rejected(message):
                sentSomething = true
                queue.remove(id: entry.id)
                isOffline = false
                failure = nil
                rejection = message
            case let .failed(message, offline):
                queue.recordFailure(id: entry.id, message: message)
                isOffline = offline
                failure = offline ? nil : message
                persist()
                isSending = false
                isBackingOff = true
                let failures = queue.entries.first { $0.id == entry.id }?.failures ?? 1
                do {
                    try await Task.sleep(for: Outbox.retryDelay(afterFailures: failures))
                } catch {
                    return // Cancelled: replaced by an immediate retry.
                }
                guard generation == flushGeneration else { return }
                isBackingOff = false
                continue
            }
            persist()
        }
        if sentSomething, generation == flushGeneration, pending.isEmpty {
            drainCount += 1
        }
    }

    private enum Outcome {
        case sent
        case retryAs(PendingWrite)
        case rejected(String)
        case failed(String, offline: Bool)
    }

    private func send(_ write: PendingWrite) async -> Outcome {
        do {
            switch write {
            case let .ascent(ascent):
                try await backend.setAscent(
                    problemId: ascent.problemId,
                    on: ascent.localDate,
                    result: ascent.result,
                    attempts: ascent.attempts,
                    perceivedGrade: ascent.perceivedGrade,
                    limiters: ascent.limiters,
                    note: ascent.note
                )
            case let .wellbeing(wellbeing):
                // Both calls are idempotent: the session is unique per day.
                let sessionId = try await backend.upsertSession(gymId: wellbeing.gymId, on: wellbeing.localDate)
                let values = wellbeing.values
                try await backend.setWellbeing(SessionWellbeing(
                    sessionId: sessionId,
                    energy: values.energy,
                    rpe: values.rpe,
                    skin: values.skin,
                    painAreas: values.painAreas
                ))
            }
            return .sent
        } catch {
            if error.isConnectivityError {
                return .failed(UserFacingError.message(for: error), offline: true)
            }
            if Self.isRejection(error) {
                // Climbed it on another device first: still a top.
                if case var .ascent(ascent) = write, ascent.result == .flash,
                   (error as? PostgrestError)?.message == "flash_not_first_attempt" {
                    ascent.result = .top
                    return .retryAs(.ascent(ascent))
                }
                return .rejected(UserFacingError.message(for: error))
            }
            return .failed(UserFacingError.message(for: error), offline: false)
        }
    }

    /// The database refused the write itself (a rule, a missing row):
    /// sending it again would fail the same way.
    private static func isRejection(_ error: any Error) -> Bool {
        guard let code = (error as? PostgrestError)?.code else { return false }
        return code.hasPrefix("P0") || code == "42501" || code.hasPrefix("22") || code.hasPrefix("23")
    }

    // MARK: Account, network, storage

    private func accountChanged(to newUserId: UUID?) {
        guard newUserId != userId else { return }
        if newUserId == nil {
            // Keep unsent writes for when the same account signs back in,
            // but no cached private data.
            LocalStore.removeCatalogs()
        }
        cancelFlush()
        userId = newUserId
        if let newUserId, queue.entries.contains(where: { $0.userId != newUserId }) {
            queue.removeAll(notBelongingTo: newUserId)
            persist()
        }
        isOffline = false
        failure = nil
        rejection = nil
        flush()
    }

    private func networkChanged() {
        withObservationTracking { _ = Connectivity.shared.isOnline } onChange: { [weak self] in
            Task { @MainActor in self?.networkChanged() }
        }
        if Connectivity.shared.isOnline { flushNow() }
    }

    private func persist() {
        do {
            try LocalStore.write(queue, to: LocalStore.outboxURL)
        } catch {
            // Still sent from memory; only a restart before that would lose it.
            failure = UserFacingError.message(for: error)
        }
    }
}
