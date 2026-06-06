//
//  TransformationRuntimeTests.swift
//  DrPasteTests
//
//  Pure-function coverage for every transformation engine. Each test name is
//  the engine raw value so output failures point straight at the engine.
//

import XCTest
@testable import DrPaste

final class TransformationRuntimeTests: XCTestCase {

    /// Save the real locale value and pin the Cyrillic-detection locale
    /// tie-breaker OFF by default, so auto-detect assertions are deterministic
    /// regardless of the runner's system locale. tearDown restores it so a
    /// test that pins it (e.g. "serbian") can't leak into other test classes.
    private var savedLocaleCyrillicID: String??
    override func setUp() {
        super.setUp()
        savedLocaleCyrillicID = TransformationRuntime.localeCyrillicLanguageID
        TransformationRuntime.localeCyrillicLanguageID = nil
    }
    override func tearDown() {
        if let saved = savedLocaleCyrillicID {
            TransformationRuntime.localeCyrillicLanguageID = saved
        }
        super.tearDown()
    }

    // MARK: - Case engines

    func testCaseChangeUpper() throws {
        let out = try TransformationRuntime.apply(engine: .caseChange,
                                                  input: "Hello World",
                                                  params: ["case": "upper"])
        XCTAssertEqual(out, "HELLO WORLD")
    }

    func testCaseChangeLower() throws {
        let out = try TransformationRuntime.apply(engine: .caseChange,
                                                  input: "Hello World",
                                                  params: ["case": "lower"])
        XCTAssertEqual(out, "hello world")
    }

    func testCaseChangeTitle() throws {
        let out = try TransformationRuntime.apply(engine: .caseChange,
                                                  input: "hello world",
                                                  params: ["case": "title"])
        XCTAssertEqual(out, "Hello World")
    }

    func testCaseChangeSentence() throws {
        let out = try TransformationRuntime.apply(engine: .caseChange,
                                                  input: "hello WORLD. nice day",
                                                  params: ["case": "sentence"])
        XCTAssertEqual(out, "Hello world. nice day")
    }

    func testCamelCase() throws {
        let out = try TransformationRuntime.apply(engine: .camelCase,
                                                  input: "hello world foo",
                                                  params: [:])
        XCTAssertEqual(out, "helloWorldFoo")
    }

    func testSnakeCase() throws {
        let out = try TransformationRuntime.apply(engine: .snakeCase,
                                                  input: "Hello World Foo",
                                                  params: [:])
        XCTAssertEqual(out, "hello_world_foo")
    }

    func testKebabCase() throws {
        let out = try TransformationRuntime.apply(engine: .kebabCase,
                                                  input: "Hello World Foo",
                                                  params: [:])
        XCTAssertEqual(out, "hello-world-foo")
    }

    // MARK: - Whitespace / lines

    func testTrim() throws {
        let out = try TransformationRuntime.apply(engine: .trim,
                                                  input: "  line one  \n  line two  \n  \n",
                                                  params: [:])
        XCTAssertEqual(out, "line one\nline two")
    }

    func testSortLinesAscending() throws {
        let out = try TransformationRuntime.apply(engine: .sortLines,
                                                  input: "banana\napple\ncherry",
                                                  params: ["direction": "asc", "caseInsensitive": "false"])
        XCTAssertEqual(out, "apple\nbanana\ncherry")
    }

    func testSortLinesDescending() throws {
        let out = try TransformationRuntime.apply(engine: .sortLines,
                                                  input: "apple\nbanana\ncherry",
                                                  params: ["direction": "desc", "caseInsensitive": "false"])
        XCTAssertEqual(out, "cherry\nbanana\napple")
    }

    func testUniqueLinesPreservesOrder() throws {
        let out = try TransformationRuntime.apply(engine: .uniqueLines,
                                                  input: "b\na\nb\nc\na",
                                                  params: [:])
        XCTAssertEqual(out, "b\na\nc")
    }

    // MARK: - Encoding

    func testBase64EncodeDecodeRoundTrip() throws {
        let encoded = try TransformationRuntime.apply(engine: .base64Encode,
                                                     input: "Hello, world!",
                                                     params: [:])
        XCTAssertEqual(encoded, "SGVsbG8sIHdvcmxkIQ==")
        let decoded = try TransformationRuntime.apply(engine: .base64Decode,
                                                     input: encoded,
                                                     params: [:])
        XCTAssertEqual(decoded, "Hello, world!")
    }

    func testBase64DecodeInvalidThrows() {
        XCTAssertThrowsError(try TransformationRuntime.apply(engine: .base64Decode,
                                                             input: "@@@",
                                                             params: [:]))
    }

    func testURLPercentEncodeDecodeRoundTrip() throws {
        let encoded = try TransformationRuntime.apply(engine: .urlPercentEncode,
                                                      input: "hello world & friends",
                                                      params: [:])
        let decoded = try TransformationRuntime.apply(engine: .urlPercentDecode,
                                                      input: encoded,
                                                      params: [:])
        XCTAssertEqual(decoded, "hello world & friends")
    }

    // MARK: - Slug / counts

    func testSlugifyHandlesUnicode() throws {
        let out = try TransformationRuntime.apply(engine: .slugify,
                                                  input: "Hello, мир! Über  test",
                                                  params: [:])
        XCTAssertEqual(out, "hello-mir-uber-test")
    }

    func testWordCountFormats() throws {
        // "one two three\nfour five" — characters count is 23
        // (4 + 4 + 5 + 1 newline + 5 + 4).
        let out = try TransformationRuntime.apply(engine: .wordCount,
                                                  input: "one two three\nfour five",
                                                  params: [:])
        XCTAssertEqual(out, "5 words, 23 characters, 2 lines")
    }

    // MARK: - JSON

    func testJSONPretty() throws {
        let out = try TransformationRuntime.apply(engine: .jsonFormat,
                                                  input: "{\"b\":2,\"a\":1}",
                                                  params: ["operation": "pretty"])
        XCTAssertEqual(out, "{\n  \"a\" : 1,\n  \"b\" : 2\n}")
    }

    func testJSONMinify() throws {
        let out = try TransformationRuntime.apply(engine: .jsonFormat,
                                                  input: "{\n  \"a\" : 1\n}",
                                                  params: ["operation": "minify"])
        XCTAssertEqual(out, "{\"a\":1}")
    }

    func testJSONExtractKeysTopLevel() throws {
        let out = try TransformationRuntime.apply(engine: .jsonFormat,
                                                  input: "{\"name\":\"x\",\"age\":1,\"nested\":{\"deep\":true}}",
                                                  params: ["operation": "extractKeys"])
        XCTAssertEqual(out, "age\nname\nnested")
    }

    func testJSONExtractKeysRecursive() throws {
        let out = try TransformationRuntime.apply(engine: .jsonFormat,
                                                  input: "{\"name\":\"x\",\"nested\":{\"deep\":true,\"x\":[{\"item\":1}]}}",
                                                  params: ["operation": "extractKeysRecursive"])
        XCTAssertEqual(out, "deep\nitem\nname\nnested\nx")
    }

    // MARK: - Markdown

    func testMdToPlain() throws {
        let input = "# Title\n**Bold** and *italic* and `code` and [link](https://x.com)\n- item one"
        let out = try TransformationRuntime.apply(engine: .mdToPlain, input: input, params: [:])
        XCTAssertTrue(out.contains("Title"))
        XCTAssertFalse(out.contains("**"))
        XCTAssertFalse(out.contains("](https"))
        XCTAssertTrue(out.contains("link"))
    }

    func testMdExtractHeadings() throws {
        let input = "# H1\nbody\n## H2\nmore\nplain line\n### H3"
        let out = try TransformationRuntime.apply(engine: .mdExtractHeadings, input: input, params: [:])
        XCTAssertEqual(out, "# H1\n## H2\n### H3")
    }

    func testMdExtractHeadingsThrowsOnEmpty() {
        XCTAssertThrowsError(try TransformationRuntime.apply(engine: .mdExtractHeadings,
                                                             input: "no headings here",
                                                             params: [:]))
    }

    func testMdExtractLinks() throws {
        let input = "see [foo](https://foo.com) and [bar](https://bar.com)"
        let out = try TransformationRuntime.apply(engine: .mdExtractLinks, input: input, params: [:])
        XCTAssertEqual(out, "https://foo.com\nhttps://bar.com")
    }

    // MARK: - URL strip tracking

    func testURLStripTracking() throws {
        let input = "https://example.com/page?utm_source=newsletter&id=42&fbclid=xyz&utm_medium=email"
        let out = try TransformationRuntime.apply(engine: .urlStripTracking, input: input, params: [:])
        XCTAssertEqual(out, "https://example.com/page?id=42")
    }

    func testURLStripTrackingPreservesNonTracking() throws {
        let input = "https://example.com/?page=2&sort=asc"
        let out = try TransformationRuntime.apply(engine: .urlStripTracking, input: input, params: [:])
        XCTAssertEqual(out, "https://example.com/?page=2&sort=asc")
    }

    // MARK: - Regex / find/replace / wrap

    func testRegexReplace() throws {
        let out = try TransformationRuntime.apply(engine: .regexReplace,
                                                  input: "hello 123 world 456",
                                                  params: ["pattern": #"\d+"#, "replacement": "N", "caseInsensitive": "false"])
        XCTAssertEqual(out, "hello N world N")
    }

    func testRegexReplaceInvalidPatternThrows() {
        XCTAssertThrowsError(try TransformationRuntime.apply(engine: .regexReplace,
                                                             input: "x",
                                                             params: ["pattern": "[unclosed", "replacement": "y"]))
    }

    func testFindReplaceCaseInsensitive() throws {
        let out = try TransformationRuntime.apply(engine: .findReplace,
                                                  input: "Apple APPLE apple",
                                                  params: ["find": "apple", "replace": "Orange", "caseInsensitive": "true"])
        XCTAssertEqual(out, "Orange Orange Orange")
    }

    func testWrap() throws {
        let out = try TransformationRuntime.apply(engine: .wrap,
                                                  input: "code",
                                                  params: ["prefix": "```\n", "suffix": "\n```"])
        XCTAssertEqual(out, "```\ncode\n```")
    }

    func testPrepend() throws {
        let out = try TransformationRuntime.apply(engine: .prepend,
                                                  input: "world",
                                                  params: ["text": "hello "])
        XCTAssertEqual(out, "hello world")
    }

    func testAppend() throws {
        let out = try TransformationRuntime.apply(engine: .append,
                                                  input: "hello",
                                                  params: ["text": " world"])
        XCTAssertEqual(out, "hello world")
    }

    func testLineFilterKeep() throws {
        let out = try TransformationRuntime.apply(engine: .lineFilter,
                                                  input: "TODO: write tests\ndone\nTODO: ship",
                                                  params: ["pattern": "^TODO", "mode": "keep"])
        XCTAssertEqual(out, "TODO: write tests\nTODO: ship")
    }

    func testLineFilterRemove() throws {
        let out = try TransformationRuntime.apply(engine: .lineFilter,
                                                  input: "foo\nbar\nfoo bar\nbaz",
                                                  params: ["pattern": "foo", "mode": "remove"])
        XCTAssertEqual(out, "bar\nbaz")
    }

    func testLatinToCyrillicMacedonian() throws {
        // Macedonian-specific digraphs: gj→ѓ, plus shared lj/nj/dž and j→ј.
        let out = try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                  input: "Skopje Gjorgji",
                                                  params: ["target": "macedonian"])
        XCTAssertEqual(out, "Скопје Ѓорѓи")
    }

    func testLatinToCyrillicMacedonianDistinctFromSerbian() throws {
        // gj→ѓ, kj→ќ, dz→ѕ are Macedonian, not Serbian (which has ђ/ћ).
        let out = try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                  input: "gjkjdz",
                                                  params: ["target": "macedonian"])
        XCTAssertEqual(out, "ѓќѕ")
    }

    // MARK: Cyrillic → Latin auto-detection across 14 languages

    /// Each input carries a marker letter unique (or near-unique) to its
    /// language; detection must route to that language's romanization.
    func testCyrillicToLatinAutoDetectsLanguage() throws {
        let cases: [(String, String)] = [
            ("Привет мир", "Privet mir"),                  // Russian default
            ("Привіт", "Pryvit"),                          // Ukrainian (і → і/y, г→h)
            ("Қазақстан", "Qazaqstan"),                    // Kazakh (ұ/қ → q)
            ("Џек", "Džek"),                               // Serbian (џ → dž)
            ("ъгъл", "agal"),                              // Bulgarian (ъ → a)
            ("Тоҷик", "Tojik"),                            // Tajik (ҷ → j)
            ("Өнөө", "Önöö"),                              // Mongolian (ө → ö)
            ("воўк", "vowk"),                              // Belarusian (ў → w)
            ("өзүң", "özüñ"),                               // Kyrgyz/Kazakh shared (ң→ñ)
            ("җәй", "cäy"),                                // Tatar (җ → c)
            ("Ӏан", "'an"),                                // Chechen (palochka → ')
            ("Ѓорѓи", "Gjorgji"),                          // Macedonian (ѓ → gj)
            ("һәҙ", "häź"),                                // Bashkir (ҙ → ź)
            ("чӑваш", "chăvash")                           // Chuvash (ӑ → ă)
        ]
        for (input, expected) in cases {
            let out = try TransformationRuntime.apply(engine: .cyrillicToLatin,
                                                      input: input, params: [:])
            XCTAssertEqual(out, expected, "Cyrillic→Latin for \(input)")
        }
    }

    /// A word containing letters absent from Russian must never be read as
    /// Russian. «Џек» is valid only in Serbian and Macedonian → the more
    /// widely spoken Serbian wins (Cyrillic џ → dž, not left untransliterated).
    func testCyrillicDetectionExcludesImpossibleLanguage() throws {
        let out = try TransformationRuntime.apply(engine: .cyrillicToLatin,
                                                  input: "Џек", params: [:])
        XCTAssertEqual(out, "Džek")
    }

    /// Tatar's unique җ must outweigh the markers it shares with Kazakh
    /// (ә/ң/һ), even though Kazakh has higher prevalence.
    func testCyrillicDetectionUniqueMarkerBeatsPrevalence() throws {
        // "җәһәт" shares ә/һ with Kazakh but җ is Tatar-only → Tatar (җ→c, ә→ä, һ→h).
        let out = try TransformationRuntime.apply(engine: .cyrillicToLatin,
                                                  input: "җәһәт", params: [:])
        XCTAssertEqual(out, "cähät")
    }

    func testLatinToCyrillicKazakh() throws {
        let out = try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                  input: "Qazaqstan",
                                                  params: ["target": "kazakh"])
        XCTAssertEqual(out, "Қазақстан")
    }

    func testLatinToCyrillicTatar() throws {
        // c→җ, ä→ә, y→й.
        let out = try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                  input: "cäy",
                                                  params: ["target": "tatar"])
        XCTAssertEqual(out, "җәй")
    }

    /// Regression: the ICU pattern used \u{...} (Swift syntax, invalid in
    /// ICU regex), which silently disabled the whole replacement so tabs and
    /// NBSP were never normalized. Tabs must collapse to a single space.
    func testNormalizeSpacesHandlesTabsAndNBSP() throws {
        let out = try TransformationRuntime.apply(engine: .normalizeSpaces,
                                                  input: "a\t\tb \u{00A0}\u{00A0}c   d",
                                                  params: [:])
        XCTAssertEqual(out, "a b c d")
    }

    /// #A77 — when the text fits several languages equally, the user's locale
    /// breaks the tie over raw speaker count. "рим" is spellable by many; the
    /// locale decides и's romanization (Russian и→i vs Ukrainian и→y).
    func testCyrillicDetectionLocaleBreaksTie() throws {
        defer { TransformationRuntime.localeCyrillicLanguageID = nil }
        TransformationRuntime.localeCyrillicLanguageID = "russian"
        XCTAssertEqual(try TransformationRuntime.apply(engine: .cyrillicToLatin,
                                                       input: "рим", params: [:]), "rim")
        TransformationRuntime.localeCyrillicLanguageID = "ukrainian"
        XCTAssertEqual(try TransformationRuntime.apply(engine: .cyrillicToLatin,
                                                       input: "рим", params: [:]), "rym")
    }

    // MARK: Latin→Cyrillic "auto" target (characteristic letters → locale → Russian)

    func testLatinToCyrillicAutoBySerbianLetters() throws {
        // đ / ć are Serbian-specific national-Latin letters.
        XCTAssertEqual(try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                       input: "Đoković", params: ["target": "auto"]),
                       "Ђоковић")
    }

    func testLatinToCyrillicAutoByMacedonianDigraph() throws {
        XCTAssertEqual(try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                       input: "Gjorgji", params: ["target": "auto"]),
                       "Ѓорѓи")
    }

    func testLatinToCyrillicAutoByKazakhLetter() throws {
        // q is shared with Bashkir → prevalence picks Kazakh (locale pinned nil).
        XCTAssertEqual(try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                       input: "Qazaq", params: ["target": "auto"]),
                       "Қазақ")
    }

    func testLatinToCyrillicAutoFallsBackToInterslavic() throws {
        // Plain ASCII carries no language evidence; locale nil → Interslavic
        // (NOT branded Russian). No glide letters here, so it reads as plain
        // common Cyrillic.
        XCTAssertEqual(try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                       input: "Privet", params: ["target": "auto"]),
                       "Привет")
    }

    func testLatinToCyrillicAutoFallsBackToLocale() throws {
        defer { TransformationRuntime.localeCyrillicLanguageID = nil }
        TransformationRuntime.localeCyrillicLanguageID = "ukrainian"
        // No markers → locale decides: Ukrainian maps i→і.
        XCTAssertEqual(try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                       input: "Privet", params: ["target": "auto"]),
                       "Прівет")
    }

    func testLatinToCyrillicRussianHasCharacteristicLetters() throws {
        // The explicit Russian target keeps Russian-specific letters.
        XCTAssertEqual(try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                       input: "syn", params: ["target": "russian"]), "сын")     // y→ы
        XCTAssertEqual(try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                       input: "yolka", params: ["target": "russian"]), "ёлка")  // yo→ё
        XCTAssertEqual(try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                       input: "Vasil'ev", params: ["target": "russian"]), "Васильев") // '→ь
    }

    func testInterslavicSchemeUsesJotaAndDecomposedIotation() throws {
        // Interslavic: ja/ju/jo via ј (ја/ју/јо), y→и (no ы/й), shch→шч.
        let out = try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                  input: "yolka shchyo syn moj", params: ["target": "interslavic"])
        XCTAssertEqual(out, "јолка шчјо син мој")
        // The jota IS used; the opaque single letters and other languages'
        // special letters never appear.
        XCTAssertTrue(out.contains("ј"))
        let forbidden = "йяюёыэъщіїґєўљњћђџѓќѕ"
        for ch in forbidden {
            XCTAssertFalse(out.contains(ch), "Interslavic output must not contain \(ch)")
        }
    }

    // MARK: case preservation through multi-char translit

    func testCyrillicToLatinMultiCharCase() throws {
        // Щ → shch; case must apply to the whole run.
        XCTAssertEqual(try TransformationRuntime.apply(engine: .cyrillicToLatin,
                                                       input: "Щука", params: [:]), "Shchuka")
        XCTAssertEqual(try TransformationRuntime.apply(engine: .cyrillicToLatin,
                                                       input: "ЩУКА", params: [:]), "SHCHUKA")
    }

    // MARK: S7 — Bulgarian rescue is locale-independent

    func testBulgarianSignatureBeatsLocale() throws {
        defer { TransformationRuntime.localeCyrillicLanguageID = nil }
        // «дъб» fits Russian, Bulgarian, Kazakh, Tajik, … equally; a Kazakh
        // locale must NOT romanize it as Kazakh (which drops ъ → "db").
        TransformationRuntime.localeCyrillicLanguageID = "kazakh"
        XCTAssertEqual(try TransformationRuntime.apply(engine: .cyrillicToLatin,
                                                       input: "дъб", params: [:]), "dab")
        TransformationRuntime.localeCyrillicLanguageID = "ukrainian"
        XCTAssertEqual(try TransformationRuntime.apply(engine: .cyrillicToLatin,
                                                       input: "дъб", params: [:]), "dab")
    }

    // MARK: S4 — typographic apostrophe normalised

    func testRussianSmartApostrophe() throws {
        // macOS autocorrect emits U+2019; must still map to ь.
        XCTAssertEqual(try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                       input: "Vasil\u{2019}ev", params: ["target": "russian"]),
                       "Васильев")
    }

    func testUkrainianApostropheIsSoftSign() throws {
        // The apostrophe maps to ь for Ukrainian too (not only Russian),
        // straight and smart forms alike.
        XCTAssertEqual(try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                       input: "Skol'ko", params: ["target": "ukrainian"]),
                       "Сколько")
        XCTAssertEqual(try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                       input: "Skol\u{2019}ko", params: ["target": "ukrainian"]),
                       "Сколько")
    }

    // MARK: S3 — auto-target tie resolution is deterministic

    func testAutoTargetTieIsDeterministic() throws {
        // "äöü" shares ä/ö/ü across Kazakh/Tatar/Bashkir (all weight-1); the
        // result must be stable across runs (no array-order dependence).
        let a = try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                input: "äöü", params: ["target": "auto"])
        let b = try TransformationRuntime.apply(engine: .latinToCyrillic,
                                                input: "äöü", params: ["target": "auto"])
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.isEmpty)
    }
}
