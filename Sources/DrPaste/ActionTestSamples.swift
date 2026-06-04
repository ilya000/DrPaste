//
//  ActionTestSamples.swift
//  DrPaste
//
//  Copyright © 2026 iLya Os.
//  Licensed under GPL-3.0-or-later with attribution (GPL §7(d)).
//  See LICENSE for terms.
//
//  Per-action curated test samples for the Settings → Edit Action sheet's
//  Test panel. Pre-populated on dialog open so the user can immediately
//  click "Run test" and see a meaningful result without first hunting
//  for sample text to paste in.
//
//  Two flavours:
//
//    • Text samples — short, demonstrative input that shows the action's
//      effect clearly. Translate gets an English sentence, Fix grammar
//      gets typo-riddled text, Unicode font transforms get a mixed-case
//      alphabet, JSON actions get pretty-printable JSON, etc.
//
//    • Image samples — for AI image actions (Pencil sketch, Watercolor,
//      Cartoon). Generated procedurally as a small PNG with a
//      recognisable subject so the user can see the style transform.
//      Saved to AppStorage.imagesDir so the standard `previewImageRel`
//      path reads it like any other clipboard image.
//
//  The matching table is action-id keyed. Unknown IDs fall back to a
//  generic "Hello, world." sentence for text actions and a generic
//  procedural shape for image actions, so the panel is never empty.
//

import Foundation
import AppKit

enum ActionTestSamples {

    // MARK: - Text samples

    /// Returns the demonstrative input string for `actionID`, or nil
    /// when no curated sample is registered. ActionEditor.loadInitialState
    /// falls back to leaving the field empty (user types their own) when
    /// the lookup misses.
    static func textSample(for actionID: String) -> String? {
        switch actionID {

        // MARK: Translation
        case "user.translate", "user.translate_rich":
            return "Hello! How are you doing today? I hope the weather is nice where you are."

        // MARK: Grammar / tone
        case "user.fix_grammar", "user.fix_grammar_rich":
            return "their going too the store later, me and him beleive its allready to late, " +
                   "but we will sea what happens"

        case "user.formal_tone":
            return "hey, just wanted to give u a quick heads up that the report's gonna be late. " +
                   "ran into some stuff i didn't expect. lmk if that's a problem."

        case "user.summarize":
            return """
            DrPaste is a macOS clipboard manager built around a press-and-hold gesture. \
            When the user holds ⌥⌘V, a heads-up display appears showing their recent \
            clipboard history alongside context-aware actions. Releasing the keys commits \
            the selected paste. The app also supports per-action hotkeys, AI-powered \
            text transformations, region-capture screenshots, and a stack of built-in \
            text utilities including case conversion, JSON formatting, URL cleaning, \
            and Unicode pseudo-font styling. It runs in the menu bar with no Dock icon \
            and is distributed as a native AppKit binary.
            """

        // MARK: Case
        case "builtin.uppercase", "builtin.lowercase",
             "builtin.title_case", "builtin.sentence_case":
            return "The quick brown fox jumps over the lazy dog."

        case "builtin.camel_case", "builtin.snake_case", "builtin.kebab_case":
            return "user account email address"

        // MARK: Whitespace / lines
        case "builtin.trim":
            return "   leading and trailing whitespace here   \n\n"

        case "builtin.sort_lines":
            return "banana\napple\ncherry\ndate\nblueberry"

        case "builtin.unique_lines":
            return "apple\nbanana\napple\ncherry\nbanana\ndate"

        // MARK: Encoding
        case "builtin.base64_encode":
            return "Hello, DrPaste!"

        case "builtin.base64_decode":
            return "SGVsbG8sIERyUGFzdGUh"

        case "builtin.url_encode":
            return "https://example.com/search?q=hello world&lang=en-US"

        case "builtin.url_decode":
            return "https://example.com/search?q=hello%20world&lang=en-US"

        // MARK: Derived
        case "builtin.slugify":
            return "My Awesome Blog Post! (Draft v2)"

        case "builtin.word_count":
            return "The quick brown fox jumps over the lazy dog."

        // MARK: JSON
        case "builtin.json_pretty", "builtin.json_minify":
            return #"{"name":"Ada Lovelace","born":1815,"contributions":["analytical engine","first algorithm"],"address":{"city":"London","country":"UK"}}"#

        case "builtin.json_extract_keys", "builtin.json_keys",
             "builtin.json_flatten", "builtin.json_remove_nulls":
            return #"{"user":{"id":42,"name":"Ada","email":null,"prefs":{"theme":"dark","notify":true}}}"#

        // MARK: Code
        case "builtin.code_wrap":
            return "let answer = 42"

        case "builtin.tabs_to_spaces":
            return "func greet() {\n\tprint(\"hello\")\n}"

        case "builtin.spaces_to_tabs":
            return "func greet() {\n    print(\"hello\")\n}"

        // MARK: Markdown
        case "builtin.md_to_plain":
            return "# Title\n\nSome **bold** and *italic* text with a [link](https://example.com).\n\n- bullet one\n- bullet two"

        case "builtin.md_to_rich":
            return "A line with **bold**, *italic*, and `inline code`.\n\nFollowed by a [linked phrase](https://example.com)."

        case "builtin.md_headings", "builtin.md_extract_headings":
            return "# Introduction\n\nSome intro text.\n\n## Background\n\nMore text.\n\n## Goals\n\n### Short-term\n\nDetail.\n\n## Conclusion"

        case "builtin.md_links", "builtin.md_extract_links":
            return "See the [docs](https://example.com/docs) and the [API reference](https://example.com/api) for details. Also check [GitHub](https://github.com/example/repo)."

        // MARK: URL
        case "builtin.url_strip_tracking", "builtin.url_clean":
            return "https://example.com/article?utm_source=newsletter&utm_medium=email&utm_campaign=launch&fbclid=abc123&id=42"

        case "builtin.url_just_domain", "builtin.url_domain":
            return "https://docs.example.com/path/to/page?ref=home"

        case "builtin.url_markdown_link", "builtin.url_html_link":
            return "https://www.apple.com"

        // MARK: Layout repair
        case "builtin.layout_repair":
            // Russian phrase typed with English keyboard layout — Cyrillic
            // glyphs produced by the wrong-layout mapping. Repair should
            // convert these back to Russian: "Привет, мир!"
            return "Ghbdtn, vbh!"

        // MARK: Cyrillic transliteration
        case "builtin.cyrillic_translit":
            return "Привет, как дела? Меня зовут Анна."

        // MARK: Unicode pseudo-fonts — show the alphabet so the user
        // immediately sees the styling effect.
        case "builtin.font_bold", "builtin.font_italic", "builtin.font_bold_italic",
             "builtin.font_script", "builtin.font_bold_script",
             "builtin.font_fraktur", "builtin.font_bold_fraktur",
             "builtin.font_double_struck",
             "builtin.font_sans", "builtin.font_sans_bold",
             "builtin.font_sans_italic", "builtin.font_sans_bold_italic",
             "builtin.font_monospace", "builtin.font_fullwidth",
             "builtin.font_small_caps",
             "builtin.font_circled", "builtin.font_filled_circled",
             "builtin.font_squared", "builtin.font_filled_squared",
             "builtin.font_upside_down":
            return "The quick brown fox 123"

        case "builtin.font_plain":
            // Stylized input that the action collapses back to plain ASCII.
            return "𝐓𝐡𝐞 𝐪𝐮𝐢𝐜𝐤 𝐛𝐫𝐨𝐰𝐧 𝐟𝐨𝐱 𝟏𝟐𝟑"

        case "builtin.font_markdown":
            // Markdown markup that the action converts span-by-span into
            // Unicode pseudo-fonts. Plain text outside markup stays as-is.
            return "Today's update: **important news** in *italic* with `inline code` and ~~struck text~~. Use ***this***  for bold-italic."

        // MARK: Tables
        case "builtin.table_to_json", "builtin.table_to_md":
            return "name,role,city\nAda,engineer,London\nGrace,admiral,New York\nKatherine,mathematician,Hampton"

        // MARK: Rich text — markdown source. The Test panel keeps a
        // plain-text TextEditor for the Input field, but `runTest`
        // parses this markdown into an NSAttributedString and feeds
        // a synthesised `.richText` item to the action (which then
        // reads `representations["public.rtf"]`). User sees Input as
        // editable markdown source; Output shows the target format.
        // Note: NSAttributedString(markdown:) on macOS 12+ honours
        // INLINE markdown (**bold**, *italic*, `code`, [link](url))
        // but NOT block-level (# headings, lists). Samples therefore
        // concentrate on inline elements that demonstrably round-trip
        // through each target format.

        case "builtin.rich_to_wiki":
            // MediaWiki output preview: '''bold''', ''italic'',
            // [https://… label], '''''both''''', <code>code</code>.
            return "MediaWiki converts **bold** to ''​'​bold​'​''​, " +
                   "*italic* to ''italic'', and `inline code` becomes " +
                   "<code>inline code</code>. Hyperlinks like " +
                   "[Wikipedia](https://en.wikipedia.org) turn into " +
                   "[https://en.wikipedia.org Wikipedia]."

        case "builtin.rich_to_md":
            // Markdown round-trip — the output looks similar to the
            // input but normalises whitespace and emits canonical
            // syntax (always **bold** not __bold__, always *italic*
            // not _italic_).
            return "Rich → Markdown produces **bold**, *italic*, " +
                   "`inline code`, and [hyperlinks](https://example.com) " +
                   "in their canonical Markdown form."

        case "builtin.rich_to_html":
            // HTML output preview: <strong>, <em>, <code>, <a href=...>.
            return "HTML conversion emits **bold** as <strong>, " +
                   "*italic* as <em>, `inline code` as <code>, and " +
                   "[hyperlinks](https://example.com) as " +
                   "<a href=\"https://example.com\">…</a>."

        case "builtin.rich_to_unicode_style":
            // Maps **bold** / *italic* to Unicode pseudo-fonts:
            // 𝐛𝐨𝐥𝐝, 𝑖𝑡𝑎𝑙𝑖𝑐. Useful for Twitter / Telegram where
            // markup is stripped but Unicode survives.
            return "**Bold** becomes 𝐛𝐨𝐥𝐝, *italic* becomes 𝑖𝑡𝑎𝑙𝑖𝑐 — " +
                   "useful when you need formatted-looking text in " +
                   "places that strip HTML / Markdown markup."

        case "builtin.clean_formatting", "builtin.paste_as_text":
            // Strip-formatting actions — show fancy formatting that
            // gets flattened to plain text in the Output.
            return "Pasting **bold**, *italic*, `inline code`, and " +
                   "[hyperlinks](https://example.com) here would " +
                   "normally carry source styling. This action " +
                   "flattens everything to plain text."

        // MARK: Type slowly
        case "builtin.type_slowly":
            return "This text will type one character at a time into the target app."

        // MARK: AI image styles — testInput is unused (sample image is
        // generated procedurally in runTest), but a friendly placeholder
        // sentence avoids confusion when the user looks at the empty
        // Input field. Returning a non-nil string also tells
        // loadInitialState to populate the field.
        case "user.ai_image_sketch",
             "user.ai_image_watercolor",
             "user.ai_image_cartoon":
            return "(Image action — Run test will use a generated sample image)"

        // MARK: AI text → image (Whiteboard sketch) — testInput IS
        // the prompt content here. Need a sample that lends itself
        // to whiteboard-style explanatory diagramming: a short
        // process / flow / cause-and-effect that someone would
        // naturally sketch on a meeting whiteboard with arrows and
        // labels. Picked the classic feedback loop because the
        // shape is recognizable, it's domain-neutral, and the
        // result is visually obviously "a whiteboard sketch" not
        // "a generic illustration".
        case "user.ai_text_to_image_whiteboard":
            return """
            Build → measure → learn loop:
            1. Build a small experiment
            2. Measure user behaviour
            3. Learn what worked
            4. Feed insights back into the next build
            Arrows close the loop. Label each step.
            """

        // MARK: Built-in image actions — Run test generates a sample
        // PNG and feeds it to the action. The Input field text is
        // informational; the user can keep these placeholders or
        // override them via the persisted-sample mechanism.
        case "builtin.image_ocr":
            return "(Image action — Run test will OCR a sample image with the word \"DrPaste sample\")"

        case "builtin.image_decode_qr":
            return "(Image action — Run test will try to decode a sample image; the procedural sample has no QR, so the action will report \"no QR code\")"

        case "builtin.image_grayscale":
            return "(Image action — Run test will desaturate a colourful sample sunset image)"

        case "builtin.image_invert":
            return "(Image action — Run test will invert colours of a sample sunset image)"

        case "builtin.image_rotate":
            return "(Image action — Run test will rotate a sample image 90° clockwise)"

        case "builtin.image_rotate_left":
            return "(Image action — Run test will rotate a sample image 90° counter-clockwise)"

        case "builtin.image_strip_meta":
            return "(Image action — Run test will strip EXIF / metadata from a sample image)"

        case "builtin.image_resize_1920":
            return "(Image action — Run test will resize a sample 512×512 image; already under 1920, action returns as-is)"

        case "builtin.image_compress_jpeg":
            return "(Image action — Run test will re-encode the sample PNG as JPEG)"

        case "builtin.image_ascii_art":
            return "(Image action — Run test will tone-map a sample image to ASCII art)"

        // MARK: QR generation — text → QR image
        case "builtin.generate_qr":
            return "https://github.com/ilya000/DrPaste"

        // MARK: Files — sample as comma-separated paths. `fileURLs()`
        // in FileActions.swift parses comma-separated paths from
        // previewText as a fallback when no file-URL representation
        // exists, so this works end-to-end in runTest without needing
        // to fabricate a file-URL pasteboard representation.
        case "builtin.files_paths",
             "builtin.files_names",
             "builtin.files_md_links":
            return "/Users/example/Documents/Q4-report.pdf, " +
                   "/Users/example/Pictures/team-photo.jpg, " +
                   "/Users/example/Desktop/notes.txt"

        case "builtin.files_reveal":
            return "(Side-effect action — Run test would reveal the file in Finder; " +
                   "test panel skips the side effect to avoid surprising the user)"

        // MARK: Identity (Paste as-is) — no transformation, so any
        // sample text demonstrates the round-trip.
        case "builtin.identity":
            return "Whatever you paste comes back unchanged — this is the no-op action."

        default:
            return nil
        }
    }

    // MARK: - Image sample

    /// The default test image used as the Input for every image-
    /// applicable action. Resolution order:
    ///
    ///   1. `Mandrill.png` bundled under `Sources/DrPaste/Resources/`
    ///      — the classic USC-SIPI test image (1973, public domain),
    ///      a colorful baboon portrait. Industry standard for image-
    ///      processing demos: rich saturated colours (red nose, blue
    ///      cheeks, yellow fur, green-tinted background) and fine
    ///      hair texture give every image action — OCR, grayscale,
    ///      invert, rotate, AI sketch / watercolor / cartoon — a
    ///      striking, recognisable subject to transform. Free of the
    ///      ethical baggage carried by Lenna (the model Lena Forsén
    ///      publicly asked the image-processing community to retire
    ///      her likeness in 2019; IEEE / Nature have since banned it).
    ///   2. Disk cache at `AppStorage.imagesDir/Mandrill-cached.png`,
    ///      populated by `prefetchMandrillIfNeeded()` on first launch.
    ///      Same Mandrill image, downloaded from USC-SIPI on the
    ///      user's machine the first time they need it. Survives
    ///      restarts, never re-downloaded.
    ///   3. Procedural fallback — stylised portrait drawn with
    ///      NSBezierPath. Used only when both bundle and cache miss
    ///      (e.g. fresh install with no network on first launch).
    ///      Once the prefetch completes in the background, subsequent
    ///      calls flip to the Mandrill cache automatically.
    ///
    /// Saved to AppStorage.imagesDir alongside regular clipboard
    /// images so the standard `previewImageRel` path reads it back
    /// uniformly. Returns a transient ClipboardItem (not added to
    /// history) ready to pass into `action.apply`.
    @MainActor
    static func makeSampleImageItem() -> ClipboardItem? {
        // 1. Try the bundled Mandrill resource.
        if let item = makeBundledMandrillSampleItem() {
            return item
        }
        // 2. Try the on-disk Mandrill cache (populated by
        //    prefetchMandrillIfNeeded on first launch).
        if let item = makeCachedMandrillSampleItem() {
            return item
        }
        // 3. Kick off a background prefetch so the cache is ready
        //    next time the user opens the editor. No-op if a
        //    prefetch is already in flight or the file is already
        //    on disk (rechecked under prefetchLock).
        prefetchMandrillIfNeeded()
        // 4. Fall back to the user's current macOS desktop wallpaper —
        //    always available, photographic, something they recognise.
        //    Beats a procedural shape for AI-style demos because real
        //    photo content gives gpt-image-1 / Watercolor / Cartoon a
        //    proper input to transform.
        if let item = makeSystemWallpaperSampleItem() {
            return item
        }
        // 5. Last resort — procedural portrait. Only hit if even the
        //    desktop wallpaper fetch failed (no main screen, sandbox
        //    blocked, …). The app stays functional.
        return makeProceduralPortraitSampleItem()
    }

    // MARK: - Mandrill cache + prefetch

    /// Filename of the cached Mandrill PNG inside `AppStorage.imagesDir`.
    /// Stable so the same bytes survive restarts and the prefetcher's
    /// existence check is cheap.
    private static let mandrillCacheFilename = "Mandrill-cached.png"

    /// USC-SIPI direct PNG URL for the classic 512×512 Mandrill image.
    /// SIPI hosts a public-domain mirror of the entire 1970s test-image
    /// set. The "preview" subpath returns the standard 8-bit PNG
    /// rendering of `misc/4.2.03` (the official Mandrill ID).
    private static let mandrillSourceURL =
        URL(string: "https://sipi.usc.edu/database/preview/misc/4.2.03.png")!

    // Dedup is handled by the file-existence check inside
    // prefetchMandrillIfNeeded(): the synchronous pre-check filters
    // out the common case (file already cached), and the in-task
    // recheck after Task.detached covers near-simultaneous calls.
    // The worst-case race of two parallel downloads ends in an
    // atomic-write tie which is harmless — same bytes, same file.
    // No lock needed (avoids NSLock-in-async-context warnings and
    // the Swift 6 strict-concurrency block on it).

    /// Pick a small system-bundled photo as the sample image. Probes
    /// `/Library/User Pictures/` — Apple's stock account-avatar set
    /// (Animals, Photos, Flowers, Nature, Sports subfolders, each
    /// typically containing 80-512px TIFFs / PNGs). Fast to load
    /// (small files), always present on macOS, no licensing concerns.
    /// Beats grabbing the user's 5K wallpaper which was both slow to
    /// fetch and oversized for a test image even after downscale.
    @MainActor
    private static func makeSystemWallpaperSampleItem() -> ClipboardItem? {
        // Candidate paths in priority order. The Photos subfolder
        // historically held the most photographic content (Astronaut,
        // Earth, Galaxy); Animals has nice photo-real wildlife shots
        // when Photos is absent. Specific filenames change between
        // macOS releases, so we scan each directory rather than hard-
        // coding paths.
        let userPicturesRoot = "/Library/User Pictures"
        let preferredSubdirs = ["Photos", "Animals", "Nature", "Flowers"]
        let fm = FileManager.default
        let validExt: Set<String> = ["png", "tif", "tiff", "jpg", "jpeg", "heic"]

        func firstImageIn(_ dir: String) -> URL? {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
            for name in names.sorted() where validExt.contains((name as NSString).pathExtension.lowercased()) {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                if (try? url.checkResourceIsReachable()) == true { return url }
            }
            return nil
        }

        var picked: URL?
        for sub in preferredSubdirs {
            let dir = userPicturesRoot + "/" + sub
            if let url = firstImageIn(dir) { picked = url; break }
        }
        // Last fallback inside User Pictures — root directory itself.
        if picked == nil { picked = firstImageIn(userPicturesRoot) }

        guard let url = picked,
              let data = try? Data(contentsOf: url),
              let img = NSImage(data: data) else {
            // No User Pictures available (sandboxed app, stripped
            // install, …) — render an SF Symbol as the absolute
            // floor. Always works.
            return makeSFSymbolSampleItem()
        }
        // Downscale to ≤ 512 px on the longest side. User Pictures are
        // small to start with so this is usually a no-op; the
        // downscale is the safety net for unusually-sized custom
        // pictures the admin might have dropped in.
        let downsized = downscaleToFit(img, maxSide: 512)
        guard let tiff = downsized.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else {
            return nil
        }
        return persistSample(pngData: png,
                             image: downsized,
                             stableFilename: "drpaste-test-systempicture.png")
    }

    /// Absolute floor fallback — render an SF Symbol photo glyph on a
    /// soft background as a 256×256 PNG. No external file access
    /// required, works under any sandboxing regime. Visually obvious
    /// "this is a placeholder" so the user knows to drop their own
    /// image if they want a meaningful test.
    @MainActor
    private static func makeSFSymbolSampleItem() -> ClipboardItem? {
        let size = NSSize(width: 256, height: 256)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        NSColor(srgbRed: 0.92, green: 0.94, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        if let symbol = NSImage(systemSymbolName: "photo.on.rectangle.angled",
                                accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 96, weight: .regular)
                .applying(.init(paletteColors: [
                    NSColor(srgbRed: 0.30, green: 0.45, blue: 0.70, alpha: 1)
                ]))
            let glyph = symbol.withSymbolConfiguration(cfg) ?? symbol
            let rect = NSRect(x: (size.width - glyph.size.width) / 2,
                              y: (size.height - glyph.size.height) / 2,
                              width: glyph.size.width,
                              height: glyph.size.height)
            glyph.draw(in: rect)
        }
        guard let tiff = image.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else {
            return nil
        }
        return persistSample(pngData: png,
                             image: image,
                             stableFilename: "drpaste-test-sfsymbol.png")
    }

    /// Lanczos-quality downscale to fit within `maxSide` pixels on the
    /// longest edge, preserving aspect ratio. Skipped if the source is
    /// already within bounds — no needless re-encode.
    private static func downscaleToFit(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let s = image.size
        guard s.width > maxSide || s.height > maxSide else { return image }
        let scale = min(maxSide / s.width, maxSide / s.height)
        let target = NSSize(width: s.width * scale, height: s.height * scale)
        let out = NSImage(size: target)
        out.lockFocus()
        defer { out.unlockFocus() }
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: NSRect(origin: .zero, size: s),
                   operation: .copy,
                   fraction: 1.0)
        return out
    }

    /// Build a ClipboardItem from the cached Mandrill PNG if it's on
    /// disk; nil otherwise. Same persistence shape as the bundled and
    /// procedural variants — single helper writes to blobs/.
    @MainActor
    private static func makeCachedMandrillSampleItem() -> ClipboardItem? {
        let cached = AppStorage.imagesDir.appendingPathComponent(mandrillCacheFilename)
        guard FileManager.default.fileExists(atPath: cached.path),
              let data = try? Data(contentsOf: cached),
              let img = NSImage(data: data) else { return nil }
        return persistSample(pngData: data,
                             image: img,
                             stableFilename: "drpaste-test-mandrill.png")
    }

    /// One-shot best-effort download. Skips if the cache already
    /// exists, no-ops if the network call fails. Runs on a detached
    /// Task so the UI thread isn't blocked. First-launch UX: user
    /// sees the system-image fallback immediately (no waiting),
    /// Mandrill swaps in the next time `makeSampleImageItem()` runs
    /// — usually within seconds of opening the editor.
    private static func prefetchMandrillIfNeeded() {
        let cached = AppStorage.imagesDir.appendingPathComponent(mandrillCacheFilename)
        // Synchronous pre-check filters out the steady-state case
        // (file already cached) without spinning up a Task.
        if FileManager.default.fileExists(atPath: cached.path) { return }
        Task.detached(priority: .utility) {
            // Recheck inside the task — covers the near-simultaneous
            // case where two callers passed the pre-check before
            // either Task started running. Tiny window, but
            // eliminating it costs nothing.
            if FileManager.default.fileExists(atPath: cached.path) { return }
            do {
                var req = URLRequest(url: mandrillSourceURL)
                req.timeoutInterval = 10
                // Identify ourselves so SIPI logs aren't surprised by
                // a bare URLSession default UA. No tracking — just
                // courtesy.
                req.setValue("DrPaste/\(AppBrand.version) (macOS clipboard manager)",
                             forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else { return }
                // Sanity check — it must decode as an image before
                // we cache it. Protects against the unlikely case of
                // SIPI returning an HTML 404 page with 200 status.
                guard NSImage(data: data) != nil else { return }
                // Atomic write so a concurrent reader never sees a
                // partial file. If two parallel downloads finish at
                // the same time both write the same bytes; the
                // atomic-rename semantics make this race a no-op.
                try data.write(to: cached, options: .atomic)
            } catch {
                // Silent — network unavailable / SIPI down / etc.
                // The system-image fallback keeps working in the
                // meantime. Next launch will retry the prefetch.
            }
        }
    }

    /// Load a `Mandrill.png` (or .jpg) packaged in the app bundle and
    /// hand it back as a ClipboardItem ready to feed any image action.
    /// Returns nil when the resource isn't present — the procedural
    /// fallback path runs in that case so the app still works.
    @MainActor
    private static func makeBundledMandrillSampleItem() -> ClipboardItem? {
        // Try common image formats — user might drop a PNG or JPEG.
        let candidates: [(name: String, ext: String)] = [
            ("Mandrill", "png"),
            ("Mandrill", "jpg"),
            ("Mandrill", "jpeg"),
            ("mandrill", "png"),
            ("mandrill", "jpg")
        ]
        for (name, ext) in candidates {
            guard let url = Bundle.module.url(forResource: name, withExtension: ext),
                  let data = try? Data(contentsOf: url),
                  let img = NSImage(data: data) else { continue }
            // Re-encode whatever format the user supplied as PNG so
            // downstream paths that assume `public.png` representation
            // (gpt-image-1 image-edits, the BigHUD preview thumbnailer,
            // PasteboardWriter) all work uniformly.
            let pngData: Data
            if ext == "png" {
                pngData = data
            } else if let tiff = img.tiffRepresentation,
                      let bmp = NSBitmapImageRep(data: tiff),
                      let png = bmp.representation(using: .png, properties: [:]) {
                pngData = png
            } else {
                continue
            }
            return persistSample(pngData: pngData,
                                 image: img,
                                 stableFilename: "drpaste-test-mandrill.png")
        }
        return nil
    }

    /// Procedural fallback when no bundled Mandrill resource is found.
    /// Draws a stylised portrait of a person in a wide-brimmed hat —
    /// keeps the "recognisable subject + rich colour + embedded text"
    /// invariants the AI / grayscale / OCR demos need.
    @MainActor
    private static func makeProceduralPortraitSampleItem() -> ClipboardItem? {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // === Background — soft warm gradient (peach → rose → twilight).
        // Bottom-up so the warm tones sit behind the figure's torso
        // and the cooler dusk colour frames the hat.
        let bg = NSGradient(colors: [
            NSColor(srgbRed: 1.00, green: 0.86, blue: 0.72, alpha: 1),  // warm peach
            NSColor(srgbRed: 0.98, green: 0.70, blue: 0.74, alpha: 1),  // soft rose
            NSColor(srgbRed: 0.55, green: 0.45, blue: 0.68, alpha: 1)   // twilight lavender
        ])
        bg?.draw(in: NSRect(origin: .zero, size: size), angle: 270)

        // === Decorative sun disc behind the figure — adds a focal
        // bright spot that AI styles can re-render as a halo / sun /
        // window depending on the prompt.
        NSColor(srgbRed: 1.00, green: 0.96, blue: 0.78, alpha: 0.55).setFill()
        NSBezierPath(ovalIn: NSRect(x: 156, y: 260, width: 200, height: 200)).fill()

        // === Shoulders / torso — coral-pink triangle anchoring the
        // composition. Drawn first so face/hair/hat sit on top.
        NSColor(srgbRed: 0.86, green: 0.38, blue: 0.42, alpha: 1).setFill()
        let torso = NSBezierPath()
        torso.move(to: NSPoint(x: 100, y: 0))
        torso.line(to: NSPoint(x: 175, y: 180))
        torso.line(to: NSPoint(x: 337, y: 180))
        torso.line(to: NSPoint(x: 412, y: 0))
        torso.close()
        torso.fill()

        // Torso highlight stripe (collar) — adds detail for sketch
        // hatching demonstrations.
        NSColor(srgbRed: 1.0, green: 0.95, blue: 0.95, alpha: 0.9).setFill()
        let collar = NSBezierPath()
        collar.move(to: NSPoint(x: 220, y: 150))
        collar.line(to: NSPoint(x: 256, y: 110))
        collar.line(to: NSPoint(x: 292, y: 150))
        collar.line(to: NSPoint(x: 256, y: 175))
        collar.close()
        collar.fill()

        // === Hair — wavy outline visible under the hat brim on both
        // sides. Warm chestnut colour.
        NSColor(srgbRed: 0.40, green: 0.22, blue: 0.18, alpha: 1).setFill()
        let hair = NSBezierPath()
        hair.move(to: NSPoint(x: 175, y: 195))
        hair.curve(to: NSPoint(x: 195, y: 290),
                   controlPoint1: NSPoint(x: 165, y: 230),
                   controlPoint2: NSPoint(x: 175, y: 270))
        hair.line(to: NSPoint(x: 317, y: 290))
        hair.curve(to: NSPoint(x: 337, y: 195),
                   controlPoint1: NSPoint(x: 337, y: 270),
                   controlPoint2: NSPoint(x: 347, y: 230))
        hair.line(to: NSPoint(x: 295, y: 195))
        hair.line(to: NSPoint(x: 217, y: 195))
        hair.close()
        hair.fill()

        // === Face — warm beige oval.
        NSColor(srgbRed: 0.96, green: 0.83, blue: 0.72, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 200, y: 200, width: 112, height: 130)).fill()

        // Cheeks — subtle pink blush so AI cartoon style picks up
        // the rosy-cheek convention.
        NSColor(srgbRed: 0.96, green: 0.55, blue: 0.52, alpha: 0.55).setFill()
        NSBezierPath(ovalIn: NSRect(x: 208, y: 232, width: 26, height: 18)).fill()
        NSBezierPath(ovalIn: NSRect(x: 278, y: 232, width: 26, height: 18)).fill()

        // Eyes — simple dark dots, positioned proportionally.
        NSColor(srgbRed: 0.15, green: 0.10, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 220, y: 280, width: 9, height: 11)).fill()
        NSBezierPath(ovalIn: NSRect(x: 283, y: 280, width: 9, height: 11)).fill()

        // Smile — small curve.
        NSColor(srgbRed: 0.55, green: 0.18, blue: 0.20, alpha: 1).setStroke()
        let smile = NSBezierPath()
        smile.move(to: NSPoint(x: 235, y: 232))
        smile.curve(to: NSPoint(x: 277, y: 232),
                    controlPoint1: NSPoint(x: 245, y: 218),
                    controlPoint2: NSPoint(x: 267, y: 218))
        smile.lineWidth = 2.5
        smile.stroke()

        // === Hat — wide brim ellipse + crown trapezoid. Deep teal,
        // the colour that gives the most contrast against the warm
        // background and survives well through grayscale / invert /
        // sketch transformations.
        NSColor(srgbRed: 0.10, green: 0.25, blue: 0.30, alpha: 1).setFill()
        // Brim — wide flat ellipse.
        NSBezierPath(ovalIn: NSRect(x: 120, y: 310, width: 272, height: 60)).fill()
        // Crown — trapezoid sitting on top.
        let crown = NSBezierPath()
        crown.move(to: NSPoint(x: 195, y: 335))
        crown.line(to: NSPoint(x: 210, y: 440))
        crown.curve(to: NSPoint(x: 302, y: 440),
                    controlPoint1: NSPoint(x: 230, y: 460),
                    controlPoint2: NSPoint(x: 282, y: 460))
        crown.line(to: NSPoint(x: 317, y: 335))
        crown.close()
        crown.fill()
        // Hat band — yellow stripe, decorative detail.
        NSColor(srgbRed: 0.96, green: 0.78, blue: 0.30, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 200, y: 332, width: 112, height: 14)).fill()
        // Hat band flower — a tiny red dot anchors the gold stripe.
        NSColor(srgbRed: 0.82, green: 0.20, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 280, y: 332, width: 16, height: 16)).fill()

        // === Caption — "DrPaste sample" at bottom, sized so OCR
        // reliably extracts it. White with mild shadow for contrast
        // over the coral torso.
        let caption = "DrPaste sample" as NSString
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3
        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .bold),
            .foregroundColor: NSColor.white,
            .shadow: shadow
        ]
        let captionSize = caption.size(withAttributes: captionAttrs)
        caption.draw(at: NSPoint(x: (size.width - captionSize.width) / 2, y: 28),
                     withAttributes: captionAttrs)

        // Encode to PNG.
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return persistSample(pngData: png,
                             image: image,
                             stableFilename: "drpaste-test-portrait.png")
    }

    /// Write `pngData` to `AppStorage.imagesDir/stableFilename` and to
    /// the matching `.bin` blob inside `AppStorage.blobsDir`, then
    /// return a transient ClipboardItem pointing at both. Stable per-
    /// source filenames so repeated `Run test` invocations reuse the
    /// same on-disk bytes — no need to fill the images dir with
    /// duplicates of the same sample. The returned item still gets a
    /// fresh UUID each call so per-item caches don't false-hit.
    @MainActor
    private static func persistSample(pngData: Data,
                                       image: NSImage,
                                       stableFilename: String) -> ClipboardItem? {
        let imagesURL = AppStorage.imagesDir.appendingPathComponent(stableFilename)
        let blobName = stableFilename + ".bin"
        let blobURL = AppStorage.blobsDir.appendingPathComponent(blobName)
        do {
            try pngData.write(to: imagesURL, options: .atomic)
            try pngData.write(to: blobURL, options: .atomic)
        } catch {
            return nil
        }
        // Pull real pixel dimensions from the first NSImageRep when
        // available — falls back to NSImage.size for vector / svg
        // fallback cases and to a 512×512 default if everything fails.
        let (w, h): (Int, Int) = {
            if let rep = image.representations.first {
                return (rep.pixelsWide, rep.pixelsHigh)
            }
            let s = image.size
            if s.width > 0, s.height > 0 {
                return (Int(s.width), Int(s.height))
            }
            return (512, 512)
        }()
        return ClipboardItem(
            id: UUID(),
            semantic: .image,
            createdAt: Date(),
            representations: ["public.png": blobName],
            typesOrdered: ["public.png"],
            previewText: "Test image \(pngData.count / 1024) KB",
            previewImageRel: stableFilename,
            originalImageWidth: w,
            originalImageHeight: h,
            originalImageFileSize: pngData.count,
            imageFormat: "PNG",
            sourceBundleID: nil,
            sourceAppName: "Editor Test",
            sourceWindowTitle: nil,
            tags: []
        )
    }

    // MARK: - Rich text sample

    /// Build a `.richText` ClipboardItem from a markdown source string.
    /// Used by `ActionEditor.runTest` to feed rich-text-only actions
    /// (rich_to_wiki, rich_to_md, rich_to_html, rich_to_unicode_style,
    /// paste_as_text, clean_formatting) a real RTF blob — they all
    /// read `representations["public.rtf"]` to extract the
    /// NSAttributedString. Plain-text input would leave them with
    /// nothing to convert and produce mediocre demonstrations.
    ///
    /// Honours inline markdown (`**bold**`, `*italic*`, `` `code` ``,
    /// `[link](url)`) via `NSAttributedString(markdown:)`. Block-level
    /// elements (#, lists) parse as literal text — curated samples
    /// avoid them.
    @MainActor
    static func makeRichTextItem(markdown: String) -> ClipboardItem? {
        guard let attr = RichTextHelpers.markdownToAttributedString(markdown) else {
            return nil
        }
        guard let rtfData = attr.rtf(
            from: NSRange(location: 0, length: attr.length),
            documentAttributes: [:]
        ) else { return nil }
        // Stable per-process filename so repeated test runs reuse
        // the same on-disk blob — no point littering blobs/ with
        // dozens of copies of the same sample.
        let blobName = "drpaste-test-richtext.rtf.bin"
        let blobURL = AppStorage.blobsDir.appendingPathComponent(blobName)
        do {
            try rtfData.write(to: blobURL, options: .atomic)
        } catch {
            return nil
        }
        return ClipboardItem(
            id: UUID(),
            semantic: .richText,
            createdAt: Date(),
            representations: ["public.rtf": blobName],
            typesOrdered: ["public.rtf"],
            previewText: attr.string,
            previewImageRel: nil,
            sourceBundleID: nil,
            sourceAppName: "Editor Test",
            sourceWindowTitle: nil,
            tags: []
        )
    }
}
