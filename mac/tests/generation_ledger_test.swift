import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

@main
struct GenerationLedgerTests {
    static func main() {
        var ledger = StudioGenerationLedger()
        let now = Date()
        expect(ledger.reserve(requestID: "a", now: now) == .accepted,
               "a fresh paid request should reserve exactly once")
        expect(ledger.reserve(requestID: "a", now: now) == .duplicateActive,
               "a duplicated active bridge event must not create a second paid call")
        expect(ledger.reserve(requestID: "b", now: now) == .anotherRequestActive,
               "parallel paid calls should be rejected by the single-flight studio")
        ledger.finish(requestID: "a")
        expect(ledger.reserve(requestID: "a", now: now) == .requestIDReused,
               "a completed or cancelled provider ID must not be replayed")
        expect(ledger.reserve(requestID: "b", now: now) == .accepted,
               "a fresh ID should work after the prior request finishes")
        ledger.finish(requestID: "b")
        expect(ledger.reserveLocalProcessing(requestID: "a"),
               "explicit local recovery may reuse a previously paid ID")
        expect(!ledger.reserveLocalProcessing(requestID: "a"),
               "local recovery remains single-flight")
        ledger.finish(requestID: "a")
        ledger.prune(before: now.addingTimeInterval(1))
        expect(ledger.usedRequestIDs.isEmpty,
               "old ledger entries should expire without growing forever")

        let old = now.addingTimeInterval(-31 * 60)
        let recent = now.addingTimeInterval(-2 * 60)
        let drafts = ["paid-parent": old, "fresh": recent, "expired": old]
        let retained = retainingStudioDrafts(
            drafts, newerThan: now.addingTimeInterval(-30 * 60),
            pinnedIDs: ["paid-parent"], lastTouchedAt: { $0 })
        expect(Set(retained.keys) == ["paid-parent", "fresh"],
               "an active/recoverable stage must pin its paid parent across the expiry boundary")

        // A dropped completion handler used to leave activeRequestID set with
        // no expiry, refusing every later generation until the app restarted.
        var wedged = StudioGenerationLedger()
        expect(wedged.reserve(requestID: "lost", now: now) == .accepted,
               "the first request reserves")
        expect(wedged.reserve(requestID: "next", now: now.addingTimeInterval(60))
               == .anotherRequestActive,
               "a live request still blocks a parallel one")
        let afterLifetime = now.addingTimeInterval(StudioGenerationLedger.reservationLifetime + 1)
        expect(wedged.reserve(requestID: "next", now: afterLifetime) == .accepted,
               "a reservation outliving the longest request must expire, not wedge the studio")
        expect(wedged.activeRequestID == "next",
               "the expired reservation is replaced by the new one")

        // Local recovery is only meaningful while the request is still recent.
        var stale = StudioGenerationLedger()
        _ = stale.reserve(requestID: "old", now: now)
        stale.finish(requestID: "old")
        expect(!stale.reserveLocalProcessing(requestID: "old",
                                             now: now.addingTimeInterval(3600),
                                             maximumAge: 1800),
               "a request older than the recovery window is not a live candidate")
        expect(stale.reserveLocalProcessing(requestID: "old",
                                            now: now.addingTimeInterval(60),
                                            maximumAge: 1800),
               "a recent request is still recoverable locally")
        print("generation ledger tests passed")
    }
}
