// Mimo — idempotency ledger for paid image-generation requests.

import Foundation

enum StudioGenerationReservationDecision: Equatable {
    case accepted
    case duplicateActive
    case anotherRequestActive
    case requestIDReused
}

struct StudioGenerationLedger {
    /// A reservation is taken before the request goes out, and every later
    /// studio call is gated on it. If a completion handler is ever dropped the
    /// reservation has to expire on its own, or every subsequent generation is
    /// refused for the rest of the process lifetime.
    static let reservationLifetime: TimeInterval = 960

    private(set) var activeRequestID: String?
    private(set) var activeReservedAt: Date?
    private(set) var usedRequestIDs: [String: Date] = [:]

    mutating func reserve(requestID: String, now: Date = Date())
        -> StudioGenerationReservationDecision {
        releaseExpiredReservation(now: now)
        if let activeRequestID {
            return activeRequestID == requestID ? .duplicateActive : .anotherRequestActive
        }
        guard usedRequestIDs[requestID] == nil else { return .requestIDReused }
        usedRequestIDs[requestID] = now
        activeRequestID = requestID
        activeReservedAt = now
        return .accepted
    }

    mutating func finish(requestID: String) {
        if activeRequestID == requestID { activeRequestID = nil; activeReservedAt = nil }
    }

    /// Re-reserving for local reprocessing is only sensible while the request
    /// is still recent; a 24h-old ID lingering in `usedRequestIDs` is not a
    /// live recovery candidate.
    mutating func reserveLocalProcessing(requestID: String, now: Date = Date(),
                                         maximumAge: TimeInterval = 1800) -> Bool {
        releaseExpiredReservation(now: now)
        guard activeRequestID == nil, let reservedAt = usedRequestIDs[requestID],
              now.timeIntervalSince(reservedAt) <= maximumAge else { return false }
        activeRequestID = requestID
        activeReservedAt = now
        return true
    }

    /// Drops an active reservation that has outlived the longest possible
    /// request, so a lost callback cannot wedge the studio permanently.
    mutating func releaseExpiredReservation(now: Date = Date()) {
        guard activeRequestID != nil else { return }
        guard let reservedAt = activeReservedAt,
              now.timeIntervalSince(reservedAt) <= Self.reservationLifetime else {
            activeRequestID = nil
            activeReservedAt = nil
            return
        }
    }

    mutating func prune(before cutoff: Date, maximumEntries: Int = 512) {
        releaseExpiredReservation()
        usedRequestIDs = usedRequestIDs.filter {
            $0.value >= cutoff || $0.key == activeRequestID
        }
        if usedRequestIDs.count > maximumEntries {
            let removable = usedRequestIDs
                .filter { $0.key != activeRequestID }
                .sorted { $0.value < $1.value }
                .prefix(usedRequestIDs.count - maximumEntries)
                .map(\.key)
            for key in removable { usedRequestIDs.removeValue(forKey: key) }
        }
    }
}

/// A cancellation flag a background worker can read without hopping to main.
///
/// The reference preprocessor takes a synchronous `isCancelled` closure so
/// callers can pass a token check "without introducing shared mutable state".
/// Satisfying it with `DispatchQueue.main.sync` defeated that: every poll
/// stalled the worker on main-runloop latency, and any path where the main
/// thread waited on the work would deadlock.
final class StudioCancellationToken: @unchecked Sendable {
    let requestID: String
    private let lock = NSLock()
    private var cancelled = false

    init(requestID: String) { self.requestID = requestID }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

func retainingStudioDrafts<Value>(_ values: [String: Value],
                                  newerThan cutoff: Date,
                                  pinnedIDs: Set<String>,
                                  lastTouchedAt: (Value) -> Date) -> [String: Value] {
    values.filter { lastTouchedAt($0.value) >= cutoff || pinnedIDs.contains($0.key) }
}
