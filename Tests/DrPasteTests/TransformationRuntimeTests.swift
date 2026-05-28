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
}
