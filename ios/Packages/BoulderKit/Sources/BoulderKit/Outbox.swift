import Foundation

// The offline outbox: journal writes made on the device and not yet confirmed
// by the server. Every write is an idempotent upsert keyed by what it changes
// (a problem on a climbing day, the wellbeing of a climbing day), so the queue
// only ever needs the latest state per key and can be replayed safely.

/// My record of one problem on one climbing day; `result == nil` clears it.
public struct PendingAscent: Hashable, Codable, Sendable {
    /// Local id, used for display until the server row is known.
    public let id: UUID
    public let gymId: UUID
    public let problemId: UUID
    public let localDate: LocalDate
    public var result: AscentResult?
    public var attempts: AttemptsBucket?
    public var perceivedGrade: PerceivedGrade?
    public var limiters: [Limiter]
    public var note: String?
    /// Grade of the problem at the time of the tap (the server keeps its own).
    public let gradeIdSnapshot: UUID

    public init(id: UUID = UUID(), gymId: UUID, problemId: UUID, localDate: LocalDate,
                result: AscentResult?, attempts: AttemptsBucket? = nil,
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

    /// The ascent as it will look once saved, keeping the identity of the
    /// server row it replaces. Nil when the write clears the record.
    public func ascent(replacing existing: Ascent? = nil) -> Ascent? {
        guard let result else { return nil }
        return Ascent(
            id: existing?.id ?? id,
            gymId: gymId,
            problemId: problemId,
            localDate: localDate,
            result: result,
            attempts: attempts,
            perceivedGrade: perceivedGrade,
            limiters: limiters,
            note: note,
            gradeIdSnapshot: existing?.gradeIdSnapshot ?? gradeIdSnapshot
        )
    }
}

/// Energy, effort, skin and pain of a session, without the session id
/// (which only the server knows for a day logged offline).
public struct WellbeingValues: Hashable, Codable, Sendable {
    public var energy: Int?
    public var rpe: Int?
    public var skin: SkinState?
    public var painAreas: [BodyArea]

    public init(energy: Int? = nil, rpe: Int? = nil, skin: SkinState? = nil, painAreas: [BodyArea] = []) {
        self.energy = energy
        self.rpe = rpe
        self.skin = skin
        self.painAreas = painAreas
    }

    public init(_ wellbeing: SessionWellbeing) {
        self.init(energy: wellbeing.energy, rpe: wellbeing.rpe, skin: wellbeing.skin,
                  painAreas: wellbeing.painAreas)
    }

    /// Nothing filled in: saving it deletes the entry.
    public var isEmpty: Bool { energy == nil && rpe == nil && skin == nil && painAreas.isEmpty }
}

/// Wellbeing of my session at a gym on a climbing day. The session is
/// created on demand when it is sent.
public struct PendingWellbeing: Hashable, Codable, Sendable {
    public let gymId: UUID
    public let localDate: LocalDate
    public var values: WellbeingValues

    public init(gymId: UUID, localDate: LocalDate, values: WellbeingValues) {
        self.gymId = gymId
        self.localDate = localDate
        self.values = values
    }
}

public enum PendingWrite: Hashable, Codable, Sendable {
    case ascent(PendingAscent)
    case wellbeing(PendingWellbeing)

    /// Writes with the same key overwrite each other on the server.
    public enum Key: Hashable, Sendable {
        case ascent(problemId: UUID, localDate: LocalDate)
        case wellbeing(gymId: UUID, localDate: LocalDate)
    }

    public var key: Key {
        switch self {
        case let .ascent(write): .ascent(problemId: write.problemId, localDate: write.localDate)
        case let .wellbeing(write): .wellbeing(gymId: write.gymId, localDate: write.localDate)
        }
    }

    public var gymId: UUID {
        switch self {
        case let .ascent(write): write.gymId
        case let .wellbeing(write): write.gymId
        }
    }
}

public struct OutboxEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// Writes are sent with this user's session only.
    public let userId: UUID
    public var write: PendingWrite
    public let enqueuedAt: Date
    /// Failed sends since the last success; drives the retry backoff.
    public var failures: Int
    public var lastError: String?

    public init(id: UUID = UUID(), userId: UUID, write: PendingWrite, enqueuedAt: Date = .now,
                failures: Int = 0, lastError: String? = nil) {
        self.id = id
        self.userId = userId
        self.write = write
        self.enqueuedAt = enqueuedAt
        self.failures = failures
        self.lastError = lastError
    }
}

/// Ordered queue of pending writes, coalesced per key.
public struct Outbox: Hashable, Codable, Sendable {
    public private(set) var entries: [OutboxEntry]

    public init(entries: [OutboxEntry] = []) {
        self.entries = entries
    }

    /// Queues `write`, dropping any older write with the same key: only the
    /// final state of a problem (or a day's wellbeing) is sent. The new entry
    /// goes to the end, so it is sent after anything queued before it — also
    /// after an older write of the same key that is already in flight.
    @discardableResult
    public mutating func enqueue(_ write: PendingWrite, userId: UUID, id: UUID = UUID(),
                                 at date: Date = .now) -> OutboxEntry {
        let key = write.key
        entries.removeAll { $0.userId == userId && $0.write.key == key }
        let entry = OutboxEntry(id: id, userId: userId, write: write, enqueuedAt: date)
        entries.append(entry)
        return entry
    }

    /// Removes a sent entry. A no-op when a newer tap already replaced it.
    public mutating func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Rewrites an entry in place (e.g. a rejected flash sent again as a top).
    public mutating func replace(id: UUID, with write: PendingWrite) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].write = write
        entries[index].lastError = nil
    }

    public mutating func recordFailure(id: UUID, message: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].failures += 1
        entries[index].lastError = message
    }

    /// Writes left behind by another account are never sent with this one.
    public mutating func removeAll(notBelongingTo userId: UUID) {
        entries.removeAll { $0.userId != userId }
    }

    public func entries(for userId: UUID) -> [OutboxEntry] {
        entries.filter { $0.userId == userId }
    }

    /// The oldest write to send next.
    public func next(for userId: UUID) -> OutboxEntry? {
        entries.first { $0.userId == userId }
    }

    public func pendingAscents(userId: UUID, gymId: UUID) -> [PendingAscent] {
        entries.compactMap { entry in
            guard entry.userId == userId, case let .ascent(write) = entry.write, write.gymId == gymId else {
                return nil
            }
            return write
        }
    }

    public func pendingWellbeing(userId: UUID, gymId: UUID, on day: LocalDate) -> PendingWellbeing? {
        entries.lazy.compactMap { entry -> PendingWellbeing? in
            guard entry.userId == userId, case let .wellbeing(write) = entry.write,
                  write.gymId == gymId, write.localDate == day else { return nil }
            return write
        }.last
    }

    /// Server ascents with every pending write applied on top, newest day first.
    /// Pending records win, so a tap made offline does not flicker back when
    /// the server data is refreshed before the write is sent.
    public static func merge(server: [Ascent], pending: [PendingAscent]) -> [Ascent] {
        guard !pending.isEmpty else { return server }
        struct Key: Hashable {
            let problemId: UUID
            let localDate: LocalDate
        }
        var latest: [Key: PendingAscent] = [:]
        for write in pending {
            latest[Key(problemId: write.problemId, localDate: write.localDate)] = write
        }
        var merged: [Ascent] = []
        var replaced: Set<Key> = []
        for ascent in server {
            let key = Key(problemId: ascent.problemId, localDate: ascent.localDate)
            if let write = latest[key] {
                if replaced.insert(key).inserted, let updated = write.ascent(replacing: ascent) {
                    merged.append(updated)
                }
            } else {
                merged.append(ascent)
            }
        }
        for (key, write) in latest where !replaced.contains(key) {
            if let added = write.ascent() { merged.append(added) }
        }
        return merged.sorted { $0.localDate > $1.localDate }
    }

    /// Pause before retrying after `failures` failed sends in a row:
    /// 2 s, 4 s, 8 s … capped at 5 minutes.
    public static func retryDelay(afterFailures failures: Int) -> Duration {
        guard failures > 0 else { return .zero }
        let seconds = min(300, 1 << min(failures, 9))
        return .seconds(seconds)
    }
}
