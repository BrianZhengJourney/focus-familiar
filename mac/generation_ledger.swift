// Mimo — idempotency ledger for paid image-generation requests.

import Foundation

enum StudioGenerationReservationDecision: Equatable {
    case accepted
    case duplicateActive
    case anotherRequestActive
    case requestIDReused
}

struct StudioGenerationLedger {
    private(set) var activeRequestID: String?
    private(set) var usedRequestIDs: [String: Date] = [:]

    mutating func reserve(requestID: String, now: Date = Date())
        -> StudioGenerationReservationDecision {
        if let activeRequestID {
            return activeRequestID == requestID ? .duplicateActive : .anotherRequestActive
        }
        guard usedRequestIDs[requestID] == nil else { return .requestIDReused }
        usedRequestIDs[requestID] = now
        activeRequestID = requestID
        return .accepted
    }

    mutating func finish(requestID: String) {
        if activeRequestID == requestID { activeRequestID = nil }
    }

    mutating func reserveLocalProcessing(requestID: String) -> Bool {
        guard activeRequestID == nil, usedRequestIDs[requestID] != nil else { return false }
        activeRequestID = requestID
        return true
    }

    mutating func prune(before cutoff: Date, maximumEntries: Int = 512) {
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

func retainingStudioDrafts<Value>(_ values: [String: Value],
                                  newerThan cutoff: Date,
                                  pinnedIDs: Set<String>,
                                  lastTouchedAt: (Value) -> Date) -> [String: Value] {
    values.filter { lastTouchedAt($0.value) >= cutoff || pinnedIDs.contains($0.key) }
}
