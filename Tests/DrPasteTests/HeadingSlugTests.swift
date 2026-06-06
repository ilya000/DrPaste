//
//  HeadingSlugTests.swift
//  DrPasteTests
//
//  The User Guide's Table-of-contents links are GitHub-style `#anchor` slugs.
//  `headingSlug` must reproduce them exactly so a click scrolls to the heading
//  instead of being handed to NSWorkspace (which fails with "can't be opened −50").
//

import XCTest
@testable import DrPaste

final class HeadingSlugTests: XCTestCase {

    @MainActor
    func testMatchesHelpTOCAnchors() {
        let cases: [(heading: String, anchor: String)] = [
            ("What it is and why",                       "what-it-is-and-why"),
            ("Smart, context-aware actions",             "smart-context-aware-actions"),
            ("Installation and permissions",             "installation-and-permissions"),
            ("The main gesture: ⌥⌘V",                    "the-main-gesture-v"),
            ("Two modes: Gesture vs Limited",            "two-modes-gesture-vs-limited"),
            ("Inside the HUD",                           "inside-the-hud"),
            ("AI providers",                             "ai-providers"),
            ("Cyrillic transliteration — 14 languages",  "cyrillic-transliteration--14-languages"),
            ("⌥⌘S Append Copy — merging clips",          "s-append-copy--merging-clips"),
            ("Region Capture — screen-region screenshots", "region-capture--screen-region-screenshots"),
        ]
        for c in cases {
            XCTAssertEqual(UserGuideWindowController.headingSlug(c.heading), c.anchor,
                           "slug mismatch for \"\(c.heading)\"")
        }
    }
}
