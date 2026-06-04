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
    case cyrillicToLatin   = "cyrillic_to_latin"    // auto-detects ru/uk/be/bg/sr/mk

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
            return "Transliterate Cyrillic text (Russian, Ukrainian, Belarusian, Bulgarian, Serbian, Macedonian) to Latin. Auto-detects the script variant by marker letters: ћ ђ ј љ њ џ ѓ ќ ѕ → Serbian/Macedonian (Gaj's diacritic scheme: ж→ž, ч→č, ш→š); ъ without ы/э/ё → Bulgarian (Streamlined 2009: щ→sht, ъ→a); є ї ґ → Ukrainian; ў → Belarusian; otherwise Russian default. Preserves word case (Привет→Privet, ПРИВЕТ→PRIVET). Useful for URL slugs, name romanization, plain-Latin contexts, and chaining into Unicode pseudo-font styling."
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
        case .trim,
             .camelCase, .snakeCase, .kebabCase,
             .base64Encode, .base64Decode,
             .urlPercentEncode, .urlPercentDecode,
             .slugify, .wordCount,
             .mdToPlain, .mdExtractHeadings, .mdExtractLinks,
             .urlStripTracking,
             .cyrillicToLatin:
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
             .cyrillicToLatin:
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
        case .caseChange, .unicodeStyle, .cyrillicToLatin,
             .trim, .wrap, .prepend, .append:
            return true
        case .regexReplace, .findReplace, .lineFilter,
             .sortLines, .uniqueLines, .jsonFormat,
             .camelCase, .snakeCase, .kebabCase,
             .base64Encode, .base64Decode,
             .urlPercentEncode, .urlPercentDecode,
             .slugify, .wordCount,
             .mdToPlain, .mdExtractHeadings, .mdExtractLinks,
             .urlStripTracking:
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

        case .caseChange, .unicodeStyle, .cyrillicToLatin:
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

    /// Variant of Cyrillic for selecting the appropriate Latin scheme.
    /// `.russian` covers Russian + Ukrainian + Belarusian (digraph style:
    /// zh, ch, sh, kh). `.bulgarian` follows Streamlined 2009 (sht, a, y).
    /// `.serbian` covers Serbian + Macedonian Gaj's Latin (ž, č, š, h, c).
    private enum CyrillicVariant { case russian, bulgarian, serbian }

    /// Detect which Cyrillic variant the text uses. Heuristic — looks at
    /// marker letters that uniquely identify a script. Defaults to Russian
    /// when no marker hits, which is the most common case.
    private static func detectCyrillicVariant(_ s: String) -> CyrillicVariant {
        let serbianMarkers: Set<Character> = ["ћ", "ђ", "ј", "љ", "њ", "џ", "ѓ", "ќ", "ѕ",
                                              "Ћ", "Ђ", "Ј", "Љ", "Њ", "Џ", "Ѓ", "Ќ", "Ѕ"]
        let russianOnlyMarkers: Set<Character> = ["ы", "э", "ё", "Ы", "Э", "Ё"]
        if s.contains(where: { serbianMarkers.contains($0) }) {
            return .serbian
        }
        let hasYer = s.contains("ъ") || s.contains("Ъ")
        let hasRussianMarker = s.contains(where: { russianOnlyMarkers.contains($0) })
        if hasYer && !hasRussianMarker {
            return .bulgarian
        }
        return .russian
    }

    /// Lowercase Cyrillic → Latin base map. Covers Russian, Ukrainian,
    /// Belarusian, and Old Church Slavonic letters. Bulgarian and Serbian
    /// overrides are applied separately in `cyrillicMap(for:)`.
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

    private static func cyrillicMap(for variant: CyrillicVariant) -> [Character: String] {
        var m = cyrillicBaseMap
        switch variant {
        case .russian:
            break
        case .bulgarian:
            // Streamlined Transliteration System (Bulgarian state standard, 2009).
            m["щ"] = "sht"
            m["ъ"] = "a"
            m["ь"] = "y"
        case .serbian:
            // Gaj's Latin alphabet — one-to-one with Serbian Cyrillic.
            m["ж"] = "ž"; m["ч"] = "č"; m["ш"] = "š"
            m["х"] = "h"; m["ц"] = "c"
            // Serbian-specific letters.
            m["ћ"] = "ć"; m["ђ"] = "đ"; m["ј"] = "j"
            m["љ"] = "lj"; m["њ"] = "nj"; m["џ"] = "dž"
            // Macedonian-specific letters.
            m["ѓ"] = "gj"; m["ќ"] = "kj"; m["ѕ"] = "dz"
        }
        return m
    }

    /// Transliterate Cyrillic to Latin with auto-detected variant and case
    /// preservation. Letters are mapped via the variant-specific table; case
    /// is determined per-letter against neighbours so "ПРИВЕТ" → "PRIVET"
    /// (all-caps) but "Привет" → "Privet" (title-case), not "PRIvet".
    private static func cyrillicTransliterate(_ input: String) -> String {
        let variant = detectCyrillicVariant(input)
        let map = cyrillicMap(for: variant)
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
}
