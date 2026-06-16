//
//  PersistenceDebouncerTests.swift
//  DrPasteTests
//
//  #A46 (0.57.0) contract tests for the shared 200 ms-debounced
//  saver. Verifies that:
//    - rapid `schedule` calls coalesce into one write,
//    - the writer eventually fires,
//    - `flushSync` runs the queued writer immediately.
//

import XCTest
@testable import DrPaste

final class PersistenceDebouncerTests: XCTestCase {

    func testRapidScheduleCallsCoalesceIntoOneWrite() async throws {
        let debouncer = PersistenceDebouncer(label: "test-coalesce", interval: 0.05)
        var fireCount = 0
        let counterQueue = DispatchQueue(label: "drpaste.tests.persistence.counter")

        for i in 0..<10 {
            debouncer.schedule {
                counterQueue.sync { fireCount += 1 }
                _ = i  // silence unused-i warning
            }
        }

        // Wait past the debounce window plus a small queue-hop buffer.
        try await Task.sleep(nanoseconds: 250_000_000)

        let final = counterQueue.sync { fireCount }
        XCTAssertEqual(final, 1, "expected exactly one write after coalescing 10 rapid schedule calls")
    }

    func testFlushSyncRunsPendingWriterImmediately() {
        let debouncer = PersistenceDebouncer(label: "test-flush", interval: 5)
        var didFire = false
        debouncer.schedule { didFire = true }
        XCTAssertFalse(didFire, "writer should not fire synchronously when scheduled")
        debouncer.flushSync()
        XCTAssertTrue(didFire, "flushSync must run the pending writer")
        XCTAssertFalse(debouncer.hasPendingWrite)
    }

    func testFlushSyncWithoutPendingWriterIsNoOp() {
        let debouncer = PersistenceDebouncer(label: "test-empty-flush", interval: 0.1)
        // Doesn't crash; just returns.
        debouncer.flushSync()
        XCTAssertFalse(debouncer.hasPendingWrite)
    }
}
