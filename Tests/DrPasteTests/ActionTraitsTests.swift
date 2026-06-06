//
//  ActionTraitsTests.swift
//  DrPasteTests
//
//  #A75 Slice 2 — trait gating rule + end-to-end descriptor filtering.
//

import XCTest
@testable import DrPaste

final class ActionTraitsTests: XCTestCase {

    // MARK: passes() rule

    func testEmptyRequiredAlwaysPasses() {
        XCTAssertTrue(ActionTrait.passes(required: [], forbidden: [], in: ContentContext()))
    }

    func testRequiredIsOR() {
        let ctx: ContentContext = [.plain, .containsURLs]
        // Present via one of the two → pass.
        XCTAssertTrue(ActionTrait.passes(required: ["containsEmails", "containsURLs"],
                                         forbidden: [], in: ctx))
        // Neither present → fail.
        XCTAssertFalse(ActionTrait.passes(required: ["containsEmails", "uppercaseHeavy"],
                                          forbidden: [], in: ctx))
    }

    func testForbiddenBlocks() {
        let ctx: ContentContext = [.plain, .containsCyrillic]
        XCTAssertFalse(ActionTrait.passes(required: ["containsLatin"],
                                          forbidden: ["containsCyrillic"],
                                          in: [.plain, .containsLatin, .containsCyrillic]))
        XCTAssertTrue(ActionTrait.passes(required: [],
                                         forbidden: ["containsCyrillic"],
                                         in: [.plain, .containsLatin]))
        _ = ctx
    }

    func testUnknownKeysAreIgnoredNotHiding() {
        // A stale/unknown required key must NOT hide the action — if it's the
        // only required key it's dropped, leaving "no constraint" → pass.
        XCTAssertTrue(ActionTrait.passes(required: ["someRetiredTrait"],
                                         forbidden: [], in: ContentContext()))
    }

    func testUnknownForbiddenKeyFailsOpen() {
        // An unknown forbidden key must never block (it's dropped).
        XCTAssertTrue(ActionTrait.passes(required: [], forbidden: ["someRetiredTrait"],
                                         in: [.plain, .containsLatin]))
    }

    func testKnownAndUnknownRequiredMixEnforcesKnown() {
        let ctx: ContentContext = [.plain]  // no URLs
        // Unknown key dropped, known "containsURLs" still required → fail.
        XCTAssertFalse(ActionTrait.passes(required: ["bogus", "containsURLs"],
                                          forbidden: [], in: ctx))
        XCTAssertTrue(ActionTrait.passes(required: ["bogus", "containsURLs"],
                                         forbidden: [], in: [.plain, .containsURLs]))
    }

    // MARK: end-to-end through a descriptor + ContextDetector

    private func item(_ text: String) -> ClipboardItem {
        ClipboardItem(id: UUID(), semantic: .text, createdAt: Date(),
                      representations: [:], typesOrdered: [], previewText: text,
                      previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
                      sourceWindowTitle: nil, tags: [])
    }

    private func gatedAction(required: [String], forbidden: [String] = []) -> CustomTransformationAction {
        let desc = CustomTransformationDescriptor(
            id: "user.transform.test", title: "Test",
            engineID: TransformationEngine.trim.rawValue,
            parameters: [:], applicableTypes: ["text"], enabled: true,
            requiredTraits: required, forbiddenTraits: forbidden)
        return CustomTransformationAction(id: desc.id, title: desc.title,
                                          descriptor: desc, applicableSet: [.text])
    }

    func testActionGatedByContainsEmails() {
        let action = gatedAction(required: ["containsEmails"])
        let withEmail = item("ping me at a@b.com")
        let without = item("no address here")
        XCTAssertTrue(action.isApplicable(item: withEmail, context: ContextDetector.detect(withEmail)))
        XCTAssertFalse(action.isApplicable(item: without, context: ContextDetector.detect(without)))
    }

    func testLatinToCyrillicGateExcludesCyrillicText() {
        // required containsLatin, forbidden containsCyrillic — mirrors the
        // built-in latin→cyrillic gate.
        let action = gatedAction(required: ["containsLatin"], forbidden: ["containsCyrillic"])
        let latin = item("Privet")
        let cyrillic = item("Привет")
        XCTAssertTrue(action.isApplicable(item: latin, context: ContextDetector.detect(latin)))
        XCTAssertFalse(action.isApplicable(item: cyrillic, context: ContextDetector.detect(cyrillic)))
    }

    /// The Settings list uses `appliesToContentType`, which ignores trait
    /// conditions — so a trait-gated action stays in the list even when the
    /// current sample doesn't match the condition (otherwise it would vanish on
    /// save and become unfindable). `isApplicable` still honours the gate.
    func testAppliesToContentTypeIgnoresTraitGate() {
        let action = gatedAction(required: ["containsEmails"])
        let noEmail = item("plain note with no address")
        let ctx = ContextDetector.detect(noEmail)
        XCTAssertFalse(action.isApplicable(item: noEmail, context: ctx),
                       "HUD gate should hide it (no email in sample)")
        XCTAssertTrue(action.appliesToContentType(item: noEmail, context: ctx),
                      "Settings list must still include it (type matches)")
    }

    func testUngatedActionStillApplies() {
        let action = gatedAction(required: [])
        let any = item("whatever")
        XCTAssertTrue(action.isApplicable(item: any, context: ContextDetector.detect(any)))
    }

    /// "Applies to" is strict: an action with applicableSet [.text] must NOT
    /// leak into JSON/URL/etc. clips (or their Settings tabs) via the old
    /// `.plain` fallback — but a rich-text clip still surfaces text actions.
    func testAppliesToStrictExceptRichText() {
        func mk(_ k: SemanticKind) -> ClipboardItem {
            ClipboardItem(id: UUID(), semantic: k, createdAt: Date(),
                          representations: [:], typesOrdered: [], previewText: "x",
                          previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
                          sourceWindowTitle: nil, tags: [])
        }
        let action = gatedAction(required: [])  // applicableSet = [.text]
        for kind in [SemanticKind.text, .richText] {
            let i = mk(kind)
            XCTAssertTrue(action.isApplicable(item: i, context: ContextDetector.detect(i)),
                          "[text] action should apply to \(kind)")
        }
        for kind in [SemanticKind.json, .url, .table, .code] {
            let i = mk(kind)
            XCTAssertFalse(action.isApplicable(item: i, context: ContextDetector.detect(i)),
                           "[text] action must NOT leak into \(kind)")
        }
    }

    // MARK: provenance (fromOCR) + AI-path gating

    private func ocrItem(_ text: String) -> ClipboardItem {
        ClipboardItem(id: UUID(), semantic: .text, createdAt: Date(),
                      representations: [:], typesOrdered: [], previewText: text,
                      previewImageRel: nil, sourceBundleID: nil, sourceAppName: nil,
                      sourceWindowTitle: nil, tags: [ContextDetector.ocrProvenanceTag])
    }

    func testFromOCRDetectedFromTag() {
        XCTAssertTrue(ContextDetector.detect(ocrItem("scanned")).contains(.fromOCR))
        XCTAssertFalse(ContextDetector.detect(item("typed")).contains(.fromOCR))
    }

    func testAIActionGatedByFromOCR() {
        let clean = AIAction(id: "ai.text.clean_ocr", title: "Clean OCR",
                             promptTemplate: "...", providerID: nil,
                             applicableTypes: [.text], requiredTraits: ["fromOCR"])
        let ocr = ocrItem("raw  ocr\ntext")
        let typed = item("normal text")
        XCTAssertTrue(clean.isApplicable(item: ocr, context: ContextDetector.detect(ocr)))
        XCTAssertFalse(clean.isApplicable(item: typed, context: ContextDetector.detect(typed)))
    }

    /// S1 fix: email actions gate on `containsEmails` (text that contains an
    /// address), so they surface on a pasted email BODY — a plain-`.text`
    /// clip — not only on a bare `.email`-semantic address. The retired
    /// `emailLike` trait fired only on the whole-clip `.email` kind and so
    /// never appeared on real email content.
    func testEmailActionsGateOnContainsEmails() {
        let action = gatedAction(required: ["containsEmails"])
        let body = item("Hi, ping me back at john.doe@example.com — thanks!")  // .text body
        let plain = item("just a plain note with no address")
        XCTAssertTrue(action.isApplicable(item: body, context: ContextDetector.detect(body)))
        XCTAssertFalse(action.isApplicable(item: plain, context: ContextDetector.detect(plain)))
    }

    func testRetiredEmailLikeKeyFailsOpen() {
        // "emailLike" no longer exists in the vocabulary; a descriptor still
        // referencing it must fail OPEN (unknown key ignored), never hide.
        let action = gatedAction(required: ["emailLike"])
        let any = item("whatever")
        XCTAssertTrue(action.isApplicable(item: any, context: ContextDetector.detect(any)))
    }
}
