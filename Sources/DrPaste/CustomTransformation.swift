//
//  CustomTransformation.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Engine architecture for transformation actions. Originally introduced for
//  user-defined transformations; now also hosts the bundled built-ins seeded
//  via DefaultTransformationSeed (UPPERCASE, sort lines, base64, slugify,
//  json pretty, markdown extraction, etc.). The engine + descriptor pair lets
//  users rename, retitle, reorder, change parameters, or fully delete any
//  transformation — built-in or user-created — through a single edit surface.
//

import Foundation

// MARK: - Engine IDs

enum TransformationEngine: String, Codable, CaseIterable, Identifiable {
    case regexReplace      = "regex_replace"
    case findReplace       = "find_replace"
    case prepend           = "prepend"
    case append            = "append"
    case wrap              = "wrap"
    case lineFilter        = "line_filter"
    case caseChange        = "case_change"          // upper / lower / title / sentence
    case sortLines         = "sort_lines"           // asc / desc, case-insensitive flag
    case uniqueLines       = "unique_lines"
    case jsonFormat        = "json_format"          // pretty / minify / extractKeys / extractKeysRecursive
    case trim              = "trim"                 // strip each line + outer whitespace
    case camelCase         = "camel_case"
    case snakeCase         = "snake_case"
    case kebabCase         = "kebab_case"
    case base64Encode      = "base64_encode"
    case base64Decode      = "base64_decode"
    case urlPercentEncode  = "url_percent_encode"
    case urlPercentDecode  = "url_percent_decode"
    case slugify           = "slugify"
    case wordCount         = "word_count"
    case mdToPlain         = "md_to_plain"
    case mdExtractHeadings = "md_extract_headings"
    case mdExtractLinks    = "md_extract_links"
    case urlStripTracking  = "url_strip_tracking"
    case unicodeStyle      = "unicode_style"        // style: bold/italic/script/...
    case cyrillicToLatin   = "cyrillic_to_latin"    // auto-detects 14 langs by markers+prevalence
    case latinToCyrillic   = "latin_to_cyrillic"    // target: one of 14 langs (see cyrillicLangs)
    case prettyCodeLocal   = "pretty_code_local"    // JSON / XML / HTML / CSS / generic
    case leetspeak         = "leetspeak"            // a→4 e→3 ... aggressive flag
    case uwuSpeak          = "uwu_speak"            // r/l→w, n+vowel→ny+vowel, face injection
    case zalgo             = "zalgo"                // combining-mark corruption

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regexReplace:      return "Regex replace"
        case .findReplace:       return "Find and replace"
        case .prepend:           return "Prepend text"
        case .append:            return "Append text"
        case .wrap:              return "Wrap with prefix/suffix"
        case .lineFilter:        return "Filter lines"
        case .caseChange:        return "Change case"
        case .sortLines:         return "Sort lines"
        case .uniqueLines:       return "Unique lines"
        case .jsonFormat:        return "Format JSON"
        case .trim:              return "Trim whitespace"
        case .camelCase:         return "camelCase"
        case .snakeCase:         return "snake_case"
        case .kebabCase:         return "kebab-case"
        case .base64Encode:      return "Base64 encode"
        case .base64Decode:      return "Base64 decode"
        case .urlPercentEncode:  return "URL percent-encode"
        case .urlPercentDecode:  return "URL percent-decode"
        case .slugify:           return "Slugify"
        case .wordCount:         return "Word / char count"
        case .mdToPlain:         return "Markdown → plain"
        case .mdExtractHeadings: return "Extract Markdown headings"
        case .mdExtractLinks:    return "Extract Markdown links"
        case .urlStripTracking:  return "Strip URL tracking params"
        case .unicodeStyle:      return "Stylize (Unicode font)"
        case .cyrillicToLatin:   return "Cyrillic → Latin transliteration"
        case .latinToCyrillic:   return "Latin → Cyrillic transliteration"
        case .prettyCodeLocal:   return "Pretty Code (local)"
        case .leetspeak:         return "Leetspeak / 1337"
        case .uwuSpeak:          return "UwU speech"
        case .zalgo:             return "Zalgo corruption"
        }
    }

    var iconName: String {
        switch self {
        case .regexReplace:      return "function"
        case .findReplace:       return "magnifyingglass"
        case .prepend:           return "text.append"
        case .append:            return "text.insert"
        case .wrap:              return "text.quote"
        case .lineFilter:        return "line.horizontal.3.decrease"
        case .caseChange:        return "textformat"
        case .sortLines:         return "arrow.up.arrow.down"
        case .uniqueLines:       return "line.3.horizontal.decrease.circle"
        case .jsonFormat:        return "curlybraces"
        case .trim:              return "scissors"
        case .camelCase:         return "textformat.alt"
        case .snakeCase:         return "textformat.alt"
        case .kebabCase:         return "textformat.alt"
        case .base64Encode:      return "lock.shield"
        case .base64Decode:      return "lock.open"
        case .urlPercentEncode:  return "percent"
        case .urlPercentDecode:  return "percent"
        case .slugify:           return "link"
        case .wordCount:         return "number"
        case .mdToPlain:         return "doc.plaintext"
        case .mdExtractHeadings: return "list.bullet.indent"
        case .mdExtractLinks:    return "link"
        case .urlStripTracking:  return "shield.lefthalf.filled"
        case .unicodeStyle:      return "textformat"
        case .cyrillicToLatin:   return "character.book.closed"
        case .latinToCyrillic:   return "character.book.closed.fill"
        case .prettyCodeLocal:   return "curlybraces.square"
        case .leetspeak:         return "number.square"
        case .uwuSpeak:          return "face.smiling"
        case .zalgo:             return "tornado"
        }
    }

    var description: String {
        switch self {
        case .regexReplace:
            return "Replace text matching a regular expression pattern with a replacement string. Supports capture groups ($1, $2)."
        case .findReplace:
            return "Replace occurrences of a literal string with another. Case-sensitive by default."
        case .prepend:
            return "Add text at the beginning of the clipboard content."
        case .append:
            return "Add text at the end of the clipboard content."
        case .wrap:
            return "Surround the text with a prefix and suffix (e.g. quotes, brackets, code fences)."
        case .lineFilter:
            return "Keep or remove lines matching a pattern."
        case .caseChange:
            return "Change text case: upper, lower, Title Case, or Sentence case."
        case .sortLines:
            return "Sort lines alphabetically, ascending or descending. Optional case-insensitive."
        case .uniqueLines:
            return "Remove duplicate lines while preserving order."
        case .jsonFormat:
            return "Format JSON: pretty-print, minify, extract top-level keys, or extract every key recursively."
        case .trim:
            return "Strip whitespace from each line and from the start/end of the text."
        case .camelCase:
            return "Convert text to camelCase by joining word boundaries and lowercasing the first word."
        case .snakeCase:
            return "Convert text to snake_case by joining word boundaries with underscores."
        case .kebabCase:
            return "Convert text to kebab-case by joining word boundaries with hyphens."
        case .base64Encode:
            return "Encode the UTF-8 representation of the text as a Base64 string."
        case .base64Decode:
            return "Decode a Base64 string back to UTF-8 text."
        case .urlPercentEncode:
            return "Percent-encode characters that are not safe in URL paths."
        case .urlPercentDecode:
            return "Reverse percent-encoding in a URL or URL-encoded fragment."
        case .slugify:
            return "Produce a URL-safe slug: lowercase, ASCII transliteration, hyphen-separated words."
        case .wordCount:
            return "Replace the content with a short summary: N words, N characters, N lines."
        case .mdToPlain:
            return "Strip Markdown markers (headings, bold, italic, code, links) and produce plain text."
        case .mdExtractHeadings:
            return "Keep only lines that start with one or more #, in source order."
        case .mdExtractLinks:
            return "Extract every URL referenced by an inline Markdown link, one per line."
        case .urlStripTracking:
            return "Drop common tracking query parameters (utm_*, fbclid, gclid, igshid, ref, _ga, etc.)."
        case .unicodeStyle:
            return "Convert ASCII letters and digits into a stylized Unicode pseudo-font (Bold, Italic, Script, Fraktur, Double-struck, Monospace, Fullwidth, Small Caps, Circled, Upside-down, etc.). Plain reverses any styled input back to ASCII."
        case .cyrillicToLatin:
            return "Transliterate Cyrillic to Latin across 14 languages (Russian, Ukrainian, Kazakh, Serbian, Bulgarian, Tajik, Mongolian, Belarusian, Kyrgyz, Tatar, Chechen, Macedonian, Bashkir, Chuvash), each with its national/common romanization. Auto-detects the language by alphabet fit — a language whose alphabet can't spell a letter in the text is ruled out (ї/є/ґ → Ukrainian, ұ/қ/ә → Kazakh, ҷ/ӣ/ӯ → Tajik, җ → Tatar, ҙ/ҡ → Bashkir, ӑ/ӗ/ӳ → Chuvash, ӏ → Chechen, ћ/ђ/џ → Serbian, ѓ/ќ/ѕ → Macedonian, ў → Belarusian, ъ without ы/э/ё → Bulgarian, …), breaking ties toward the more widely spoken language. Preserves word case (Привет→Privet, ПРИВЕТ→PRIVET). Useful for URL slugs, name romanization, and chaining into Unicode pseudo-font styling."
        case .latinToCyrillic:
            return "Reverse-transliterate Latin to Cyrillic for a chosen target language (14 supported: Russian default, Ukrainian, Kazakh, Serbian, Bulgarian, Tajik, Mongolian, Belarusian, Kyrgyz, Tatar, Chechen, Macedonian, Bashkir, Chuvash). Recognizes digraphs (zh→ж, ch→ч, sh→ш, shch→щ, gj→ѓ, …) and the national Latin's diacritic letters (ä→ә, ö→ө, ü→ү, ñ→ң, …), falling back to a single-letter map. Preserves case (Privet→Привет, PRIVET→ПРИВЕТ). Deterministic and offline."
        case .prettyCodeLocal:
            return "Deterministic code reformatter. Auto-detects format by leading characters: { / [ → JSON via JSONSerialization (.prettyPrinted + .sortedKeys); <?xml → XMLDocument .nodePrettyPrint; <!DOCTYPE / <html → HTML reflow (newlines after tags, tag-depth indent, collapse multi-space); selector + { → CSS (newline after ;, indent rule body 2 spaces); otherwise generic whitespace normalization (trim trailing whitespace, collapse 3+ blank lines, tabs → 4 spaces, normalize LF). Fully offline, sub-50 ms for typical sizes. AI Pretty Code is a separate action for arbitrary languages with idiomatic style."
        case .leetspeak:
            return "Convert text to 1337 leetspeak by substituting common letters with digits: a→4, e→3, i→1, o→0, s→5, t→7. With Aggressive mode also maps l→1, g→9, b→8. Useful for nostalgia, themed posts, and screenshot-able internet humor."
        case .uwuSpeak:
            return "Convert text to UwU speech: r and l become w (preserving case), n followed by a vowel becomes ny+vowel, hops, and faces (UwU / OwO / nya~) inject after sentence-ending punctuation when Faces is on. Idempotent-ish — re-running compounds the cuteness rather than mangling the text."
        case .zalgo:
            return "Corrupt text with overlapping Unicode combining marks (the \"Zalgo\" effect). Intensity parameter controls density: Light adds 1 mark above and 1 below per character; Medium adds up to 3 above, 3 below, 1 middle; Heavy adds up to 8 above, 8 below, 2 middle. Whitespace stays clean. Use sparingly — heavy Zalgo breaks line wrapping in some apps."
        }
    }

    var defaultParameters: [String: String] {
        switch self {
        case .regexReplace: return ["pattern": "", "replacement": "", "caseInsensitive": "false"]
        case .findReplace:  return ["find": "", "replace": "", "caseInsensitive": "false"]
        case .prepend:      return ["text": ""]
        case .append:       return ["text": ""]
        case .wrap:         return ["prefix": "", "suffix": ""]
        case .lineFilter:   return ["pattern": "", "mode": "keep"]
        case .caseChange:   return ["case": "upper"]
        case .sortLines:    return ["direction": "asc", "caseInsensitive": "false"]
        case .uniqueLines:  return [:]
        case .jsonFormat:   return ["operation": "pretty"]
        case .unicodeStyle: return ["style": UnicodeFontStyle.bold.rawValue]
        case .latinToCyrillic: return ["target": "russian"]
        case .leetspeak:    return ["aggressive": "false"]
        case .uwuSpeak:     return ["faces": "true"]
        case .zalgo:        return ["intensity": "medium"]
        case .trim,
             .camelCase, .snakeCase, .kebabCase,
             .base64Encode, .base64Decode,
             .urlPercentEncode, .urlPercentDecode,
             .slugify, .wordCount,
             .mdToPlain, .mdExtractHeadings, .mdExtractLinks,
             .urlStripTracking,
             .cyrillicToLatin,
             .prettyCodeLocal:
            return [:]
        }
    }

    /// True if this engine is a useful composable building block when the user
    /// creates a brand-new custom transformation. False for parameter-less
    /// "recipe" engines that exist solely to back a specific bundled built-in
    /// (camelCase, slugify, Markdown extract, Strip URL tracking, etc.) — they
    /// already appear as ready-to-use actions in the Actions list, so showing
    /// them again in the engine picker would just clutter the menu.
    ///
    /// Note: engines flagged `false` still run normally and remain editable
    /// when the user opens an existing built-in for editing — only the engine
    /// **picker for new transformations** filters by this flag.
    var userPickable: Bool {
        switch self {
        case .regexReplace, .findReplace, .prepend, .append, .wrap, .lineFilter,
             .caseChange, .sortLines, .uniqueLines, .jsonFormat, .unicodeStyle:
            return true
        case .trim,
             .camelCase, .snakeCase, .kebabCase,
             .base64Encode, .base64Decode,
             .urlPercentEncode, .urlPercentDecode,
             .slugify, .wordCount,
             .mdToPlain, .mdExtractHeadings, .mdExtractLinks,
             .urlStripTracking,
             .cyrillicToLatin,
             .latinToCyrillic,
             .prettyCodeLocal,
             .leetspeak, .uwuSpeak, .zalgo:
            return false
        }
    }

    /// True when applying this engine to rich-text input via the
    /// per-attributed-run path produces the right answer — i.e. when
    /// the transformation is character-local (caseChange, unicodeStyle,
    /// cyrillicToLatin) OR edge-local in a way the runtime handles
    /// specially (trim, wrap, prepend, append). For these engines
    /// `CustomTransformationAction.apply` takes the formatting-
    /// preserving branch: bold / italic / colour / hyperlink markup
    /// from the source clip survives into the result.
    ///
    /// Engines flagged false restructure the text (sortLines drops or
    /// reorders runs; jsonFormat reflows; slugify / camelCase / snake
    /// / kebab strip whitespace; base64 / url encode produces unrelated
    /// output; mdToPlain / mdExtract* extract subsets; lineFilter
    /// drops lines; regex / findReplace match across run boundaries
    /// unreliably; wordCount outputs statistics). Those keep the
    /// plain-text path — the result is always plain text by design.
    var preservesRichTextFormatting: Bool {
        switch self {
        case .caseChange, .unicodeStyle, .cyrillicToLatin, .latinToCyrillic,
             .leetspeak, .uwuSpeak,
             .trim, .wrap, .prepend, .append:
            return true
        case .regexReplace, .findReplace, .lineFilter,
             .sortLines, .uniqueLines, .jsonFormat,
             .camelCase, .snakeCase, .kebabCase,
             .base64Encode, .base64Decode,
             .urlPercentEncode, .urlPercentDecode,
             .slugify, .wordCount,
             .mdToPlain, .mdExtractHeadings, .mdExtractLinks,
             .urlStripTracking,
             .prettyCodeLocal,
             // Zalgo restructures the visual layout — combining marks
             // multiply char counts and per-attributed-run application
             // would visually misalign the marks with their base chars.
             // Keep the plain-text path.
             .zalgo:
            return false
        }
    }
}

// MARK: - Descriptor

struct CustomTransformationDescriptor: Codable, Identifiable, Equatable {
    var id: String                           // "user.transform.<slug>"
    var title: String
    var engineID: String                     // TransformationEngine.rawValue
    var parameters: [String: String]
    var applicableTypes: [String]            // SemanticKind.rawValue list
    var enabled: Bool = true

    var engine: TransformationEngine? {
        TransformationEngine(rawValue: engineID)
    }
}

// MARK: - Runtime action

/// ClipboardAction wrapper for a CustomTransformationDescriptor.
/// Instantiated by ActionRegistry.rebuildCustomTransformations().
struct CustomTransformationAction: ClipboardAction {
    let id: String
    let title: String
    let isLocal: Bool = true
    let descriptor: CustomTransformationDescriptor
    let applicableSet: Set<SemanticKind>

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        applicableSet.contains(item.semantic) || context.contains(.plain)
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        guard let engine = descriptor.engine else {
            return .failed(original: item, reason: "Unknown engine: \(descriptor.engineID)", recovery: nil)
        }
        // Rich-text input + an engine that preserves formatting per
        // attributed run → take the formatting-preserving path. Without
        // this, uppercase / unicodeStyle / cyrillicTranslit / trim /
        // wrap / etc. would flatten any rich-text input to plain text
        // (item.previewText) and discard the user's bold / italic /
        // colour / hyperlink markup. Engines that restructure the text
        // (sortLines, jsonFormat, slugify, snake_case, base64, …) keep
        // the plain-text path because per-run application is
        // semantically wrong for them.
        if item.semantic == .richText,
           engine.preservesRichTextFormatting,
           let rel = item.representations["public.rtf"] ?? item.representations["com.apple.flat-rtfd"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: rel.hasSuffix(".rtfd") || rel.contains("rtfd")
                    ? NSAttributedString.DocumentType.rtfd
                    : NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
           ) {
            do {
                let transformed = try TransformationRuntime.applyToAttributed(
                    engine: engine,
                    input: attr,
                    params: descriptor.parameters
                )
                return .preview(makeRichTextItem(transformed, from: item))
            } catch let TransformationError.invalidRegex(msg) {
                return .failed(original: item, reason: "Invalid regex: \(msg)", recovery: nil)
            } catch {
                return .failed(original: item, reason: error.localizedDescription, recovery: nil)
            }
        }
        // Plain-text path — original behaviour. Engines that don't
        // preserve formatting always come through here.
        //
        // Rich-text input special-case for markdown-extract engines.
        // mdExtractHeadings / mdExtractLinks scan their input for
        // markdown markup (`## …`, `[label](url)`). For a `.richText`
        // clip, `previewText` is the rendered string with markup
        // stripped — so the extractors find nothing. Recover the
        // markdown source by converting the RTF/RTFD attributed string
        // back to markdown via `RichTextHelpers`, then feed THAT to
        // the engine. Without this, a Rich-text email with hyperlinks
        // returns "no links found" even though the formatting clearly
        // showed several. Same logic for headings.
        var input = item.previewText ?? ""
        if item.semantic == .richText,
           engine == .mdExtractHeadings || engine == .mdExtractLinks,
           let rel = item.representations["public.rtf"] ?? item.representations["com.apple.flat-rtfd"],
           let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
           let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: rel.hasSuffix(".rtfd") || rel.contains("rtfd")
                    ? NSAttributedString.DocumentType.rtfd
                    : NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
           ),
           let md = RichTextHelpers.attributedStringToMarkdown(attr) {
            input = md
        }
        do {
            let result = try TransformationRuntime.apply(engine: engine,
                                                          input: input,
                                                          params: descriptor.parameters)
            return .preview(makeTextItem(result, from: item))
        } catch let TransformationError.invalidRegex(msg) {
            return .failed(original: item, reason: "Invalid regex: \(msg)", recovery: nil)
        } catch {
            return .failed(original: item, reason: error.localizedDescription, recovery: nil)
        }
    }
}

// MARK: - Runtime

enum TransformationError: Error {
    case invalidRegex(String)
    case missingParameter(String)
}

enum TransformationRuntime {
    static func apply(engine: TransformationEngine,
                      input: String,
                      params: [String: String]) throws -> String {
        switch engine {
        case .regexReplace:      return try regexReplace(input, params: params)
        case .findReplace:       return findReplace(input, params: params)
        case .prepend:           return (params["text"] ?? "") + input
        case .append:            return input + (params["text"] ?? "")
        case .wrap:              return (params["prefix"] ?? "") + input + (params["suffix"] ?? "")
        case .lineFilter:        return try lineFilter(input, params: params)
        case .caseChange:        return caseChange(input, params: params)
        case .sortLines:         return sortLines(input, params: params)
        case .uniqueLines:       return uniqueLines(input)
        case .jsonFormat:        return jsonFormat(input, params: params)
        case .trim:              return trim(input)
        case .camelCase:         return camelCase(input)
        case .snakeCase:         return snakeCase(input)
        case .kebabCase:         return kebabCase(input)
        case .base64Encode:      return base64Encode(input)
        case .base64Decode:      return try base64Decode(input)
        case .urlPercentEncode:  return urlPercentEncode(input)
        case .urlPercentDecode:  return urlPercentDecode(input)
        case .slugify:           return slugify(input)
        case .wordCount:         return wordCount(input)
        case .mdToPlain:         return mdToPlain(input)
        case .mdExtractHeadings: return try mdExtractHeadings(input)
        case .mdExtractLinks:    return try mdExtractLinks(input)
        case .urlStripTracking:  return urlStripTracking(input)
        case .unicodeStyle:      return unicodeStyle(input, params: params)
        case .cyrillicToLatin:   return cyrillicTransliterate(input)
        case .latinToCyrillic:   return latinToCyrillicTransliterate(input, params: params)
        case .prettyCodeLocal:   return prettyCodeLocal(input)
        case .leetspeak:         return leetspeak(input, params: params)
        case .uwuSpeak:          return uwuSpeak(input, params: params)
        case .zalgo:             return zalgo(input, params: params)
        }
    }

    // MARK: - Attributed-string entry point

    /// Apply a formatting-preserving engine to an NSAttributedString,
    /// retaining each attributed run's bold / italic / colour / link /
    /// underline / etc. markup in the output. Only engines whose
    /// `preservesRichTextFormatting` flag is true should be passed
    /// here — the caller (`CustomTransformationAction.apply`) gates
    /// on that flag and falls back to the plain-text path otherwise.
    ///
    /// Strategy per engine kind:
    ///
    ///   • Character-local engines (caseChange, unicodeStyle,
    ///     cyrillicToLatin) — enumerate attributes, apply the
    ///     transformation to each run's substring, append result
    ///     with the same attributes. Works because the transformation
    ///     is positional and independent of surrounding context.
    ///
    ///   • Edge-only engines (trim) — trim outer whitespace from the
    ///     whole attributed string without touching attributes on the
    ///     surviving range. Per-run application would wrongly trim
    ///     whitespace inside formatted runs.
    ///
    ///   • Boundary-adding engines (wrap, prepend, append) — wrap the
    ///     original attributed string with plain prefix / suffix
    ///     strings (they carry no source attributes by definition).
    ///     Middle content keeps its formatting.
    static func applyToAttributed(engine: TransformationEngine,
                                  input: NSAttributedString,
                                  params: [String: String]) throws -> NSAttributedString {
        switch engine {

        case .trim:
            return trimAttributed(input)

        case .prepend:
            let result = NSMutableAttributedString(string: params["text"] ?? "")
            result.append(input)
            return result

        case .append:
            let result = NSMutableAttributedString(attributedString: input)
            result.append(NSAttributedString(string: params["text"] ?? ""))
            return result

        case .wrap:
            let result = NSMutableAttributedString(string: params["prefix"] ?? "")
            result.append(input)
            result.append(NSAttributedString(string: params["suffix"] ?? ""))
            return result

        case .caseChange, .unicodeStyle, .cyrillicToLatin, .latinToCyrillic,
             .leetspeak, .uwuSpeak:
            return try applyPerRun(engine: engine, input: input, params: params)

        // Everything else either isn't reachable (gated by
        // `preservesRichTextFormatting`) or would mis-handle the
        // formatting if forced through. Fall back to plain text.
        default:
            let plain = input.string
            let result = try apply(engine: engine, input: plain, params: params)
            return NSAttributedString(string: result)
        }
    }

    /// Per-attributed-run application. Each run's substring is fed to
    /// `TransformationRuntime.apply` independently and the transformed
    /// text gets the run's original attributes back. Safe only for
    /// character-local engines where the output of a substring is
    /// independent of surrounding context.
    private static func applyPerRun(engine: TransformationEngine,
                                    input: NSAttributedString,
                                    params: [String: String]) throws -> NSAttributedString {
        let result = NSMutableAttributedString()
        var thrown: Error?
        input.enumerateAttributes(
            in: NSRange(location: 0, length: input.length),
            options: []
        ) { attrs, range, stop in
            let substring = input.attributedSubstring(from: range).string
            do {
                let transformed = try apply(engine: engine, input: substring, params: params)
                result.append(NSAttributedString(string: transformed, attributes: attrs))
            } catch {
                thrown = error
                stop.pointee = true
            }
        }
        if let err = thrown { throw err }
        return result
    }

    /// Trim outer whitespace from an attributed string. Preserves
    /// every attribute on the surviving substring; only the leading
    /// and trailing whitespace characters get removed. Counterpart to
    /// the plain-text `trim(_:)` helper, exposed for the attributed
    /// path.
    private static func trimAttributed(_ input: NSAttributedString) -> NSAttributedString {
        let nsString = input.string as NSString
        let length = nsString.length
        let cs = CharacterSet.whitespacesAndNewlines
        var startLoc = 0
        var endLoc = length
        while startLoc < endLoc {
            let scalar = Unicode.Scalar(nsString.character(at: startLoc))
            guard let s = scalar, cs.contains(s) else { break }
            startLoc += 1
        }
        while endLoc > startLoc {
            let scalar = Unicode.Scalar(nsString.character(at: endLoc - 1))
            guard let s = scalar, cs.contains(s) else { break }
            endLoc -= 1
        }
        guard endLoc > startLoc else { return NSAttributedString(string: "") }
        return input.attributedSubstring(from: NSRange(location: startLoc, length: endLoc - startLoc))
    }

    private static func unicodeStyle(_ input: String, params: [String: String]) -> String {
        let raw = params["style"] ?? UnicodeFontStyle.bold.rawValue
        let style = UnicodeFontStyle(rawValue: raw) ?? .bold
        return UnicodeStylizer.apply(to: input, style: style)
    }

    // MARK: Cyrillic transliteration

    /// One supported Cyrillic-script language. `prevalence` is a rough
    /// native-speaker count in millions, used *only* to break
    /// auto-detection ties toward the more widely spoken language.
    /// `markers` are distinctive lowercase Cyrillic letters that flag this
    /// language during Cyrillic→Latin detection (Russian carries none — it
    /// is the default fallback). `cyr2lat` / `lat2cyr` are romanization
    /// overrides layered over the Russian base maps; `lat2cyrDrop` removes
    /// Russian base digraphs that don't exist in this language.
    private struct CyrillicLang {
        let id: String
        let name: String
        let prevalence: Int
        /// The language's full lowercase Cyrillic alphabet. Detection rules
        /// out any language whose alphabet is missing a letter present in
        /// the text — so a word can never be assigned to a language that
        /// physically can't spell it.
        let letters: Set<Character>
        let cyr2lat: [Character: String]
        let lat2cyr: [String: String]
        let lat2cyrDrop: [String]
        init(_ id: String, _ name: String, _ prevalence: Int,
             letters: String,
             cyr2lat: [Character: String] = [:],
             lat2cyr: [String: String] = [:],
             lat2cyrDrop: [String] = []) {
            self.id = id; self.name = name; self.prevalence = prevalence
            self.letters = Set(letters)
            self.cyr2lat = cyr2lat
            self.lat2cyr = lat2cyr; self.lat2cyrDrop = lat2cyrDrop
        }
    }

    /// Russian 33-letter alphabet — the base most other languages extend.
    private static let ruCore = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"

    /// Slavic-script Gaj/Vuk digraphs shared by Serbian and Macedonian:
    /// the Russian-style ASCII digraphs (sh/ch/zh/…) are dropped in favour
    /// of single diacritic letters.
    private static let southSlavicDrop = ["sh", "ch", "zh", "kh", "ts",
                                          "yo", "yu", "ya", "shch", "ye"]

    /// All 14 supported Cyrillic languages (>1M speakers), ordered by
    /// prevalence (the tie-breaker during detection). `letters` is each
    /// language's complete alphabet; romanization follows each language's
    /// national / common scheme rather than a single uniform standard.
    /// Latin→Cyrillic overrides assume input written in that national Latin
    /// (incl. diacritics like ä/ö/ü/ñ where the scheme uses them).
    private static let cyrillicLangs: [CyrillicLang] = [
        CyrillicLang("russian", "Russian", 150,
            letters: ruCore),
        CyrillicLang("ukrainian", "Ukrainian", 33,
            letters: "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя",
            cyr2lat: ["г": "h", "и": "y"],
            lat2cyr: ["y": "и", "yi": "ї", "ye": "є", "g": "г", "i": "і"]),
        CyrillicLang("kazakh", "Kazakh", 13,
            letters: ruCore + "әғіңөұүһқ",
            cyr2lat: ["ә": "ä", "ғ": "ğ", "қ": "q", "ң": "ñ", "ө": "ö",
                      "ұ": "ū", "ү": "ü", "һ": "h", "і": "i", "ж": "j",
                      "ш": "ş", "и": "i", "й": "i", "ю": "iu", "я": "ia"],
            lat2cyr: ["ä": "ә", "ğ": "ғ", "q": "қ", "ñ": "ң", "ö": "ө",
                      "ū": "ұ", "ü": "ү", "j": "ж", "ş": "ш", "h": "һ"]),
        CyrillicLang("serbian", "Serbian", 9,
            letters: "абвгдђежзијклљмнњопрстћуфхцчџш",
            cyr2lat: ["ж": "ž", "ч": "č", "ш": "š", "х": "h", "ц": "c",
                      "ћ": "ć", "ђ": "đ", "ј": "j", "љ": "lj", "њ": "nj",
                      "џ": "dž"],
            lat2cyr: ["ž": "ж", "č": "ч", "š": "ш", "ć": "ћ", "đ": "ђ",
                      "lj": "љ", "nj": "њ", "dž": "џ", "j": "ј", "h": "х",
                      "c": "ц"],
            lat2cyrDrop: southSlavicDrop),
        CyrillicLang("bulgarian", "Bulgarian", 8,
            letters: "абвгдежзийклмнопрстуфхцчшщъьюя",
            cyr2lat: ["щ": "sht", "ъ": "a", "ь": "y"],
            lat2cyr: ["sht": "щ", "a": "а", "yo": "йо", "yu": "ю", "ya": "я"]),
        CyrillicLang("tajik", "Tajik", 8,
            letters: "абвгғдеёжзиӣйкқлмнопрстуӯфхҳцчҷшъэюя",
            cyr2lat: ["ғ": "gh", "ӣ": "ī", "қ": "q", "ӯ": "ū", "ҳ": "h",
                      "ҷ": "j", "ъ": "'"],
            lat2cyr: ["gh": "ғ", "ī": "ӣ", "q": "қ", "ū": "ӯ", "h": "ҳ",
                      "j": "ҷ"]),
        CyrillicLang("mongolian", "Mongolian", 6,
            letters: ruCore + "өү",
            cyr2lat: ["ж": "j", "ө": "ö", "ү": "ü", "щ": "sh", "й": "i",
                      "ъ": "i", "ь": "i"],
            lat2cyr: ["ö": "ө", "ü": "ү", "j": "ж"]),
        CyrillicLang("belarusian", "Belarusian", 5,
            letters: "абвгдеёжзійклмнопрстуўфхцчшыьэюя",
            cyr2lat: ["г": "h"],
            lat2cyr: ["w": "ў", "h": "г", "i": "і"]),
        CyrillicLang("kyrgyz", "Kyrgyz", 5,
            letters: ruCore + "ңөү",
            cyr2lat: ["ң": "ñ", "ө": "ö", "ү": "ü", "ж": "j"],
            lat2cyr: ["ñ": "ң", "ö": "ө", "ü": "ү", "j": "ж"]),
        CyrillicLang("tatar", "Tatar", 5,
            letters: ruCore + "әөүҗңһ",
            cyr2lat: ["ә": "ä", "ө": "ö", "ү": "ü", "җ": "c", "ң": "ñ",
                      "һ": "h", "ж": "j", "х": "x", "ч": "ç", "ш": "ş",
                      "ы": "ı"],
            lat2cyr: ["ä": "ә", "ö": "ө", "ü": "ү", "ñ": "ң", "c": "җ",
                      "ç": "ч", "ş": "ш", "j": "ж", "x": "х", "ı": "ы"]),
        CyrillicLang("chechen", "Chechen", 2,
            letters: ruCore + "ӏӀ",
            cyr2lat: ["ӏ": "'", "Ӏ": "'", "ъ": "'"],
            lat2cyr: ["'": "ӏ"]),
        CyrillicLang("macedonian", "Macedonian", 2,
            letters: "абвгдѓежзѕијклљмнњопрстќуфхцчџш",
            cyr2lat: ["ж": "ž", "ч": "č", "ш": "š", "х": "h", "ц": "c",
                      "ѓ": "gj", "ќ": "kj", "ѕ": "dz", "џ": "dž",
                      "љ": "lj", "њ": "nj", "ј": "j"],
            lat2cyr: ["ž": "ж", "č": "ч", "š": "ш", "gj": "ѓ", "ǵ": "ѓ",
                      "kj": "ќ", "ḱ": "ќ", "dz": "ѕ", "lj": "љ", "nj": "њ",
                      "dž": "џ", "j": "ј", "h": "х", "c": "ц"],
            lat2cyrDrop: southSlavicDrop),
        CyrillicLang("bashkir", "Bashkir", 1,
            letters: ruCore + "әөүғҙҡңҫһ",
            cyr2lat: ["ә": "ä", "ө": "ö", "ү": "ü", "ғ": "ğ", "ҙ": "ź",
                      "ҫ": "ś", "ҡ": "q", "ң": "ñ", "һ": "h", "ж": "j",
                      "х": "x", "ч": "ç", "ш": "ş", "ы": "ı"],
            lat2cyr: ["ä": "ә", "ö": "ө", "ü": "ү", "ğ": "ғ", "ź": "ҙ",
                      "ś": "ҫ", "q": "ҡ", "ñ": "ң", "ç": "ч", "ş": "ш",
                      "j": "ж", "x": "х", "ı": "ы"]),
        CyrillicLang("chuvash", "Chuvash", 1,
            letters: ruCore + "ӑӗҫӳ",
            cyr2lat: ["ӑ": "ă", "ӗ": "ĕ", "ҫ": "ś", "ӳ": "ÿ"],
            lat2cyr: ["ă": "ӑ", "ĕ": "ӗ", "ś": "ҫ", "ÿ": "ӳ"])
    ]

    private static func cyrillicLang(id: String) -> CyrillicLang {
        cyrillicLangs.first { $0.id == id } ?? cyrillicLangs[0]
    }

    /// Union of every supported alphabet — used to isolate the Cyrillic
    /// letters in a string while ignoring Latin / punctuation.
    private static let allCyrillicLetters: Set<Character> = {
        var u = Set<Character>()
        for lang in cyrillicLangs { u.formUnion(lang.letters) }
        return u
    }()

    /// Auto-detect the Cyrillic language by alphabet fit: a language is
    /// penalised once for every Cyrillic letter in the text that its
    /// alphabet does not contain, and the language with the fewest such
    /// "foreign" letters wins. Ties break toward the more widely spoken
    /// language (higher `prevalence`) — so «Џек», impossible in Russian
    /// but valid in Serbian and Macedonian, resolves to Serbian. Bulgarian,
    /// whose alphabet is a subset of Russian's, is recovered from its
    /// signature ъ-as-vowel with no Russian-only ы/э/ё.
    private static func detectCyrillicLanguage(_ s: String) -> CyrillicLang {
        var present = Set(s.lowercased())
        present.formUnion(s)
        let textCyr = present.intersection(allCyrillicLetters)
        guard !textCyr.isEmpty else { return cyrillicLang(id: "russian") }
        var best = cyrillicLangs[0]                       // Russian baseline
        var bestForeign = textCyr.subtracting(best.letters).count
        for lang in cyrillicLangs.dropFirst() {
            let foreign = textCyr.subtracting(lang.letters).count
            if foreign < bestForeign
                || (foreign == bestForeign && lang.prevalence > best.prevalence) {
                bestForeign = foreign
                best = lang
            }
        }
        if best.id == "russian"
            && textCyr.contains("ъ")
            && textCyr.isDisjoint(with: ["ы", "э", "ё"]) {
            return cyrillicLang(id: "bulgarian")
        }
        return best
    }

    /// Lowercase Cyrillic → Latin base map (Russian + Ukrainian /
    /// Belarusian / Old Church Slavonic letters). Per-language overrides
    /// are layered on top in `cyrillicMap(forLanguage:)`.
    private static let cyrillicBaseMap: [Character: String] = [
        // Common letters
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d",
        "е": "e", "ё": "yo", "ж": "zh", "з": "z", "и": "i",
        "й": "y", "к": "k", "л": "l", "м": "m", "н": "n",
        "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
        "у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch",
        "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "",
        "э": "e", "ю": "yu", "я": "ya",
        // Ukrainian-specific
        "є": "ye", "і": "i", "ї": "yi", "ґ": "g",
        // Belarusian-specific
        "ў": "w",
        // Old Church Slavonic / extended (may appear in liturgical / historical text)
        "ѣ": "ye", "ѵ": "i", "ѳ": "f", "ѕ": "dz"
    ]

    private static func cyrillicMap(forLanguage lang: CyrillicLang) -> [Character: String] {
        var m = cyrillicBaseMap
        for (k, v) in lang.cyr2lat { m[k] = v }
        return m
    }

    /// Transliterate Cyrillic to Latin with auto-detected variant and case
    /// preservation. Letters are mapped via the variant-specific table; case
    /// is determined per-letter against neighbours so "ПРИВЕТ" → "PRIVET"
    /// (all-caps) but "Привет" → "Privet" (title-case), not "PRIvet".
    private static func cyrillicTransliterate(_ input: String) -> String {
        let lang = detectCyrillicLanguage(input)
        let map = cyrillicMap(forLanguage: lang)
        let chars = Array(input)
        var out = ""
        out.reserveCapacity(chars.count * 2)
        for i in chars.indices {
            let ch = chars[i]
            let lowerStr = String(ch).lowercased()
            guard let lowerCh = lowerStr.first, let translit = map[lowerCh] else {
                out.append(ch)
                continue
            }
            if !ch.isUppercase || translit.isEmpty {
                out.append(translit)
                continue
            }
            // Uppercase input. Decide title-case vs all-caps by looking at
            // the nearest Cyrillic neighbour's case.
            let neighborUpper = nearestCyrillicNeighborIsUppercase(chars, at: i, map: map)
            if neighborUpper {
                out.append(translit.uppercased())
            } else if let first = translit.first {
                out.append(String(first).uppercased())
                out.append(String(translit.dropFirst()))
            }
        }
        return out
    }

    /// True if the closest Cyrillic letter to either side of `idx` is
    /// uppercase. Used by `cyrillicTransliterate` to decide whether a
    /// multi-letter translit like "shch" should render as "Shch" (title)
    /// or "SHCH" (all-caps).
    private static func nearestCyrillicNeighborIsUppercase(_ chars: [Character],
                                                           at idx: Int,
                                                           map: [Character: String]) -> Bool {
        func isCyrillic(_ c: Character) -> Bool {
            let lower = String(c).lowercased().first ?? c
            return map[lower] != nil
        }
        // Backward scan.
        var j = idx - 1
        while j >= 0 {
            let n = chars[j]
            if isCyrillic(n) { return n.isUppercase }
            if !n.isLetter { break }
            j -= 1
        }
        // Forward scan.
        j = idx + 1
        while j < chars.count {
            let n = chars[j]
            if isCyrillic(n) { return n.isUppercase }
            if !n.isLetter { break }
            j += 1
        }
        return false
    }

    private static func caseChange(_ input: String, params: [String: String]) -> String {
        switch params["case"] ?? "upper" {
        case "upper": return input.uppercased()
        case "lower": return input.lowercased()
        case "title": return input.capitalized
        case "sentence":
            let lower = input.lowercased()
            guard let first = lower.first else { return lower }
            return first.uppercased() + lower.dropFirst()
        default: return input
        }
    }

    private static func sortLines(_ input: String, params: [String: String]) -> String {
        let direction = params["direction"] ?? "asc"
        let caseInsensitive = params["caseInsensitive"] == "true"
        let lines = input.components(separatedBy: "\n")
        let sorted = lines.sorted { a, b in
            let la = caseInsensitive ? a.lowercased() : a
            let lb = caseInsensitive ? b.lowercased() : b
            return direction == "desc" ? la > lb : la < lb
        }
        return sorted.joined(separator: "\n")
    }

    private static func uniqueLines(_ input: String) -> String {
        var seen = Set<String>()
        let lines = input.components(separatedBy: "\n")
        let unique = lines.filter { seen.insert($0).inserted }
        return unique.joined(separator: "\n")
    }

    private static func jsonFormat(_ input: String, params: [String: String]) -> String {
        let op = params["operation"] ?? "pretty"
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data,
                                                            options: [.allowFragments]) else {
            return input
        }
        switch op {
        case "minify":
            if let out = try? JSONSerialization.data(withJSONObject: json, options: []) {
                return String(data: out, encoding: .utf8) ?? input
            }
        case "extractKeys":
            if let dict = json as? [String: Any] {
                return dict.keys.sorted().joined(separator: "\n")
            }
            return ""
        case "extractKeysRecursive":
            var keys = Set<String>()
            collectJSONKeys(into: &keys, from: json)
            return keys.sorted().joined(separator: "\n")
        default: // pretty
            if let out = try? JSONSerialization.data(withJSONObject: json,
                                                      options: [.prettyPrinted, .sortedKeys]) {
                return String(data: out, encoding: .utf8) ?? input
            }
        }
        return input
    }

    /// Recursive walker used by jsonFormat operation = extractKeysRecursive.
    private static func collectJSONKeys(into keys: inout Set<String>, from obj: Any) {
        if let dict = obj as? [String: Any] {
            for (k, v) in dict { keys.insert(k); collectJSONKeys(into: &keys, from: v) }
        } else if let arr = obj as? [Any] {
            for v in arr { collectJSONKeys(into: &keys, from: v) }
        }
    }

    private static func regexReplace(_ input: String, params: [String: String]) throws -> String {
        let pattern = params["pattern"] ?? ""
        let replacement = params["replacement"] ?? ""
        guard !pattern.isEmpty else { return input }
        var options: NSRegularExpression.Options = []
        if params["caseInsensitive"] == "true" { options.insert(.caseInsensitive) }
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: options)
            let range = NSRange(input.startIndex..., in: input)
            return regex.stringByReplacingMatches(in: input, options: [],
                                                  range: range, withTemplate: replacement)
        } catch {
            throw TransformationError.invalidRegex(error.localizedDescription)
        }
    }

    private static func findReplace(_ input: String, params: [String: String]) -> String {
        let find = params["find"] ?? ""
        let replace = params["replace"] ?? ""
        guard !find.isEmpty else { return input }
        if params["caseInsensitive"] == "true" {
            return input.replacingOccurrences(of: find, with: replace,
                                              options: [.caseInsensitive])
        }
        return input.replacingOccurrences(of: find, with: replace)
    }

    private static func lineFilter(_ input: String, params: [String: String]) throws -> String {
        let pattern = params["pattern"] ?? ""
        let mode = params["mode"] ?? "keep"
        guard !pattern.isEmpty else { return input }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            throw TransformationError.invalidRegex(error.localizedDescription)
        }
        let lines = input.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.firstMatch(in: line, options: [], range: range) != nil
            return mode == "keep" ? matches : !matches
        }
        return filtered.joined(separator: "\n")
    }

    // MARK: - New parameter-less engines (seeded as builtin.* transformations)

    private static func trim(_ input: String) -> String {
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func camelCase(_ input: String) -> String {
        let parts = input.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard let first = parts.first?.lowercased() else { return "" }
        let rest = parts.dropFirst().map { $0.lowercased().capitalized }
        return first + rest.joined()
    }

    private static func snakeCase(_ input: String) -> String {
        input.split { !$0.isLetter && !$0.isNumber }
            .map { $0.lowercased() }
            .joined(separator: "_")
    }

    private static func kebabCase(_ input: String) -> String {
        input.split { !$0.isLetter && !$0.isNumber }
            .map { $0.lowercased() }
            .joined(separator: "-")
    }

    private static func base64Encode(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return input }
        return data.base64EncodedString()
    }

    private static func base64Decode(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed),
              let decoded = String(data: data, encoding: .utf8) else {
            throw TransformationError.missingParameter("input is not valid Base64")
        }
        return decoded
    }

    private static func urlPercentEncode(_ input: String) -> String {
        input.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? input
    }

    private static func urlPercentDecode(_ input: String) -> String {
        input.removingPercentEncoding ?? input
    }

    private static func slugify(_ input: String) -> String {
        let lower = input.lowercased()
        let latin = lower.applyingTransform(.toLatin, reverse: false) ?? lower
        let stripped = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return stripped.split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
    }

    private static func wordCount(_ input: String) -> String {
        let words = input.split { $0.isWhitespace }.count
        let chars = input.count
        let lines = input.split(separator: "\n").count
        return "\(words) words, \(chars) characters, \(lines) lines"
    }

    private static func mdToPlain(_ input: String) -> String {
        var s = input
        let patterns: [(String, String)] = [
            (#"^#{1,6}\s+"#, ""),
            (#"\*\*(.+?)\*\*"#, "$1"),
            (#"\*(.+?)\*"#, "$1"),
            (#"`([^`]+)`"#, "$1"),
            (#"\[([^\]]+)\]\([^)]+\)"#, "$1"),
            (#"^[-*+]\s+"#, "• ")
        ]
        for (pat, rep) in patterns {
            s = s.replacingOccurrences(of: pat, with: rep, options: .regularExpression)
        }
        return s
    }

    private static func mdExtractHeadings(_ input: String) throws -> String {
        let lines = input.split(separator: "\n").map(String.init)
        let headings = lines.filter { $0.hasPrefix("#") && $0.contains(" ") }
        if headings.isEmpty {
            throw TransformationError.missingParameter("no Markdown headings found")
        }
        return headings.joined(separator: "\n")
    }

    private static func mdExtractLinks(_ input: String) throws -> String {
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        let matches = regex.matches(in: input, range: range)
        let urls = matches.compactMap { m -> String? in
            guard let r = Range(m.range(at: 2), in: input) else { return nil }
            return String(input[r])
        }
        if urls.isEmpty {
            throw TransformationError.missingParameter("no Markdown links found")
        }
        return urls.joined(separator: "\n")
    }

    /// Tracking parameter list mirrors the legacy URLStripTrackingAction whitelist.
    private static let urlTrackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "yclid", "mc_cid", "mc_eid", "igshid",
        "_ga", "_gl", "ref", "ref_src", "ref_url", "spm", "wt_mc",
        "vero_conv", "vero_id"
    ]

    private static func urlStripTracking(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: trimmed) else { return input }
        if let q = comps.queryItems {
            comps.queryItems = q.filter { !urlTrackingParams.contains($0.name.lowercased()) }
            if comps.queryItems?.isEmpty == true { comps.queryItems = nil }
        }
        return comps.string ?? input
    }

    // MARK: - Latin → Cyrillic transliteration (#A18)

    /// Reverse-transliterate Latin → Cyrillic with a per-language target
    /// scheme. Greedy multi-char digraph matching first (sh, ch, zh, shch,
    /// yo, yu, ya) before single-letter substitution. Case is preserved
    /// per source word run: "Privet"→"Привет", "PRIVET"→"ПРИВЕТ", lone
    /// "P"→"П". Non-letter chars pass through.
    private static func latinToCyrillicTransliterate(_ input: String,
                                                      params: [String: String]) -> String {
        let target = params["target"] ?? "russian"
        let map = latinToCyrillicMap(for: target)
        let chars = Array(input)
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            // Greedy longest-match against the digraph/trigraph table.
            var matched = false
            for length in stride(from: min(4, chars.count - i), through: 1, by: -1) {
                let slice = String(chars[i..<(i + length)]).lowercased()
                guard let cyrillic = map[slice] else { continue }
                // Case decision from the source slice. If any letter in
                // the slice is uppercase + the previous source letter was
                // also uppercase → ALL CAPS output. Else if first letter
                // of slice is uppercase → Title case. Else lowercase.
                let firstSourceChar = chars[i]
                let allCapsRun = firstSourceChar.isUppercase
                    && (length == 1 || chars[i + 1].isUppercase)
                if allCapsRun {
                    out.append(cyrillic.uppercased())
                } else if firstSourceChar.isUppercase {
                    if let f = cyrillic.first {
                        out.append(String(f).uppercased())
                        out.append(String(cyrillic.dropFirst()))
                    }
                } else {
                    out.append(cyrillic)
                }
                i += length
                matched = true
                break
            }
            if !matched {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    /// Latin → Cyrillic map for the given target language. Digraphs first
    /// (matched greedily by the caller), single letters second. Russian
    /// base, then the target language's `lat2cyrDrop` removals and
    /// `lat2cyr` overrides from the `cyrillicLangs` table are applied.
    private static func latinToCyrillicMap(for target: String) -> [String: String] {
        // Russian base — digraphs precede single-letter for greedy match.
        var m: [String: String] = [
            // Trigraph
            "shch": "щ",
            // Digraphs
            "sh": "ш", "ch": "ч", "zh": "ж", "kh": "х", "ts": "ц",
            "yo": "ё", "yu": "ю", "ya": "я",
            "ye": "е",
            // Single letters
            "a": "а", "b": "б", "v": "в", "g": "г", "d": "д",
            "e": "е", "z": "з", "i": "и", "y": "й",
            "k": "к", "l": "л", "m": "м", "n": "н", "o": "о",
            "p": "п", "r": "р", "s": "с", "t": "т", "u": "у",
            "f": "ф", "h": "х", "c": "ц",
            "j": "й",
            "w": "в", "x": "кс", "q": "к"
        ]
        let lang = cyrillicLang(id: target)
        for key in lang.lat2cyrDrop { m.removeValue(forKey: key) }
        for (k, v) in lang.lat2cyr { m[k] = v }
        return m
    }

    // MARK: - Pretty Code Local (#A19)

    /// Deterministic offline reformatter for JSON / XML / HTML / CSS plus
    /// a generic whitespace-normalization fallback. Format auto-detected
    /// by leading characters; never enlarges output, never reorders
    /// content beyond what each format's pretty-printer does.
    private static func prettyCodeLocal(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return input }
        let firstChar = trimmed.first!
        let lower = trimmed.lowercased()

        // JSON: leading { or [
        if firstChar == "{" || firstChar == "[" {
            if let data = trimmed.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments]),
               let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                        options: [.prettyPrinted, .sortedKeys]),
               let s = String(data: pretty, encoding: .utf8) {
                return s
            }
            return input
        }
        // XML: leading <?xml or <tag without DOCTYPE/html
        if lower.hasPrefix("<?xml") || (firstChar == "<" && !lower.hasPrefix("<!doctype") && !lower.hasPrefix("<html")) {
            if let data = trimmed.data(using: .utf8),
               let doc = try? XMLDocument(data: data, options: []) {
                let pretty = doc.xmlData(options: [.nodePrettyPrint])
                if let s = String(data: pretty, encoding: .utf8) { return s }
            }
            // Fall through to HTML if XML failed.
        }
        // HTML: leading <!DOCTYPE or <html
        if lower.hasPrefix("<!doctype") || lower.hasPrefix("<html") || (firstChar == "<" && lower.contains("</")) {
            return prettyHTMLLike(trimmed)
        }
        // CSS: contains "{...}" structure.
        if trimmed.contains("{") && trimmed.contains("}") && trimmed.contains(":") {
            return prettyCSS(trimmed)
        }
        // Generic whitespace cleanup.
        return prettyGeneric(trimmed)
    }

    /// Simple regex-driven HTML reflow: newline after `>` between elements,
    /// indent by tag depth, collapse runs of inline whitespace. Targets the
    /// 90% common case of "ugly minified HTML" → readable.
    private static func prettyHTMLLike(_ s: String) -> String {
        var src = s
        // Normalize line endings + collapse runs of 2+ spaces between tags.
        src = src.replacingOccurrences(of: "\r\n", with: "\n")
        src = src.replacingOccurrences(of: "\r", with: "\n")
        // Add a newline between adjacent tags.
        src = src.replacingOccurrences(of: ">\\s*<",
                                       with: ">\n<",
                                       options: .regularExpression)
        let lines = src.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var indent = 0
        var out: [String] = []
        let voidTags: Set<String> = ["br", "hr", "img", "input", "meta", "link",
                                     "area", "base", "col", "embed", "param",
                                     "source", "track", "wbr"]
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lowered = line.lowercased()
            let isClosing = lowered.hasPrefix("</")
            if isClosing { indent = max(0, indent - 1) }
            out.append(String(repeating: "  ", count: indent) + line)
            // Self-closing or void → don't push indent.
            let isSelfClosing = lowered.hasSuffix("/>")
            let openedTag: String = {
                guard lowered.hasPrefix("<") && !isClosing && !isSelfClosing else { return "" }
                let body = lowered.dropFirst()
                let nameEnd = body.firstIndex(where: { !$0.isLetter && !$0.isNumber }) ?? body.endIndex
                return String(body[body.startIndex..<nameEnd])
            }()
            let isVoid = voidTags.contains(openedTag)
            // Single-line element like <p>hi</p> — depth unchanged.
            let hasInlineClose = lowered.contains("</\(openedTag)>") && !openedTag.isEmpty
            if !isClosing && !isSelfClosing && !isVoid && !hasInlineClose && lowered.hasPrefix("<") {
                indent += 1
            }
        }
        return out.joined(separator: "\n")
    }

    private static func prettyCSS(_ s: String) -> String {
        var src = s
        src = src.replacingOccurrences(of: "\r\n", with: "\n")
        // Standardize one rule per block.
        src = src.replacingOccurrences(of: "\\s*\\{\\s*",
                                       with: " {\n  ",
                                       options: .regularExpression)
        src = src.replacingOccurrences(of: "\\s*;\\s*(?!})",
                                       with: ";\n  ",
                                       options: .regularExpression)
        src = src.replacingOccurrences(of: "\\s*}\\s*",
                                       with: "\n}\n\n",
                                       options: .regularExpression)
        // Tidy any leftover trailing whitespace.
        let lines = src.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .init(charactersIn: " \t")) }
        return lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generic fallback: trim trailing whitespace per line, normalize
    /// line endings, expand tabs → 4 spaces, collapse 3+ blank lines.
    private static func prettyGeneric(_ s: String) -> String {
        var src = s.replacingOccurrences(of: "\r\n", with: "\n")
        src = src.replacingOccurrences(of: "\t", with: "    ")
        src = src.replacingOccurrences(of: "\n{3,}",
                                       with: "\n\n",
                                       options: .regularExpression)
        let lines = src.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .init(charactersIn: " \t")) }
        return lines.joined(separator: "\n")
    }

    // MARK: - Leetspeak / 1337 (#A70)

    /// Pure table-driven leet substitution. Aggressive mode adds three
    /// extra mappings that are noisier-looking but more distinctive.
    private static func leetspeak(_ input: String, params: [String: String]) -> String {
        let aggressive = (params["aggressive"] ?? "false") == "true"
        var map: [Character: Character] = [
            "a": "4", "e": "3", "i": "1", "o": "0", "s": "5", "t": "7"
        ]
        if aggressive {
            map["l"] = "1"; map["g"] = "9"; map["b"] = "8"
        }
        return String(input.map { ch -> Character in
            let lower = Character(String(ch).lowercased())
            return map[lower] ?? ch
        })
    }

    // MARK: - UwU speech (#A70)

    /// UwU transformations:
    ///   • r / l → w (preserve case)
    ///   • n + vowel → ny + vowel (lowercase + uppercase variants)
    ///   • Optional face injection after sentence-ending punctuation.
    private static func uwuSpeak(_ input: String, params: [String: String]) -> String {
        let facesOn = (params["faces"] ?? "true") == "true"
        // r / l → w (case-preserving).
        var s = String(input.map { ch -> Character in
            switch ch {
            case "r", "l": return "w"
            case "R", "L": return "W"
            default:       return ch
            }
        })
        // n + vowel → ny + vowel (case-preserving on the leading n).
        s = s.replacingOccurrences(of: "n([aeiouAEIOU])",
                                   with: "ny$1",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "N([aeiouAEIOU])",
                                   with: "Ny$1",
                                   options: .regularExpression)
        guard facesOn else { return s }
        // Inject UwU / OwO / nya~ after sentence-ending punctuation,
        // rotating through the face list for variety.
        let faces = [" UwU", " OwO", " nya~"]
        guard let re = try? NSRegularExpression(pattern: "([.!?])(\\s+|$)",
                                                options: []) else { return s }
        let ns = s as NSString
        let matches = re.matches(in: s, options: [],
                                 range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var result = ""
        var cursor = 0
        var idx = 0
        for m in matches {
            let punctRange = m.range(at: 1)
            let tailRange = m.range(at: 2)
            let punctEnd = punctRange.location + punctRange.length
            if cursor < punctEnd {
                result += ns.substring(with: NSRange(location: cursor,
                                                     length: punctEnd - cursor))
            }
            result += faces[idx % faces.count]
            idx += 1
            if tailRange.length > 0 {
                result += ns.substring(with: tailRange)
            }
            cursor = tailRange.location + tailRange.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor,
                                                 length: ns.length - cursor))
        }
        return result
    }

    // MARK: - Zalgo corruption (#A70)

    /// Add overlapping Unicode combining marks to non-whitespace
    /// characters. Intensity controls density. Whitespace passes through
    /// untouched so word boundaries stay scannable.
    private static func zalgo(_ input: String, params: [String: String]) -> String {
        let intensity = params["intensity"] ?? "medium"
        let (up, down, mid): (Int, Int, Int)
        switch intensity {
        case "light":  (up, down, mid) = (1, 1, 0)
        case "heavy":  (up, down, mid) = (8, 8, 2)
        default:       (up, down, mid) = (3, 3, 1)
        }
        let combiningUp: [Character] = (0x0300...0x036F).compactMap {
            UnicodeScalar($0).map(Character.init)
        }
        let combiningDown: [Character] = (0x0316...0x0362).compactMap {
            UnicodeScalar($0).map(Character.init)
        }
        let combiningMid: [Character] = (0x0334...0x0338).compactMap {
            UnicodeScalar($0).map(Character.init)
        }
        var out = ""
        out.reserveCapacity(input.count * (1 + up + down + mid))
        for ch in input {
            out.append(ch)
            guard !ch.isWhitespace, !ch.isNewline else { continue }
            for _ in 0..<Int.random(in: 0...up) {
                if let c = combiningUp.randomElement() { out.append(c) }
            }
            for _ in 0..<Int.random(in: 0...down) {
                if let c = combiningDown.randomElement() { out.append(c) }
            }
            for _ in 0..<Int.random(in: 0...mid) {
                if let c = combiningMid.randomElement() { out.append(c) }
            }
        }
        return out
    }
}
