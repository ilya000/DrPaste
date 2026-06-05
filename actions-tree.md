# DrPaste — Default actions tree

Snapshot of every action shipped in DrPaste as of **0.57.0**.
Generated from `DefaultTransformationSeed.swift`, `DefaultAISeed.swift`,
standalone `ClipboardAction` registrations in `main.swift`, and
`CuratedDefaults.enabledByDefault`.

**Convention v2 (#A74, 0.56.0).** Action IDs use the form
`<namespace>.<content_kind>.<verb_noun>` where `content_kind` matches
the source `SemanticKind` (`text`, `rich`, `url`, `json`, `table`,
`md`, `code`, `html`, `image`, `files`). Seeded AI lives under
`ai.<content_kind>.<verb_noun>`; `user.*` is reserved for genuinely
user-created descriptors. `builtin.identity` is the sole universal-
anchor exception.

**Status legend:**

- ✅ — curated-on by default (action chip visible in HUD for matching clips).
- ⚪ — palette-only by default (user must enable in Settings → Actions → "Add more…").

The user can flip any of these in Settings → Actions; the curated list
controls only the **first-launch** state and the post-Factory-Reset state.

---

## Paste / general

| Title | ID | Type | Default | Applies to |
|---|---|---|---|---|
| Paste as is | `builtin.identity` | Builtin | ✅ | (anchor — all kinds) |
| Type Slowly | `builtin.text.type_slowly` | Builtin | ✅ | text, code, markdown, url |

## Text — case

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| UPPERCASE | `builtin.text.uppercase` | caseChange (upper) | ✅ | text, markdown, code |
| lowercase | `builtin.text.lowercase` | caseChange (lower) | ✅ | text, markdown, code |
| Title Case | `builtin.text.title_case` | caseChange (title) | ⚪ | text, markdown |
| Sentence case | `builtin.text.sentence_case` | caseChange (sentence) | ⚪ | text, markdown |
| camelCase | `builtin.text.camel_case` | camelCase | ⚪ | text, code |
| snake_case | `builtin.text.snake_case` | snakeCase | ⚪ | text, code |
| kebab-case | `builtin.text.kebab_case` | kebabCase | ⚪ | text, code |

## Text — whitespace / lines

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| Trim whitespace | `builtin.text.trim` | trim | ⚪ | text, markdown, code |
| Sort lines | `builtin.text.sort_lines` | sortLines (asc, case-sens) | ✅ | text, markdown, code |
| Unique lines | `builtin.text.unique_lines` | uniqueLines | ⚪ | text, markdown, code |
| Normalize spaces | `builtin.text.normalize_spaces` | normalizeSpaces | ⚪ | text, markdown |
| Collapse blank lines | `builtin.text.collapse_blank_lines` | collapseBlankLines | ⚪ | text, markdown |
| Remove line breaks | `builtin.text.remove_line_breaks` | removeLineBreaks | ⚪ | text, markdown |

## Text — encoding / derived

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| Base64 encode | `builtin.text.base64_encode` | base64Encode | ⚪ | text, code |
| Base64 decode | `builtin.text.base64_decode` | base64Decode | ⚪ | text, code |
| Slugify | `builtin.text.slugify` | slugify | ⚪ | text |
| Word count | `builtin.text.word_count` | wordCount | ✅ | text, markdown, code |
| Generate QR code | `builtin.text.generate_qr` | generateQR (TextActions.swift) | ✅ | text, url |
| Wrap in quotes | `builtin.text.wrap_quotes` | wrap ("…") | ✅ | text |
| Wrap in parentheses | `builtin.text.wrap_parens` | wrap (…) | ⚪ | text |

## Text — extras

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| Fix keyboard layout | `builtin.text.layout_repair` | layoutRepair (LayoutRepairAction) | ⚪ | text |
| Unit conversion | `builtin.text.unit_conversion` | unitConversion (UnitConversion.swift) | ✅ | text, markdown |
| Extract emails | `builtin.text.extract_emails` | extractEmails | ✅ | text, markdown |
| Extract links | `builtin.text.extract_links` | extractLinks | ⚪ | text, markdown |

## URL

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| Strip tracking | `builtin.url.strip_tracking` | stripTrackingParams | ✅ | url |
| Just the domain | `builtin.url.extract_domain` | URLActions.swift | ✅ | url |
| As Markdown link | `builtin.url.to_md_link` | URLActions.swift | ⚪ | url |
| As HTML link | `builtin.url.to_html_link` | URLActions.swift | ⚪ | url |
| URL encode | `builtin.url.encode` | urlEncode | ⚪ | url |
| URL decode | `builtin.url.decode` | urlDecode | ✅ | url |
| Preview card | `builtin.url.preview_card` | URLActions.swift | ✅ | url |

## JSON

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| Pretty JSON | `builtin.json.pretty` | jsonPretty | ✅ | json, code |
| Minify JSON | `builtin.json.minify` | jsonMinify | ✅ | json, code |
| Extract keys | `builtin.json.extract_keys` | jsonExtractKeys | ✅ | json |
| Flatten | `builtin.json.flatten` | jsonFlatten | ⚪ | json |
| Remove nulls | `builtin.json.remove_nulls` | jsonRemoveNulls | ⚪ | json |
| Validate | `builtin.json.validate` | jsonValidate | ✅ | json, code |

## Code

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| Wrap as code block | `builtin.code.wrap_block` | wrap (\`\`\`…\`\`\`) | ✅ | text, code |
| Tabs → spaces | `builtin.code.tabs_to_spaces` | tabsToSpaces | ✅ | code |
| Spaces → tabs | `builtin.code.spaces_to_tabs` | spacesToTabs | ⚪ | code |
| Pretty code (local) | `builtin.code.pretty_local` | prettyCodeLocal | ✅ | code, json |

## Markdown

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| Markdown → plain text | `builtin.md.to_plain` | mdToPlain | ✅ | markdown |
| Markdown → rich text | `builtin.md.to_rich` | MarkdownActions.swift | ✅ | markdown, text, code |
| Extract headings | `builtin.md.extract_headings` | mdExtractHeadings | ✅ | markdown |
| Extract links | `builtin.md.extract_links` | mdExtractLinks | ⚪ | markdown |

## Table / CSV

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| CSV → JSON | `builtin.table.to_json` | MoreActions.swift | ✅ | table, code |
| CSV → Markdown table | `builtin.table.to_md` | MoreActions.swift | ✅ | table |
| CSV → Wiki table | `builtin.table.to_wiki` | CSVTableActions.swift | ✅ | table |
| CSV → Rich table | `builtin.table.to_rich` | CSVTableActions.swift | ✅ | table |
| CSV → HTML table | `builtin.table.to_html` | CSVTableActions.swift | ✅ | table |

## Rich text

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| Strip formatting | `builtin.rich.strip_formatting` | MoreActions.swift | ✅ | richText |
| Rich → Markdown | `builtin.rich.to_md` | MoreActions.swift | ✅ | richText |
| Rich → HTML | `builtin.rich.to_html` | MoreActions.swift | ✅ | richText |
| Rich → Wiki | `builtin.rich.to_wiki` | MoreActions.swift | ✅ | richText |
| Rich → Unicode styled | `builtin.rich.to_unicode_styled` | MoreActions.swift | ✅ | richText |

## Unicode pseudo-fonts ("Fancy text")

All under the `text.font_*` namespace, all driven by the `unicodeStyle`
engine with a `style` parameter. Each preserves source case (e.g.
`A→𝐀`, `a→𝐚`).

| Title | ID | Style | Default |
|---|---|---|---|
| Bold | `builtin.text.font_bold` | bold | ✅ |
| Italic | `builtin.text.font_italic` | italic | ✅ |
| Bold italic | `builtin.text.font_bold_italic` | boldItalic | ✅ |
| Script | `builtin.text.font_script` | script | ✅ |
| Bold script | `builtin.text.font_bold_script` | boldScript | ✅ |
| Fraktur | `builtin.text.font_fraktur` | fraktur | ✅ |
| Bold fraktur | `builtin.text.font_bold_fraktur` | boldFraktur | ✅ |
| Double struck | `builtin.text.font_double_struck` | doubleStruck | ✅ |
| Sans | `builtin.text.font_sans` | sans | ✅ |
| Sans bold | `builtin.text.font_sans_bold` | sansBold | ✅ |
| Sans italic | `builtin.text.font_sans_italic` | sansItalic | ✅ |
| Sans bold italic | `builtin.text.font_sans_bold_italic` | sansBoldItalic | ✅ |
| Monospace | `builtin.text.font_monospace` | monospace | ✅ |
| Fullwidth | `builtin.text.font_fullwidth` | fullwidth | ✅ |
| Small caps | `builtin.text.font_small_caps` | smallCaps | ✅ |
| Circled | `builtin.text.font_circled` | circled | ✅ |
| Filled circled | `builtin.text.font_filled_circled` | filledCircled | ✅ |
| Squared | `builtin.text.font_squared` | squared | ✅ |
| Filled squared | `builtin.text.font_filled_squared` | filledSquared | ✅ |
| Upside down | `builtin.text.font_upside_down` | upsideDown | ✅ |
| Plain (un-style) | `builtin.text.font_plain` | plain | ✅ |
| From Markdown | `builtin.text.font_markdown` | markdownToUnicode | ⚪ |

## HTML

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| Strip HTML tags | `builtin.html.strip_tags` | htmlStripTags | ✅ | text, code |
| HTML escape | `builtin.html.escape` | htmlEscape | ⚪ | text, code |
| HTML unescape | `builtin.html.unescape` | htmlUnescape | ⚪ | text, code |

## Transliteration

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| Cyrillic → Latin | `builtin.text.cyrillic_to_latin` | cyrillicToLatin | ✅ | text |
| Latin → Cyrillic | `builtin.text.latin_to_cyrillic` | latinToCyrillic | ✅ | text |

## Image

| Title | ID | Source | Default | Applies to |
|---|---|---|---|---|
| OCR (extract text) | `builtin.image.ocr` | ImageActions.swift | ✅ | image |
| Decode QR | `builtin.image.decode_qr` | ImageActions.swift | ✅ | image |
| Strip metadata | `builtin.image.strip_metadata` | ImageActions.swift | ✅ | image |
| Resize (universal) | `builtin.image.resize` | ImageResizeAction.swift | ✅ | image, files, richText |
| Resize ≤ 1920 px | `builtin.image.resize_max_1920` | ImageActions.swift | ⚪ | image |
| Compress as JPEG | `builtin.image.compress_jpeg` | ImageActions.swift | ✅ | image |
| To grayscale | `builtin.image.to_grayscale` | ImageActions.swift | ✅ | image |
| Invert colors | `builtin.image.invert_colors` | ImageActions.swift | ⚪ | image |
| Rotate right 90° | `builtin.image.rotate_right` | ImageActions.swift | ✅ | image |
| Rotate left 90° | `builtin.image.rotate_left` | ImageActions.swift | ✅ | image |
| ASCII art | `builtin.image.to_ascii_art` | ImageActions.swift | ✅ | image |

## Files

| Title | ID | Source | Default | Applies to |
|---|---|---|---|---|
| Copy paths | `builtin.files.copy_paths` | FileActions.swift | ✅ | files |
| Copy filenames | `builtin.files.copy_filenames` | FileActions.swift | ✅ | files |
| As Markdown links | `builtin.files.to_md_links` | FileActions.swift | ✅ | files |
| Reveal in Finder | `builtin.files.reveal_in_finder` | FileActions.swift | ✅ | files |
| Shell-safe paths | `builtin.files.copy_shell_safe_paths` | FileActions.swift | ✅ | files |
| Rich icons | `builtin.files.to_rich_icons` | FileActions.swift | ✅ | files |
| Extract image | `builtin.files.extract_image` | FileToImageAction.swift | ✅ | files |

## Fun / Internet Slang *(palette only, not curated)*

| Title | ID | Engine | Default | Applies to |
|---|---|---|---|---|
| Leetspeak | `builtin.text.leetspeak` | leetspeak | ⚪ | text |
| UwU speak | `builtin.text.uwu_speak` | uwuSpeak | ⚪ | text |
| Zalgo | `builtin.text.zalgo` | zalgo | ⚪ | text |

## AI — text actions (`ai.text.*` and `ai.rich.*`)

Seeded via `DefaultAISeed`. Every entry defaults to enabled at seed time.

| Title | ID | Default model | Applies to |
|---|---|---|---|
| Summarize | `ai.text.summarize` | (default provider) | text, markdown |
| Translate | `ai.text.translate` | (default provider) | text |
| Translate (rich) | `ai.rich.translate` | (default provider) | richText |
| Fix grammar | `ai.text.fix_grammar` | (default provider) | text |
| Fix grammar (rich) | `ai.rich.fix_grammar` | (default provider) | richText |
| Formal tone | `ai.text.formal_tone` | (default provider) | text |
| Latin → Cyrillic (AI) | `ai.text.latin_to_cyrillic` | (default provider) | text |
| Make shorter | `ai.text.make_shorter` | (default provider) | text, markdown |
| Improve clarity | `ai.text.improve_clarity` | (default provider) | text, markdown |
| Make friendly | `ai.text.make_friendly` | (default provider) | text |
| Draft email reply | `ai.text.draft_email_reply` | (default provider) | text |
| Generate email subject | `ai.text.generate_email_subject` | (default provider) | text |
| Clean OCR text | `ai.text.clean_ocr` | (default provider) | text |

## AI — code actions (`ai.code.*`)

| Title | ID | Default model | Applies to |
|---|---|---|---|
| Pretty code | `ai.code.pretty` | (default provider) | code |
| Explain code | `ai.code.explain` | (default provider) | code |
| Find bugs | `ai.code.find_bugs` | (default provider) | code |
| Translate code | `ai.code.translate` | (default provider) | code |

## AI — image actions (`ai.image.*`)

| Title | ID | Provider | Default | Applies to |
|---|---|---|---|---|
| Pencil sketch | `ai.image.sketch` | image-capable picker | ✅ | image |
| Watercolor | `ai.image.watercolor` | image-capable picker | ✅ | image |
| Cartoon | `ai.image.cartoon` | image-capable picker | ✅ | image |

## AI — text → image (`ai.text.image_*`)

| Title | ID | Provider | Default | Applies to |
|---|---|---|---|---|
| Whiteboard sketch | `ai.text.image_whiteboard` | image-capable picker | ✅ | text |

---

## Summary

| Category | Total | Enabled by default | Palette only |
|---|---:|---:|---:|
| Paste / general | 2 | 2 | 0 |
| Text — case | 7 | 2 | 5 |
| Text — whitespace / lines | 6 | 1 | 5 |
| Text — encoding / derived | 7 | 3 | 4 |
| Text — extras | 4 | 3 | 1 |
| URL | 7 | 4 | 3 |
| JSON | 6 | 4 | 2 |
| Code | 4 | 3 | 1 |
| Markdown | 4 | 3 | 1 |
| Table / CSV | 5 | 5 | 0 |
| Rich text | 5 | 5 | 0 |
| Unicode pseudo-fonts | 22 | 21 | 1 |
| HTML | 3 | 1 | 2 |
| Transliteration | 2 | 2 | 0 |
| Image | 11 | 9 | 2 |
| Files | 7 | 7 | 0 |
| Fun / Internet Slang | 3 | 0 | 3 |
| AI text | 13 | 13 | 0 |
| AI code | 4 | 4 | 0 |
| AI image | 3 | 3 | 0 |
| AI text → image | 1 | 1 | 0 |
| **Total shipped** | **126** | **96** | **30** |

---

## Notes on design

- **Convention v2 IDs are for human scanning only.** HUD chip filtering
  is driven by each action's `applicableTypes` + `isApplicable(item:context:)`
  contract, NOT by ID-substring matching. Renaming an ID never changes
  which chips appear in the HUD — that's a function of code.
- **Curated default-on** is intentionally biased toward the **most common
  shapes** for each content type. Casing has 7 variants but only
  UPPERCASE and lowercase are curated-on; Sentence case, Title Case, and
  the three programmer-cases live in the palette to keep the chip strip
  scannable on a quick ⌥⌘V press.
- **Unicode pseudo-fonts are mostly curated-on** by deliberate marketing
  decision — they're the brightest "wow factor" in the chip strip and
  the user can disable variants they don't want in two clicks. The
  outlier is `font_markdown` (parses `**bold**` markup span-by-span)
  which is palette-only because it's narrower in scope.
- **Fun / Internet Slang trio (Leetspeak / UwU / Zalgo) is palette-only**
  by design — keeps the default chip strip serious; the user opts in
  when they want them.
- **AI seeds bypass the curated table** — every entry in `DefaultAISeed`
  defaults to `enabled = true` on the descriptor itself, regardless of
  the CuratedDefaults table. To disable an AI seed at first launch you
  flip its descriptor flag, not the curated list.
- **`builtin.identity` is an anchor**, not a real transformation — it's
  a Tier-0 entry that pastes the original clip untouched. Lives in
  `IdentityAction`.
- **`paste_as_text` + `clean_formatting` merged.** Both used to flatten
  rich text to plain text. Now a single `builtin.rich.strip_formatting`.
- **AI text categories.** `ai.text.*` is plain-text in, plain-text out.
  `ai.rich.*` is reserved for rich-text-preserving variants of the same
  prompts (translate / fix_grammar today; more under #A73). `ai.code.*`
  groups code-shaped prompts. `ai.image.*` is image → image. The single
  `ai.text.image_whiteboard` is text → image.

---

## What's NOT shipped

These IDs appeared in earlier brainstorm trees but **don't exist in
code today**:

- `text.remove_empty_lines` — covered by `text.collapse_blank_lines`.
- `json.escape_string`, `json.unescape_string` — narrow utility,
  defer until requested.
- `fun.lolspeak_ai`, `fun.olbanian_ai`, `fun.hacker_terminal_ai` —
  deferred. The local Fun trio (leet / uwu / zalgo) ships; AI fun
  variants need design.
- `code.translate_to_<specific_language>` seeds — only the generic
  `ai.code.translate` ships. The user picks target language in the
  prompt body.
- Block-level Markdown survival across AI rich roundtrip — only
  inline markdown (bold / italic / code / links) survives today.
  Block-level (lists, headings) round-trips as inline-only fidelity.
  See #A73 for the future expansion.
