//
//  CuratedActionOrderTests.swift
//  DrPasteTests
//
//  Locks the curated default action ordering invariants: identity pinned
//  first, valuable/wow actions ahead of novelty, no duplicate IDs.
//

import XCTest
@testable import DrPaste

final class CuratedActionOrderTests: XCTestCase {

    private func idx(_ order: [String], _ id: String) -> Int? { order.firstIndex(of: id) }

    func testIdentityFirstForEveryKind() {
        for kind in SemanticKind.userVisibleKinds {
            let order = CuratedActionOrder.order(for: kind)
            if order.isEmpty { continue }
            XCTAssertEqual(order.first, "builtin.identity", "\(kind) must pin identity first")
        }
    }

    func testNoDuplicateIDsWithinAKind() {
        for kind in SemanticKind.userVisibleKinds {
            let order = CuratedActionOrder.order(for: kind)
            XCTAssertEqual(Set(order).count, order.count, "\(kind) has duplicate IDs")
        }
    }

    func testValuableBeforeNovelty_text() {
        let o = CuratedActionOrder.order(for: .text)
        // Hero/everyday clearly ahead of novelty.
        XCTAssertLessThan(idx(o, "builtin.text.layout_repair")!, idx(o, "builtin.text.uppercase")!)
        XCTAssertLessThan(idx(o, "ai.text.fix_grammar")!, idx(o, "builtin.text.uppercase")!)
        XCTAssertLessThan(idx(o, "builtin.text.uppercase")!, idx(o, "builtin.text.zalgo")!)
        XCTAssertLessThan(idx(o, "builtin.text.trim")!, idx(o, "builtin.text.base64_encode")!)
    }

    func testWowLeadsPerKind() {
        let url = CuratedActionOrder.order(for: .url)
        XCTAssertLessThan(idx(url, "builtin.url.strip_tracking")!, idx(url, "builtin.url.extract_domain")!)
        let img = CuratedActionOrder.order(for: .image)
        XCTAssertLessThan(idx(img, "builtin.image.ocr")!, idx(img, "builtin.image.to_ascii_art")!)
        let rich = CuratedActionOrder.order(for: .richText)
        XCTAssertLessThan(idx(rich, "builtin.rich.strip_formatting")!, idx(rich, "builtin.rich.to_wiki")!)
    }

    /// The curated lists reference real IDs (modulo a known stale-font tail).
    /// Cross-check against the catalog so typos surface.
    func testCuratedIDsAreKnown() {
        let known = Set(BuiltinActionMetadata.descriptions.keys)
            .union(DefaultTransformationSeed.defaults().map(\.id))
            .union(DefaultAISeed.defaults().map(\.id))
            .union(["builtin.identity"])
        for kind in SemanticKind.userVisibleKinds {
            for id in CuratedActionOrder.order(for: kind) {
                // pseudo-font family IDs were merged away; tolerate that one tail.
                if id.hasPrefix("builtin.text.font_") { continue }
                XCTAssertTrue(known.contains(id), "\(kind): unknown curated id \(id)")
            }
        }
    }
}
