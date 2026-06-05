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

    func testUngatedActionStillApplies() {
        let action = gatedAction(required: [])
        let any = item("whatever")
        XCTAssertTrue(action.isApplicable(item: any, context: ContextDetector.detect(any)))
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

    func testEmailLikeMapsToEmailKind() {
        let action = gatedAction(required: ["emailLike"])
        let email = ClipboardItem(id: UUID(), semantic: .email, createdAt: Date(),
                                  representations: [:], typesOrdered: [],
                                  previewText: "From: a@b.com\nSubject: hi",
                                  previewImageRel: nil, sourceBundleID: nil,
                                  sourceAppName: nil, sourceWindowTitle: nil, tags: [])
        let plain = item("just text")
        XCTAssertTrue(action.isApplicable(item: email, context: ContextDetector.detect(email)))
        XCTAssertFalse(action.isApplicable(item: plain, context: ContextDetector.detect(plain)))
    }
}
