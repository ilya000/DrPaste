//
//  PasteCommitterTests.swift
//  DrPasteTests
//
//  #A39 (0.57.0) contract tests for the unified outcome → side-effect
//  policy table. A fake `PasteCommitterPerformer` records every call,
//  so the assertions check what the committer *would* have done
//  against the live AppDelegate at runtime.
//

import XCTest
@testable import DrPaste

@MainActor
final class PasteCommitterTests: XCTestCase {

    // MARK: Fake performer

    final class Recorder: PasteCommitterPerformer {
        var standardPastes: [String] = []      // captured previewText
        var typeSlowlyCalls: [(text: String, delay: TimeInterval, jitter: Double)] = []
        var successSounds = 0
        var failureSounds = 0
        var closeBigHUDCalls = 0

        func performStandardPaste(_ item: ClipboardItem,
                                  savedApp: NSRunningApplication?) {
            standardPastes.append(item.previewText ?? "")
        }

        func performTypeSlowly(_ item: ClipboardItem,
                               savedApp: NSRunningApplication?,
                               delay: TimeInterval,
                               jitter: Double) {
            typeSlowlyCalls.append((item.previewText ?? "", delay, jitter))
        }

        func playSuccessSound() { successSounds += 1 }
        func playFailureSound() { failureSounds += 1 }
        func closeBigHUDForSideEffect() { closeBigHUDCalls += 1 }
    }

    // MARK: Helpers

    private func makeItem(_ text: String = "hello") -> ClipboardItem {
        ClipboardItem(
            id: UUID(), semantic: .text, createdAt: Date(),
            representations: [:], typesOrdered: [],
            previewText: text, previewImageRel: nil,
            sourceBundleID: nil, sourceAppName: nil,
            sourceWindowTitle: nil, tags: []
        )
    }

    // MARK: .preview → standard paste

    func testPreviewOutcomePastesUnderStandardMode() {
        let r = Recorder()
        PasteCommitter.commit(.preview(makeItem("world")),
                              into: nil, mode: .standard, performer: r)
        XCTAssertEqual(r.standardPastes, ["world"])
        XCTAssertEqual(r.failureSounds, 0)
    }

    // MARK: .alternativeCommit dispatches by style

    func testAlternativeCommitTypeSlowlyRoutesToTypeSlowly() {
        let r = Recorder()
        PasteCommitter.commit(
            .alternativeCommit(makeItem("typed"),
                               style: .typeSlowly(delay: 0.2, jitter: 0.1)),
            into: nil, mode: .directHotkey, performer: r
        )
        XCTAssertEqual(r.typeSlowlyCalls.count, 1)
        XCTAssertEqual(r.typeSlowlyCalls[0].text, "typed")
        XCTAssertEqual(r.typeSlowlyCalls[0].delay, 0.2, accuracy: 1e-6)
        XCTAssertEqual(r.standardPastes.count, 0,
                       "Type Slowly via direct hotkey must NOT paste — that was the 0.42.x bug")
    }

    func testAlternativeCommitTypeFastUsesFastPresetDelay() {
        let r = Recorder()
        PasteCommitter.commit(
            .alternativeCommit(makeItem("fast"), style: .typeFast),
            into: nil, mode: .standard, performer: r
        )
        XCTAssertEqual(r.typeSlowlyCalls.count, 1)
        XCTAssertEqual(r.typeSlowlyCalls[0].delay, 0.05, accuracy: 1e-6)
        XCTAssertEqual(r.typeSlowlyCalls[0].jitter, 0, accuracy: 1e-6)
    }

    // MARK: .failed × mode

    func testFailedOutcomeUnderStandardPastesOriginal() {
        let r = Recorder()
        PasteCommitter.commit(
            .failed(original: makeItem("orig"), reason: "no key", recovery: nil),
            into: nil, mode: .standard, performer: r
        )
        XCTAssertEqual(r.standardPastes, ["orig"])
        XCTAssertEqual(r.failureSounds, 1)
    }

    func testFailedOutcomeUnderDirectHotkeyPlaysFailureOnly() {
        let r = Recorder()
        PasteCommitter.commit(
            .failed(original: makeItem("orig"), reason: "no key", recovery: nil),
            into: nil, mode: .directHotkey, performer: r
        )
        XCTAssertEqual(r.standardPastes, [], "direct-trigger must not paste original on failure")
        XCTAssertEqual(r.failureSounds, 1)
    }

    func testFailedOutcomeUnderDeferredAIPlaysFailureOnly() {
        let r = Recorder()
        PasteCommitter.commit(
            .failed(original: makeItem("orig"), reason: "timeout", recovery: nil),
            into: nil, mode: .deferredAI, performer: r
        )
        XCTAssertEqual(r.standardPastes, [])
        XCTAssertEqual(r.failureSounds, 1)
    }

    // MARK: .sideEffect × mode

    func testSideEffectKeepingHUDOpenClosesHUDBeforePerforming() {
        let r = Recorder()
        var performerRan = false
        PasteCommitter.commit(
            .sideEffect(description: "open url", perform: { performerRan = true }),
            into: nil, mode: .keepingHUDOpen, performer: r
        )
        XCTAssertEqual(r.closeBigHUDCalls, 1)
        XCTAssertTrue(performerRan)
        XCTAssertEqual(r.successSounds, 1)
    }

    func testSideEffectStandardDoesNotForceCloseAgain() {
        // `.standard` leaves close handling to the caller; the
        // committer must not also close (would double-close).
        let r = Recorder()
        var performerRan = false
        PasteCommitter.commit(
            .sideEffect(description: "reveal", perform: { performerRan = true }),
            into: nil, mode: .standard, performer: r
        )
        XCTAssertEqual(r.closeBigHUDCalls, 0)
        XCTAssertTrue(performerRan)
        XCTAssertEqual(r.successSounds, 1)
    }

    // MARK: .previewOnly rejects every escape attempt

    func testPreviewOnlyAllowsPreviewOutcome() {
        let r = Recorder()
        let result = PasteCommitter.commit(
            .preview(makeItem("safe")),
            into: nil, mode: .previewOnly, performer: r
        )
        XCTAssertEqual(result, .committed)
        XCTAssertEqual(r.standardPastes, [],
                       "preview-only must never write to the system pasteboard")
    }

    func testPreviewOnlyRejectsSideEffect() {
        let r = Recorder()
        var performerRan = false
        let result = PasteCommitter.commit(
            .sideEffect(description: "open url", perform: { performerRan = true }),
            into: nil, mode: .previewOnly, performer: r
        )
        if case .skipped(let reason) = result {
            XCTAssertTrue(reason.contains("Side effect"))
        } else {
            XCTFail("preview-only must reject side-effect outcomes")
        }
        XCTAssertFalse(performerRan, "side-effect block must NOT run from playground")
        XCTAssertEqual(r.successSounds, 0)
    }

    func testPreviewOnlyRejectsAlternativeCommit() {
        let r = Recorder()
        let result = PasteCommitter.commit(
            .alternativeCommit(makeItem("typed"),
                               style: .typeSlowly(delay: 0.2, jitter: 0.1)),
            into: nil, mode: .previewOnly, performer: r
        )
        if case .skipped = result {
            // good
        } else {
            XCTFail("preview-only must reject alternativeCommit")
        }
        XCTAssertEqual(r.typeSlowlyCalls.count, 0)
    }
}
