---
name: drpaste
description: Project memory and working context for DrPaste — a native macOS clipboard extension built around a press-and-hold philosophy ("an extension of the Paste gesture itself"). The "Dr" in DrPaste reads as "scholarly / educated" (PhD), not "doctor / medical". Load this skill whenever the conversation mentions DrPaste, Dr Paste, paste manager, paste extension, macOS clipboard manager, clipboard HUD, press-and-hold paste, ⌥⌘V HUD, intelligent paste, Flycut / Jumpcut / Maccy / Paste alternatives, or BYO-AI paste tools. The earlier working name was ClipMacPoC (also a trigger). Covers the full design brief, architectural decisions, file-by-file responsibilities, implementation subtleties (CGEventTap vs Carbon vs NSEvent.addGlobalMonitor, NSPanel non-activating vs key-window, simulated paste, keyboard layout repair, Full Gesture vs Limited Mode auto-detect), current status, and roadmap.
---

# DrPaste

Native macOS clipboard utility built around press-and-hold UX. Goal is not "yet another clipboard manager" but **an extension of the system Paste gesture itself**.

Original working name: **ClipMacPoC**. Final product name: **DrPaste** (chosen 25 May 2026). The "Dr" semantic is **PhD / scholar / educated**, not medical. The icon reflects this: clipboard + mortarboard cap, not a medical cross.

Current version: **0.59.0** (alpha, unsigned SwiftPM build).

## Project location

```
~/Dropbox/Claude My/DrPaste/
  Package.swift
  README.md                         English, publishable
  LICENSE                           GPL-3.0-or-later + attribution §7(d)
  SKILL.md                          this file
  BACKLOG.md                        active items + condensed changelog
  HELP.md                           Russian end-user guide (16 sections)
  .gitattributes                    LF for all text files
  Sources/DrPaste/
    main.swift                      AppDelegate, bootstrap, AX monitor, hotkey dispatch
    AppBrand.swift                  AppBrand.name = "DrPaste", icons, About credits, version
    AppTheme.swift                  Default / Vivid / Soft / Ocean theme palettes
    ClipboardModel.swift            ClipboardItem, Store, Watcher, AppStorage paths,
                                    isEffectivelyEmpty filter;
                                    SemanticKind enum + per-clip detection live here
                                    (no separate SemanticClassifier file)
    ContextDetector.swift           local content classifier (ContentContext bitmask)
    Actions.swift                   protocol ClipboardAction + ActionRegistry +
                                    Identity / LayoutRepair / CleanFormatting +
                                    seed orchestration (seedAI / seedTransformations /
                                    rebrandFancyTextIfNeeded /
                                    expandMarkdownExtractTypesIfNeeded)
    DefaultTransformationSeed.swift bundled builtin.* transformation descriptors
                                    (currentSeedVersion = 6, ~28 entries)
    CustomTransformation.swift      TransformationEngine enum + runtime + descriptor model;
                                    rich-text-preserving branch for applicable engines
    AIProvider.swift                multi-provider AI registry + concrete providers +
                                    AIAction (text→text); stream() protocol method;
                                    cost-aware cheapestEnabledImageProvider() cache;
                                    Anthropic / OpenAI-compat / Gemini SSE finishers
    AIImageActions.swift            AIImageAction (image→image) and
                                    AITextToImageAction (text→image) action types;
                                    OpenAI gpt-image-1 wire format,
                                    Gemini imagen path, OpenRouter image route
    UsageProbe.swift                OpenAI cost probe + OpenRouter credit probe;
                                    silent hide on 401/403; anchor reset on machine switch
    AIPromptTemplates.swift         seed prompts for Translate / Fix / Polish / image styles;
                                    quality directive parser
    KeyboardLayoutRepair.swift      QWERTY ↔ ЙЦУКЕН swap + NSSpellChecker scoring
    HotkeyEngine.swift              EventTapEngine + CarbonHotKeyEngine +
                                    GlobalMonitorEngine + factory; ⌥⌘⏎ paste-and-keep;
                                    hold-detection for per-action hotkeys
    HotkeyRecorder.swift            assign-a-hotkey-to-an-action UI;
                                    system-shortcut conflict block with feature names
    ActionHotkey.swift              per-action hotkey descriptor + Carbon manager;
                                    DrPaste reserved chord names
    BigHUD.swift                    primary HUD: NSPanel + SwiftUI view + accumulator;
                                    formerly HUD.swift, renamed in 0.19.0
    MiniHUD.swift                   transient mini-window for direct-trigger AI / progress;
                                    formerly ProgressHUD.swift; draggable; 90s watchdog;
                                    completion UX (green Done pill)
    AppendAccumulator.swift         universal NSAttributedString accumulator for ⌥⌘S;
                                    NSTextAttachment(fileWrapper:) for RTFD images;
                                    files-strict track + rich/image bridge
    PasteSimulator.swift            ⌘V/⌘C/⌘X via CGEvent + PasteboardWriter;
                                    simulatePasteKeepingHeldModifiers() with .privateState +
                                    cgAnnotatedSessionEventTap for ⌥⌘⏎
    SettingsWindow.swift            TabView Settings: General, AI, per-content tabs;
                                    Factory Reset; Import/Export
    ActionEditor.swift              unified editor for builtin / AI / transformation actions;
                                    multi-window controller; Duplicate (sibling spawn);
                                    Provider picker with reroute indicator
    ActionPaletteSheet.swift        "Add more actions" palette for re-enabling actions
    BuiltinActionEditor.swift       descriptions metadata for built-ins
    BuiltinActionIcons.swift        SF Symbol mapping for built-in action ids
    BuiltinActionMetadata.swift     (legacy stub — most metadata lives in BuiltinActionEditor)
    CuratedDefaults.swift           default-enabled subset for first launch
    APIKeyStorage.swift             Keychain wrapper + plain-JSON fallback;
                                    Keychain disabled in 0.14.0 (restore in #A1)
    RichTextHelpers.swift           NSAttributedString ↔ Markdown / HTML / Wiki;
                                    markdownToAttributedString uses native API
    RichTextPreviewView.swift       NSTextView wrapper used by HUD and Settings;
                                    com.apple.flat-rtfd priority
    AboutWindow.swift               custom 560×500 About panel
    WelcomeWindow.swift             first-launch panel with AX guidance
    SoundFeedback.swift             cue throttling and preview playback
    ContentMeta.swift               on-demand "N words, N chars" metadata cache
    TypeSimulator.swift             Type Slowly engine; defaultBaseDelay = 0.133 s
                                    (1.5× faster than original 0.2 s);
                                    auto-cancel on user activity
    TextActions.swift               Generate QR (image-producing action)
    JSONActions.swift               Flatten, Remove nulls
    URLActions.swift                Just domain, Markdown / HTML link, query params
    MoreActions.swift               Table converters, Rich → MD / HTML / Wiki, Paste as text
    FileActions.swift               File-reference actions (paths, names, SHA, reveal)
    ImageActions.swift              OCR, decode QR, strip metadata, resize, grayscale, …;
                                    ASCII art (40-col default, monospaced rich-text output)
    MarkdownActions.swift           MarkdownToRichTextAction (builtin.md_to_rich);
                                    other markdown handlers migrated to engines
    UnicodeStyles.swift             pseudo-font tables (~20 styles) + applyMarkdown
                                    for builtin.font_markdown
    ScreenRegionCapture.swift       ⌥⌘ + drag region capture (#A11);
                                    full-screen overlay, dim layer, crosshair cursor
    RegionCaptureCheatSheet.swift   corner cheat sheet shown on ⌥⌘ hold;
                                    Settings toggle to disable
    ActionConfig.swift              ActionConfig Codable root + preferences + seed versions
    ActionTestSamples.swift         per-action curated test samples (text + image);
                                    persisted custom samples
    TestOutputPane.swift            playground result pane; TypeSlowlyPreview animator
    ContentMeta.swift               (already listed above)
    Resources/
      AppIcon.svg                   placeholder vector icon
                                    (a higher-quality PNG can be dropped in alongside
                                     and AppBrand.nsIcon's lookup chain will pick it up;
                                     no production AppIcon.png is checked in today)
      MenuBarIcon.svg               monochrome template (clipboard + ⌘V)
      RichTextSamples/              fixed RTF sample for the Rich Text playground
      Sounds/                       bundled aiff cues
```

Note on the image-action test sample (Mandrill): the bundled
`Mandrill.png` resource is OPTIONAL — when missing, the lookup chain in
`ActionTestSamples.makeSampleImageItem()` falls back to (a) a previously
downloaded / user-dropped Mandrill cached in Application Support, (b)
a system image picked from `/Library/User Pictures`, (c) an SF Symbol
silhouette. User documentation should say "Mandrill where available,
otherwise a system fallback" rather than promising a bundled Mandrill.

The `.build/` directory contains many small build artefacts — exclude it from Dropbox Selective Sync.

## Concept (one-liner)

User holds `⌥⌘V` → BigHUD overlay appears → `↑↓` browses clipboard history, `←→` switches between actions, live preview updates → user releases the modifiers → the current preview is pasted at the cursor of the frontmost app. Escape aborts.

**Dr = "educated paste".** The product diagnoses content context (URL / JSON / wrong layout / Markdown / code) and surfaces only the relevant transformations.

## Design principles

- **Press-and-Hold** — "press, choose, release, paste".
- **Preview-First** — every transformation is shown before commit, with token streaming for AI actions so partial results appear live (no opaque spinner wait).
- **Context-Aware Actions** — determined locally; only the relevant ones are shown.
- **Local-first** — useful without AI and without an internet connection.
- **Bring Your Own AI is free forever** — no bundled backend, no metering when using personal keys.
- **Honest provider routing** — every UI surface that names a provider shows the *real* executor; soft-fallback to a working provider for capability mismatches is surfaced with a visible reroute indicator and an explanation hint, never silently.
- **Keyboard-first, mouse-available** — same posture as Spotlight or Cmd-Tab.
- **System HUD aesthetic** — translucent, light/dark, system accent.
- **Graceful degradation** — works without Accessibility permission (Limited Mode).
- **Open source** — GPL-3.0 with attribution, community-extensible.

### Two-surface model — HUD runs, Settings manages

The HUD is the runtime surface: it shows only what is
`enabled && applicable && context-matching`, because the user is mid-paste
and any extra row costs speed. The Settings window is the management
surface: it shows **everything**, including disabled actions (rendered
dimmed). Disabled rows in Settings are not noise — they are how users find
and re-enable, rename, edit `Applies to`, or reassign hotkeys for actions
they previously turned off. Never collapse the two surfaces into one;
never hide disabled actions from Settings; never push runtime filtering
into the management view.

### Action hierarchy — three tiers of depth

DrPaste curates the action surface so each user goes only as deep as their
actual need.

- **Tier 1 — Out of the box (90% of users).** Each content type ships with
  a hand-picked default-enabled subset of about half a dozen actions chosen
  for "obviously useful, immediately." This is what the user sees in the
  HUD on day one without ever opening Settings. The
  `CuratedDefaults.enabledByDefault` set governs this tier; new bundled
  actions default to **disabled** unless they earn a place in the curated
  subset.
- **Tier 2 — Toggle in Settings (extra 9%, 99% cumulative).** A user who
  wants more — or wants to silence a default they don't use — flips a
  checkbox in `Settings → <content-tab>` or browses the palette to enable
  extras. No code, no editing of internals, no decision about parameters
  — just a binary "I want / don't want." This is where the long tail of
  bundled actions lives.
- **Tier 3 — Custom actions and parameter editing (power users).** The
  bottom 1% who want a transformation tuned to their workflow open the
  editor: rename, re-scope `Applies to`, change engine parameters, write
  a custom AI prompt, or build a brand-new descriptor from scratch.

Design implication: every new action ships **disabled by default** outside
the curated set. The Tier 2 surface (Settings palette + per-tab list)
must stay legible — that's why we filter the engine picker by useful
categories instead of dumping every internal capability on the user.
The Tier 3 surface (ActionEditor) is expected to look denser — power
users earn that density.

## Architectural decisions

**Stack.** Swift 5.9 + SwiftUI + AppKit + Carbon.HIToolbox, macOS 13+.
SwiftPM executable, no Xcode project, no external dependencies.

**Hotkey: ⌥⌘V in both modes.** The conflict with Microsoft Word
"Paste Special" is accepted deliberately.

**Three hotkey engines with auto-detect:**

| Engine | Use | Permission | Can swallow events |
|---|---|---|---|
| `EventTapEngine` | Full Gesture Mode (production) | requires AX | yes |
| `CarbonHotKeyEngine` | Limited Mode (fallback) | none | no |
| `GlobalMonitorEngine` | debug only | requires AX | no |

Selection rule: `AXIsProcessTrusted()` true → EventTap, false → Carbon.
Environment override: `CLIPMAC_ENGINE=tap|carbon|monitor`.

**Two HUD entities (split in 0.19.0):**

- **BigHUD** (`BigHUD.swift`) — primary surface for the press-and-hold
  gesture. NSPanel with two `styleMask` variants depending on Gesture vs
  Limited Mode. Hosts the history strip + actions bar + preview pane +
  footer legend. Owns the in-HUD accumulator state (`anchorIndex`,
  `consumedIndices`).
- **MiniHUD** (`MiniHUD.swift`) — transient mini-window shown for
  direct-trigger actions (per-action hotkey) and for AI loading state.
  Draggable (`isMovableByWindowBackground`). Has cancel ✕, watchdog
  (90 s detached task to escape main-actor congestion), completion UX
  (green "Done · X.Xs" pill).

In 0.19.0 the formerly-single `HUD.swift` was split into BigHUD/MiniHUD
because they had grown different responsibilities and the shared file was
hard to reason about. The "single HUD" architectural principle survived
as "BigHUD's surface is single" (one SwiftUI view, one panel, two
styleMask variants for Gesture vs Limited) — but MiniHUD lives in its
own file.

**BigHUD panel variants (single class, parameterised):**

- **`.gesture`** (Full): `NSPanel` with `styleMask: [.borderless,
  .nonactivatingPanel]`, `canBecomeKey: false`, `level: .statusBar`.
  EventTap swallows all key presses while the HUD is active. Commit on
  release of modifiers.
- **`.summon`** (Limited): same `NSPanel` with `styleMask: [.borderless,
  .titled, .fullSizeContentView]`, `canBecomeKey: true`, brought up via
  `makeKeyAndOrderFront`. Local key monitor catches Enter / Esc / arrows /
  `⌘±`. Commit on Enter or double-click. A "Limited Mode — press Enter to
  paste. Enable Accessibility for release-to-paste" banner appears with
  an inline "Open Settings…" button.

**AX trust monitor.** A background `Timer` polls `AXIsProcessTrusted()`
every 3 s. On `false → true` transition it shows an `NSAlert` offering
to restart; on the reverse transition the next launch silently downgrades.

**HUD design highlights:**

1. **Actions bar:** horizontal `ScrollView` + `ScrollViewReader.scrollTo`
   with a 0.18 s animation. Edge `mask(LinearGradient)` for fade-out.
2. **Mouse support:** `BigHUDHostingView<Content: View>: NSHostingView`
   overrides `acceptsFirstMouse(for:) -> true`. Single-click selects
   (updates preview, HUD stays open), double-click commits. `onHover`
   for highlight.
3. **Rich text preview:** `NSTextView` wrapped in `NSViewRepresentable`
   (RichTextPreviewView). Foreground colors are remapped to
   `NSColor.labelColor` so Dark Mode is legible. RTFD with embedded image
   attachments survives via `com.apple.flat-rtfd` priority lookup.
4. **Streaming AI preview** (#A9, shipped 0.14.0): `AIProvider.stream(...)`
   returns `AsyncThrowingStream<String, Error>`. Anthropic / OpenAI-compat
   / Gemini implementations parse SSE and yield delta chunks. BigHUD and
   MiniHUD consume the stream and update preview as tokens arrive. Stream
   finishers (`message_stop`, `finishReason`, `[DONE]`) break the loop
   cleanly. 90s detached watchdog in MiniHUD as belt-and-braces.
5. **AppBrand** — single source of truth for name, icons, version, About
   credits. `Bundle.module.url(forResource:withExtension:)` via
   `.process("Resources")` in Package.swift.
6. **Font scale:** `BigHUDState.fontScale: CGFloat` persisted in
   `UserDefaults`. Bounds 0.7..1.6 in 0.1 steps.
7. **Dynamic visibleRowCount + chevrons:** `Int(round(11.0 / fontScale))`
   clamped to `5...items.count`. Window centers on the active item and
   clamps to edges.
8. **Themes** (`AppTheme.swift`): Default / Vivid / Soft / Ocean. Reach
   BigHUD, MiniHUD, region-capture cheat sheet.

**Context detection.** `ContextDetector.detect(item) -> ContentContext`
(bitmask). Local heuristics only, no AI / network call.

**Action registry.**
`protocol ClipboardAction { id, title, isLocal, isApplicable, apply async }`.
Local actions run synchronously. AI calls run async with a loading state
and a `previewToken` so stale results from previous focus do not overwrite
the current preview. Direct-trigger AI hotkeys spawn MiniHUD with the
same streaming loading panel.

**Transformation engines.** Every bundled built-in transformation lives
in `config.customTransformations` as a `CustomTransformationDescriptor`
seeded on first launch via `DefaultTransformationSeed`. Users rename,
retitle, reorder, change parameters, or fully delete them through the
same editor that handles user-created transformations.
Current seed version: **6**. Migrations:
- v3 — fancy-text rebrand + Regional Indicator removal.
- v4 — Cyrillic → Latin transliteration seeded.
- v5 — `md_headings` / `md_links` applicableTypes expanded to
  `[markdown, text, richText]` so they apply to rich-text clips
  (via `RichTextHelpers.attributedStringToMarkdown` recovery).
- v6 — `builtin.font_markdown` (Markdown styles → Unicode) seeded.

**Hardcoded ClipboardAction subclasses** (not descriptor-backed) live in
TextActions / JSONActions / URLActions / MoreActions / FileActions /
ImageActions / MarkdownActions / TypeSimulator. These are actions that
don't fit the "engine + parameters" model — they're full image OCR
pipelines, multi-step file extracts, Type Slowly, etc.

**AI provider abstraction.** `protocol AIProvider`. Concrete
implementations: Anthropic, OpenAI-compatible (covers OpenAI / Grok /
Mistral / DeepSeek / Groq / Cerebras / Together / Cloudflare Workers AI),
Gemini, OpenRouter, Ollama, LM Studio, llama.cpp, custom. Registry:
`AIProviderRegistry.shared`. Keys live in Keychain via `APIKeyStorage`
(currently routed to plain-JSON fallback in 0.14.0; restore in #A1).
Default provider chosen via radio button in Settings and auto-promoted
after the first successful connection test.

**Cost-aware image-provider auto-select.** When a default chat provider
can't run image actions (e.g. default = Anthropic, action = Text→Image),
runtime soft-falls-back to the cheapest enabled image-capable provider
in priority order: **Gemini → OpenRouter → OpenAI → Custom**. The
chosen provider is surfaced honestly across every UI surface:
- Action editor: provider chip + reroute indicator (orange glyph)
  + hint sentence ("Default chat provider Anthropic can't run image
  actions. Routed to Gemini.").
- HUD action chip: provider icon = real executor.
- Settings list: provider badge = real executor.

**Usage stats** (OpenAI cost + OpenRouter credits) live in
`UsageProbe.swift`. Probe runs per provider:
- OpenAI: `/v1/organization/costs` with regular API key (no admin
  scope required). Silent hide on 401/403 (key without billing scope).
- OpenRouter: `/api/v1/credits`. Anchor (first-seen credit balance for
  the day) resets on machine switch / lifetime regression / account
  re-key.

**Persistence.** JSON + PNG blobs under
`~/Library/Application Support/DrPaste/`. Up to 500 items,
deduplication, trim. `AppStorage` enum encapsulates paths.

**Keyboard layout repair.** Character mapping QWERTY ↔ ЙЦУКЕН.
Scoring via `NSSpellChecker.checkSpelling`. The Cyrillic table is the
only non-English content left in the source tree — it's data, not a
comment.

**Append accumulator** (`AppendAccumulator.swift`). Universal
NSAttributedString accumulator for ⌥⌘S Append Copy:
- `attributedString(forImage:)` uses `NSTextAttachment(fileWrapper:)`
  with PNG FileWrapper (the cell form was dropped by the RTFD encoder).
- Two-track model: rich-text track (red menu-bar dot) + files-strict
  track (cyan dot).
- Bidirectional bridge: an image-file clip merging into a rich track
  becomes an inline attachment; a rich-text fragment merging into a
  pure-image-files track flips the track to rich.
- 120 s session timeout; session resets on any other DrPaste hotkey.

**Region capture** (`ScreenRegionCapture.swift`, #A11, shipped 0.22.0):
⌥⌘ + drag captures a screen region as PNG, drops it into clipboard
history, opens BigHUD focused on the capture. Implementation:
- **0.40 s grace timer** before arming (raised from the original
  250 ms in 0.24.x — #173 found that the shorter window let normal
  ⌥⌘<letter> chords occasionally trip the cursor swap mid-press;
  the longer grace stabilises detection for typical chord typing
  speeds). Lives in `HotkeyEngine.swift` around the flagsChanged
  handler that gates the cursor overlay.
- Full-screen transparent NSPanel overlay per `NSScreen` for the
  selection rectangle + dim layer.
- ScreenCaptureKit (macOS 12.3+) preferred; falls back to
  `CGWindowListCreateImage` pre-SCK.
- Source-app metadata extracted from `kCGWindowOwnerPID` so HUD shows
  "Captured from Safari" / "Captured from Pages".

**Per-action hotkey hold-preview** (#A10, shipped 0.18.0): assigning
⌥⌘<letter> to an action runs it directly on tap-and-release — the
result either pastes immediately (text-cheap actions) or surfaces in
**MiniHUD** as a streaming AI-loading panel (slow actions).
**Hold-after-letter** (the user releases the letter but keeps ⌥⌘
down for ≥250 ms) calls `openBigHUDFocusedOnAction(_:)` — **BigHUD
opens pre-focused on that exact action**, with normal Gesture-Mode
commit semantics (release ⌥⌘ to paste, Esc to cancel, ←→ to swap
actions, ⌫ to delete, etc.). The hold-preview surface is therefore
BigHUD, not MiniHUD. Detection lives in HotkeyEngine's flagsChanged
handler.

## Icon

"Dr" reads as **PhD / scholar / educated**, not medical. The current
checked-in icon is `AppIcon.svg` — a vector placeholder.
`AppBrand.nsIcon` has a multi-step lookup chain that prefers, in
order: an Asset Catalog hit (signed builds), `AppIcon.icns`,
`AppIcon@2x.png`, `AppIcon.png`, then `AppIcon.svg`, then an SF
Symbol fallback. So dropping a higher-resolution PNG / icns into
Resources will automatically take precedence over the SVG without any
code change. `MenuBarIcon.svg` is a monochrome template version of the
same idea, tinted by macOS to match system appearance.

## Build & run

```bash
cd ~/Dropbox/"Claude My"/DrPaste
swift run
```

Release build: `swift build -c release && ./.build/release/DrPaste`.

With an environment-provided Anthropic key:
`ANTHROPIC_API_KEY=sk-ant-... swift run`.

To force a specific engine: `CLIPMAC_ENGINE=monitor swift run`.

## License

GPL-3.0-or-later with attribution requirement via GPL §7(d). `LICENSE`
contains the attribution clause and a pointer to the canonical text.

Copyright `© 2026 iLya Os`. The handle `iLya Os` is the standard form
used in copyright headers.

## Notable implementation gotchas

- **`ClipboardItem.semantic` must be `var`, not `let`.** Transformations
  mutate it.
- **Top-level `MainActor.assumeIsolated { ... }`** in main.swift.
  `AppDelegate` is `@MainActor`; its `init()` is main-isolated; top-level
  code in Swift 6 is not main-isolated by default.
- **Carbon `kVK_*` constants are `Int`; `CGKeyCode` is `UInt16`.** Use
  `switch Int(kc) { case kVK_UpArrow: ... }`.
- **CGEventTap callbacks arrive on the main runloop** when the source is
  added via `CFRunLoopGetCurrent()` from the main thread.
- **Carbon `RegisterEventHotKey` does not require Accessibility** — the
  foundation of Limited Mode.
- **Limited Mode panel** must use a styleMask **without**
  `.nonactivatingPanel` and override `canBecomeKey: true`. An `NSPanel`
  with `.nonactivatingPanel` cannot become key window.
- **`BigHUDHostingView<Content: View>: NSHostingView`** overrides
  `acceptsFirstMouse(for:) -> true`. Without this, clicks in the
  non-activating panel are dropped.
- **`Bundle.module`** is generated only when
  `resources: [.process("Resources")]` is set in Package.swift.
- **`NSAttributedString` foreground colors** in RTF source are almost
  always literal black. Remap to `NSColor.labelColor` so Dark Mode
  renders correctly. Catalog colors (`linkColor`, `systemBlue`) adapt
  natively and must be left alone.
- **Pasteboard write order:** `clearContents` → `setString` / `setData` /
  `writeObjects` → set `watcher.ignoreNextChange = true`.
- **BigHUDState threading** — `@MainActor`. AppDelegate is also
  `@MainActor`. CGEventTap callbacks arrive on the main runloop already.
- **Preview computation token** (`previewToken`) guards against stale AI
  results during fast action switching.
- **Synthetic CGEvents** carry `eventSourceUserData = DrPasteSyntheticMarker`
  so the EventTap recognises and skips its own posted events.
- **⌥⌘⏎ paste-and-keep** (#222–#225): the synthetic ⌘V must use
  `CGEventSource(stateID: .privateState)` + `cgAnnotatedSessionEventTap`
  posting to escape the HID layer's modifier merging. Otherwise the
  held ⌥ leaks into the synthetic event and macOS triggers
  ⌥⌘V (DrPaste's own summon hotkey) recursively.
- **MiniHUD watchdog must be `Task.detached`** (#245): a regular
  `Task { @MainActor in }` watchdog sleep is starved when the main actor
  is busy streaming AI tokens. Detach to the global executor.
- **NSAttributedString.data(from:documentAttributes:)** is throwing;
  use `try?` not `error: nil`.
- **NSTextAttachment cell form is NOT preserved by RTFD encoder**
  (#236): use `NSTextAttachment(fileWrapper:)` with a PNG `FileWrapper`
  so the attachment survives the round-trip.
- **Unicode reverse-style lookup** (#A32, 0.42.0): the
  `customReverse` map must skip pairs whose "fancy" form is itself plain
  ASCII (e.g. upside-down `b → q` plus `q → b`). Otherwise NFKC of Math
  Bold input gets re-rewritten in the second pass and `the quick` turns
  into `the bnick`.
- **`Text(...).foregroundStyle(...)`** on a composed Text is macOS 14+
  only. For 13 deployment target use `.foregroundColor(_:)` (deprecated
  in general SwiftUI but still the back-deployable call on Text).

## Roadmap

The active backlog lives in `BACKLOG.md`. Highlights of **planned** work
(items already shipped have been moved to the Changelog section):

1. **#A1** — Ship as a signed `.app` bundle with `.icns` and notarization.
2. **#A2** — Real Launch on Login (`SMAppService.mainApp`). Depends on #A1.
3. **#A3** — iCloud Keychain sync for provider keys. Depends on #A1.
4. **#A5** — Per-app AI provider override.
5. **#A6** — Bidirectional drag-and-drop in HUD.
6. **#A7** — HUD search / filter (re-attempt with cleaner mode separation).
   See also **#A13**, the flight-test variant.
7. **#A8** — Skills / Marketplace registry for shareable action packs.
8. **#A12** — Unified hotkey contract: tap-vs-hold semantics for
   ⌥⌘C/S/X with content preview in MiniHUD.
9. **#A14–#A23** — flight-test backlog: Resize universal, CSV tables,
   Built-in editor redesign, Paste-as-is icons, Latin → Cyrillic,
   Pretty Code (local + AI), Unit conversion, File → Image, URL
   preview cards, macOS Services context menu.
10. **#A28–#A38** — engine consolidation, semantic kind expansion
    (Color / Email / PDF / Wiki / HTML), HUD Pin button, clickable
    legend, AX text-operations for full-document context, etc.
11. **#A39–#A45** — architectural maturity pass from the external
    code-review session: unified action pipeline + PasteCommitter
    (#A39), SelectionCaptureService (#A40), import/export merge
    audit + ImportReport (#A41), surface state machines (#A42),
    PreferencesKeys enum (#A43), ProviderResolver tighten-up (#A44),
    contract tests (#A45). #A39 is the prevention layer for the class
    of bug exemplified by the Type Slowly direct-trigger fix in 0.42.1.

**Recently shipped** (highlight set):
- **0.14.0** — AI streaming (#A9): token-by-token preview, SSE finishers.
- **0.18.0** — per-action hotkey hold-preview synergy (#A10 C1).
- **0.22.0** — Region capture via ⌥⌘ + drag (#A11): overlay, dim layer,
  crosshair cursor, source-app metadata.
- **0.34.x** — ⌥⌘⏎ paste-and-keep in HUD (multiple iterations).
- **0.35.x** — provider routing consistency: real executor surfaced
  everywhere, cost-aware fallback ordering, usage stats.
- **0.36.x–0.40.x** — ⌥⌘S accumulator rewrite (rich-text +
  files-strict + bridge), session indicator, RTFD round-trip fix.
- **0.41.0** — MiniHUD AI hang fixes (stream finishers + detached
  watchdog).
- **0.42.0** — small-bug sweep + medium UX polish (#A32 / #A34 / #A35 /
  #A36 / #A24 / #A25 / #A26 / #A27): Unicode reverse-table denormalize
  bug, Save button in New Built-in, Extract links/headings on rich text,
  Built-in handler picker visibility audit, Markdown → Rich Text action,
  Unicode Fancy on markdown markup, ASCII art rich text + 40-col default,
  Type Slowly 1.5× faster + animated playground preview.
- **0.42.1** — hot-patch: Type Slowly via per-action hotkey was being
  committed as plain ⌘V (wildcard pattern in `actionHotkeyDidFire`
  collapsed `.alternativeCommit(_, _)`). Bug surfaced by an external
  code-review pass; #A39–#A45 (unified pipeline / capture service /
  import audit / state machines / preferences enum / provider resolver
  formalisation / contract tests) added to backlog as the
  prevention layer.
- **0.42.2** — quick-wins from the second code-review pass: pasteboard
  polling timeout 0.25→0.40 + bundleID logging, shared CIContext,
  safer AX bridge cast (CFGetTypeID check), index.json + fallback-key
  doc fixes, UsageProbe local-day honest comment, MiniHUD completion
  pill for image-AI direct hotkeys, PasteboardWriter declares only
  readable types (skip missing-blob silent corruption). 13 deferred
  recommendations queued as #A46–#A58.
- **0.51.0** — batch: foundation (PreferenceKeys enum,
  `withWatchdog` helper, AIHTTP session with explicit timeouts,
  ToastController), user-visible UX (BigHUD Pin button, Append Copy
  toasts, Region Capture "Captured WxH" toast, cheat-sheet per-action
  "tap run, hold preview" suffix), correctness (ClipboardItem
  `contentHash` SHA-256 + hash-based sameContent dedup). Plus
  post-0.50 calibration items: comment fixes in `remapLegacyActionIDs`
  (version + honest conflict policy).
- **0.50.0** — adversarial review integration: `remapLegacyActionIDs`
  hot-patch (existing users with hotkeys / titles on
  `_extract_*` IDs would have seen orphaned state after the 0.42.4
  rename — fixed by walking enabledFlags / customTitles /
  actionHotkeys / actionOrder / actionTestSamples before the seed
  step). Eight backlog specs deepened with adversarial-pass
  refinements: #A64 (baseDefaultHash override, fallback chain,
  no-backfill i18n rule, explicit #A41 dependency), #A39
  (`.previewOnly` mode, mode × outcome policy table, typed
  terminal state with generation tokens, explicit #A40 dependency),
  #A59 (HintState schema with resetGeneration + 90-day staleness
  window), #A1 (boot-phase fatal UI as `try!` recovery path).
  SKILL.md trap-comments principle clarified: comments follow
  invariant owner, not call site — migrate during extraction.
  Process learning: adversarial prompt with required output shape
  produces 11/12 actionable findings vs prior consensus rounds.
- **0.42.4** — hot-patch: built-in action ID rename drift.
  `CuratedDefaults.enabledByDefault` referenced legacy
  `_extract_` IDs that no longer exist as seeds (the seed had moved
  to `json_keys` / `md_headings` / `md_links`). Fresh installs
  missed Extract Keys / Extract Headings in the default-enabled
  set; Settings rows lost descriptions and got `gearshape` icon
  fallback. Surfaced by a second-machine test run. Curated set
  switched to current IDs; metadata/icons gained entries for
  current IDs while keeping legacy `_extract_` aliases (existing
  user configs may still carry the old IDs). Dedicated migration
  task #299 queued to walk user configs and finally retire the
  aliases.
- **0.42.3** — UX micro-fixes from the final UX/UI review:
  HUD footer `C save` / `esc cancel` (was `copy` / `close`),
  Settings action row shows the original title inline in grey
  next to the user's renamed title (one row, not two),
  HotkeyRecorder gains "Tap to run · hold ⌥⌘ to preview"
  footer hint, menu-bar tooltip now describes the active append
  session (rich / files / idle). Bigger UX recommendations
  (#A63 visual selection clarity, #A64 title/description split,
  #A65 toasts, #A66 region toast, #A68 theme mini-HUD, #A69
  MiniHUD failure state, plus the Welcome refocus in #241)
  queued in backlog. Adopted explicit decision: Welcome
  Window stays focused on 4 basics + Accessibility CTA — does
  NOT get the "What DrPaste can do" feature dump that #241
  originally proposed (per UX review's anti-onboarding
  principle).

## Related notes in personal profile

iLya Os — engineer / inventor, 30+ patents, prefers embedded / edge AI,
dislikes unnecessary wrappers. Comfortable working directly against
low-level APIs (Carbon, CGEventTap, NSPanel) without third-party
libraries. Open-source orientation. Copyright headers use the handle
**iLya Os** (lowercase i, uppercase L, no period).

---

## APPENDIX A — Complete keybinding reference

All global hotkeys are fixed except per-action `⌥⌘<letter>` chords.

### Global (any app, when DrPaste is running)

| Chord | Action | Behaviour |
|---|---|---|
| `⌥⌘V` | Open BigHUD | Press-and-hold in Gesture Mode, summon in Limited |
| `⌥⌘C` | Quick Copy | Synthesize `⌘C` + success sound |
| `⌥⌘X` | Cut & Replace | Cut current selection, open HUD, swap on commit |
| `⌥⌘S` | Append Copy | Add to accumulator (rich or files-strict track) |
| `⌥⌘ + drag` | Region capture | Drag rectangle → PNG → BigHUD focused on capture |
| `⌥⌘<letter>` | User-assigned action | Tap = direct paste (MiniHUD for slow AI). Hold ⌥⌘ after letter ≥250 ms → BigHUD opens focused on that action via `openBigHUDFocusedOnAction(_:)` |

### Reserved chords (HotkeyRecorder blocks assignment with `drPasteReservedName`)

- `⌥⌘V` → "Open BigHUD"
- `⌥⌘C` → "Quick Copy"
- `⌥⌘X` → "Cut & Replace"
- `⌥⌘S` → "Append Copy"
- `⌥⌘⏎` → "Paste & Keep" (inside HUD)

### System chords blocked with `systemHotkeyName`

- `⌥⌘Q` — Force Quit (NOT "Log Out User" — user corrected this in 0.35.x)
- `⌥⌘D` — Show or Hide the Dock
- `⌥⌘M` — Minimize All
- `⌥⌘H` — Hide Others
- `⌥⌘L` — Downloads / Other (varies)
- `⌥⌘N` — New
- `⌥⌘O` — Open & Close Finder Window
- `⌥⌘P` — Print
- `⌥⌘T` — Show / Hide Toolbar
- `⌥⌘Space` — Show Finder Search Window

### Inside BigHUD

| Key | Action |
|---|---|
| `↑↓` | Browse history |
| `←→` | Switch action |
| `⏎` | Commit (paste + close) |
| `⌥⌘⏎` | Paste & Keep — paste focused item, leave HUD open |
| `C` (Gesture) / `⌥⌘C` (Limited) | Copy preview to top of history |
| `S` (Gesture) / `⌥⌘S` (Limited) | Merge focused clip into in-HUD accumulator |
| `⌫` | Delete focused item from history |
| `⌘+` / `⌘−` / `⌘0` | Font scale up / down / reset |
| `Esc` | Cancel without paste |

### Inside MiniHUD

| Element | Action |
|---|---|
| ✕ | Cancel in-flight task |
| Background drag | Reposition window |

## APPENDIX B — File system layout

### User data (persists across launches)

`~/Library/Application Support/DrPaste/`
- `actions.json` — full `ActionConfig`: customAI, customTransformations,
  enabledFlags, customTitles, actionHotkeys, actionOrder per kind,
  testSamples, preferences, seedAIVersion, seedTransformationVersion.
- `index.json` — clipboard history index (up to 500 items, JSON
  Codable form of `ClipboardItem`). Path constructed by
  `ClipboardStore.indexURL` at line 188 of ClipboardModel.swift.
- `blobs/` — PNG / RTFD / RTF blob storage referenced by
  `ClipboardItem.representations[type] = relPath`.
- `provider-keys-fallback.json` — plain-JSON key store, used while
  Keychain is disabled (since 0.14.0). Will migrate into Keychain in
  #A1 (signed-release day).
- `providers.json` — `ProvidersConfig` (the multi-provider list with
  endpoint URLs, model names, capability hints; keys live separately).

### Persistent preferences (UserDefaults)

- `drpaste.hud.fontScale` — Double, 0.7–1.6.
- `drpaste.theme` — String, one of "default" / "vivid" / "soft" / "ocean".
- `drpaste.cutReplace.cursorOnSecond` — Bool, the start-cursor-on-second
  toggle.
- `drpaste.cheatSheet.enabled` — Bool, region-capture cheat sheet.
- `drpaste.sound.<cue>` — Bool per cue toggle.
- `drpaste.sound.volume` — Double 0.0–1.0.
- `drpaste.openrouter.anchor` — JSON `{ date, credits, machineUUID }`
  for daily-delta credit display.
- `drpaste.api_keys.use_fallback_only` — Bool, whether to bypass
  Keychain entirely (always true in 0.14.0+ until #A1). Live constant:
  `APIKeyStorage.fallbackOnlyDefaultsKey`.

### Workspace files

```
~/Dropbox/Claude My/DrPaste/
  Package.swift                   SwiftPM manifest, Swift 5.9, macOS 13+
  Sources/DrPaste/*.swift         all source files (see file tree above)
  Sources/DrPaste/Resources/      bundled resources
  Tests/DrPasteTests/*.swift      XCTest target — pure-module tests
  README.md                       English marketing description
  SKILL.md                        this file — project memory
  HELP.md                         Russian end-user guide
  BACKLOG.md                      active items + condensed changelog
  LICENSE                         GPL-3.0-or-later + §7(d) attribution
  .gitattributes                  enforces LF line endings
  .build/                         SwiftPM artefacts (exclude from sync)
```

## APPENDIX C — Action catalogue (current snapshot)

### Hardcoded ClipboardAction subclasses (not descriptor-backed)

These live as Swift classes that implement `protocol ClipboardAction`:

- **Identity** (`builtin.identity`) — pinned anchor, restores clip as-is.
- **LayoutRepair** (`builtin.layout_repair`) — fix wrong-keyboard text.
- **CleanFormatting** (`builtin.clean_formatting`) — strip rich text.
- **Generate QR** (`builtin.generate_qr`) — text → QR image.
- **Image actions**: OCR, decode QR, strip metadata, resize-1920,
  compress JPEG, grayscale, invert, rotate right / left, ASCII art.
- **AI image styles**: pencil sketch, watercolor, cartoon (as
  CustomAIDescriptor seeds, not hardcoded).
- **Whiteboard sketch** (text-to-image AI seed).
- **Type Slowly** (`builtin.type_slowly`) — keystroke simulator.
- **Markdown → Rich Text** (`builtin.md_to_rich`, added 0.42.0) —
  uses RichTextHelpers.markdownToAttributedString.
- **File actions**: paths, names, MD links, reveal in Finder.
- **URL actions**: just domain, MD link, HTML link, query-params table.
- **Table converters**: table → JSON, table → Markdown.
- **Paste as text**, **Rich → Wiki/MD/HTML** (in MoreActions.swift).

### Descriptor-backed (seeded into customTransformations)

`DefaultTransformationSeed.defaults()` produces these on first launch
(currentSeedVersion = 6, ~28 entries):

**Text utility:** UPPERCASE, lowercase, Title Case, Sentence case,
camelCase, snake_case, kebab-case, Trim whitespace, Sort lines (asc/desc),
Unique lines, Word count, Slugify, Base64 encode/decode, URL %-encode/decode,
Tabs → spaces, Spaces → tabs.

**Markdown:** Markdown → plain, Extract headings, Extract links.
(All three migrated to applicableTypes `[markdown, text, richText]` in
seed v5 — engines use `RichTextHelpers.attributedStringToMarkdown` to
recover MD source from rich-text clips.)

**URL:** Clean URL (strip tracking params).

**JSON:** Pretty, Minify, Extract keys, Extract keys recursive.

**Unicode pseudo-fonts** (~20 styles, seeded as
`builtin.font_<style>` with `unicodeStyle` engine + style param):
Bold, Italic, Bold Italic, Script, Bold Script, Fraktur, Bold Fraktur,
Double-struck, Sans-serif (+ Bold / Italic / Bold Italic), Monospace,
Fullwidth, Small Caps, Circled, Filled Circled, Squared, Filled Squared,
Upside Down, **Markdown styles → Unicode** (added 0.42.0, parses
`**bold**` / `*italic*` / `` `code` `` / `~~strike~~`), Plain (reverse).

**Cyrillic transliteration:** К → K (Russian / Ukrainian / Belarusian /
Bulgarian / Serbian / Macedonian — auto-detect).

### CuratedDefaults — enabled-on-first-launch subset

Lives in `CuratedDefaults.enabledByDefault`. Currently:

- Text: paste_as_text, layout_repair, uppercase, lowercase, trim,
  word_count, sort_lines.
- Markdown: md_to_plain, md_to_rich (added 0.42.0), md_headings
  (renamed from md_extract_headings in 0.50.0 — legacy alias kept
  in metadata/icons until #299 retires them).
- Code: code_wrap, tabs_to_spaces.
- URL: url_strip_tracking, url_just_domain, url_md_link.
- JSON: json_pretty, json_minify, json_keys (renamed from
  json_extract_keys in 0.50.0; legacy alias kept).
- Image: ocr, decode_qr, strip_metadata, resize_1920, grayscale, rotate,
  rotate_left, ascii_art.
- Files: paths, names, md_links, reveal.
- Tables: to_json, to_md.
- Unicode fancy: the **full curated set** is bold, italic,
  bold_italic, script, bold_script, fraktur, bold_fraktur,
  double_struck, sans, sans_bold, sans_italic, sans_bold_italic,
  monospace, fullwidth, small_caps, circled, filled_circled,
  squared, filled_squared, upside_down, plain, and font_markdown
  (added 0.42.0). All seeded by default — the user can disable
  individual styles via Settings, the curated philosophy is
  "every Unicode pseudo-font is one toggle away".
- Cyrillic transliteration.
- AI text (via CustomAIDescriptor.enabled = true): Translate, Fix
  grammar, Polish, Summarize, Explain.
- AI image (via CustomAIDescriptor.enabled = true): Pencil sketch,
  Watercolor, Cartoon.

## APPENDIX D — AI provider catalogue

| Kind | Endpoint kind | Streams | Image generate | Image edit | Where to get key |
|---|---|---|---|---|---|
| Anthropic | `/v1/messages` SSE | yes | no | no | console.anthropic.com |
| OpenAI | `/v1/chat/completions` SSE + `/v1/images/generations` | yes | yes (gpt-image-1) | yes | platform.openai.com |
| Gemini | `streamGenerateContent` | yes | yes (imagen) | yes | aistudio.google.com |
| Grok (xAI) | OpenAI-compat | yes | no | no | x.ai |
| Mistral | OpenAI-compat | yes | no | no | mistral.ai |
| DeepSeek | OpenAI-compat | yes | no | no | platform.deepseek.com |
| OpenRouter | OpenAI-compat proxy | yes | yes (flux / imagen routes) | yes | openrouter.ai |
| Together AI | OpenAI-compat | yes | varies | varies | together.ai |
| Groq | OpenAI-compat | yes | no | no | groq.com |
| Cerebras | OpenAI-compat | yes | no | no | cerebras.ai |
| Cloudflare Workers AI | custom | varies | OSS only | OSS only | dash.cloudflare.com |
| Ollama | OpenAI-compat local | yes | no | no | localhost:11434 |
| LM Studio | OpenAI-compat local | yes | no | no | localhost:1234 |
| llama.cpp | OpenAI-compat local | yes | no | no | localhost:8080 |
| Custom | user-defined | yes (assumed) | OpenAI wire format | OpenAI wire format | n/a |

### Cost-aware image fallback priority

`cheapestEnabledImageProvider()` in AIProvider.swift returns the first
enabled provider in this order:

1. **Gemini** — ~$0.039 / image (cheapest).
2. **OpenRouter** — typically cheaper than direct OpenAI via flux/imagen.
3. **OpenAI** — $0.011 (low) to $0.167 (high) per gpt-image-1 1024×1024.
4. **Custom** — unknown cost, last resort.

`imageEditCostRank` field on each provider drives the ordering.

### Quality directive parsing

`extractQualityDirective(from:)` regex parser scans a prompt for
`Quality: low|medium|high|auto` and lifts it into the API call. Used
only for OpenAI gpt-image-1; ignored for Gemini / OpenRouter (different
APIs). Default seed prompts include `Quality: low` at the end so the
default is cheap; users can edit it out for higher quality.

### Usage probes (UsageProbe.swift)

- **OpenAIUsageProbe** — calls `/v1/organization/costs` with the regular
  API key. Returns `notSupportedForKey` on 401/403 (key without billing
  scope) → row is silently hidden. No admin key required since 0.35.1.
- **OpenRouterUsageProbe** — calls `/api/v1/credits`. Stores
  daily-anchor in UserDefaults. Resets anchor on:
  - machine UUID change (machine switch),
  - lifetime credit regression (account re-key),
  - date change at local midnight.
- Anthropic, Gemini, etc. have no public usage API → no row shown.

## APPENDIX E — Migrations and seed-version chain

`ActionRegistry.runFirstLaunchSeeds()` runs four migration passes on
each launch (idempotent — guarded by version comparisons):

1. **seedAI** — if `seedAIVersion < DefaultAISeed.currentSeedVersion (=6)`,
   add missing AI descriptors. Migrations:
   - v2 — added image styles family.
   - v3 — moved factory AI from hardcoded to customAI.
   - v6 — appended `Quality: low` directive to existing image-style
     prompts that didn't have it (idempotent on user-edited prompts).
2. **seedTransformations** — if `seedTransformationVersion < 6`, add
   missing transformation descriptors. Per-entry: skip if already present
   (preserves user edits). Inherits user's prior enabled flag from
   `enabledFlags`, prior custom title from `customTitles`.
3. **rebrandFancyTextIfNeeded** — one-shot v3 migration renamed font
   actions from "Font: Bold" to "𝐀  Bold", restricted `applicableTypes`
   from `[text, markdown, code]` to `[text]`, removed Regional
   Indicator. Idempotent.
4. **expandMarkdownExtractTypesIfNeeded** — v5 migration (added 0.42.0):
   patches existing `builtin.md_headings` and `builtin.md_links`
   `applicableTypes` from `[markdown]` to `[markdown, text, richText]`.
   Idempotent — only runs if the descriptor still has the exact legacy
   `[markdown]` set.

## APPENDIX F — Critical implementation details that are easy to miss

### Trap comments must follow the invariant, not the call site

A standing project principle: comments that document **non-obvious
platform traps** (HID modifier leak, RTFD attachment cell-form,
detached-watchdog necessity, etc.) stay in the source, not in
external docs. They are institutional memory rendered next to the
code that depends on them.

The adversarial review pass clarified a refinement: **a trap comment
belongs at the invariant owner, not at every historical call site.**
When refactoring code that is currently guarded by such a comment,
move the comment to the new owner (the extracted helper's API doc,
or a test name that asserts the invariant). Do NOT leave the comment
behind at the now-stale call site that no longer expresses the
invariant directly. Stale local comments referring to
`pendingDeferredPasteApp` or "the second-to-last change to
`actionHotkeyDidFire`" after that path is unified through #A39
become misleading; a future developer trusts the local comment and
preserves the wrong ordering in the new abstraction.

Practical recipe during extraction:

1. Identify which comments document an *invariant* the extracted
   code preserves (HID modifier isolation, generation-token
   cancellation, detached watchdog).
2. Move those into the extracted owner's documentation comment or
   into the name + body of a regression test.
3. Leave a comment at the old call site ONLY if it describes
   call-site-specific state (a particular flag's lifecycle, a
   timing race local to that scope).

The point of the principle remains: institutional memory near
production code. The refinement is just that **"near"** is defined
by *who currently enforces the invariant*, not *where the bug
historically appeared*.

### ⌥⌘⏎ paste-and-keep (#222–#225, 0.34.x)

`PasteSimulator.simulatePasteKeepingHeldModifiers()`:
1. Use `CGEventSource(stateID: .privateState)` (NOT `.combinedSessionState`)
   so the synthetic event doesn't inherit the user's held `⌥`.
2. Post via `tap: .cgAnnotatedSessionEventTap` (NOT `.cghidEventTap`)
   so HID layer doesn't OR the held modifier into the synthetic event.
3. Skip `NSApp.activate(ignoringOtherApps: true)` — focus steal triggers
   the target app to re-evaluate its modifier state and the held ⌥
   leaks back in.
4. Synthetic event carries `eventSourceUserData = DrPasteSyntheticMarker`
   so EventTap recognises it as ours and skips swallow logic.

Without all four: held `⌥` ORs with synthetic `⌘V` → target sees
`⌥⌘V`, which is DrPaste's own summon hotkey → infinite loop.

### MiniHUD watchdog must be Task.detached (#245, 0.41.0)

The 90-second watchdog that cancels a runaway AI task must run via
`Task.detached(priority: .background)` — NOT `Task { @MainActor in }`.
When AIProvider.stream is yielding many small chunks to MainActor, the
main-actor queue is saturated; a MainActor-bound Task.sleep gets
starved and never fires. Detached runs on the global executor and is
not affected.

Pattern:
```swift
let watchdog = Task.detached(priority: .background) { [weak self] in
    try? await Task.sleep(nanoseconds: 90_000_000_000)
    guard !Task.isCancelled else { return }
    await MainActor.run { [weak self] in
        self?.actionHotkeyTask?.cancel()
    }
}
defer { watchdog.cancel() }
```

### Stream finishers per provider (#244, 0.41.0)

URLSession byte streams don't always end with EOF when the provider
emits keep-alive pings. Each provider needs an explicit finisher
sentinel to break the read loop:

- **Anthropic** — listen for `event: message_stop` SSE event.
- **OpenAI-compatible** — listen for `data: [DONE]` SSE line.
- **Gemini** — parse JSON chunks for `finishReason` field; any
  non-null value (`STOP`, `MAX_TOKENS`, etc.) terminates.

### NSTextAttachment must be FileWrapper-based for RTFD (#236, 0.36.x)

`NSTextAttachment` has two construction forms:
- `attachment.attachmentCell = NSTextAttachmentCell(imageCell: ...)` —
  works in-memory, but the RTFD encoder DROPS the cell on serialization.
- `NSTextAttachment(fileWrapper: FileWrapper(regularFileWithContents: pngData))`
  — survives RTFD round-trip, the image reappears on the other end.

Always use the FileWrapper form for accumulator and AppendAccumulator
attachments.

### RichTextLoader RTFD priority (#237, 0.36.x)

When loading rich-text content from a ClipboardItem, check
`com.apple.flat-rtfd` representation FIRST (before `public.rtf`).
RTFD carries embedded images; RTF strips them silently. Skipping
RTFD means the accumulator preview shows text but no inline images
even though they're in the pasteboard.

### Unicode reverse-style map filter (#A32, 0.42.0)

`customReverse` in UnicodeStyles.swift must FILTER OUT entries whose
"fancy" form is itself a plain ASCII letter / digit. The upside-down
table contains self-swapping pairs (`b: q` + `q: b`, `d: p` + `p: d`,
`n: u` + `u: n`). Without the filter, NFKC output of Math Bold input
(`𝐭𝐡𝐞 𝐪𝐮𝐢𝐜𝐤` → `the quick`) gets re-rewritten in the second pass
(`the bnick`). Always check `if fancy.isASCII { continue }`.

### Save in `+ New Built-in` needs explicit setEnabled (#A34, 0.42.0)

When the user creates a new Built-in action from "+ New" and picks a
handler that's disabled by curated defaults, just calling
`setCustomTitle` + `setHotkey` produces a no-op-looking Save — the
descriptor exists but it's hidden. Save must also call
`registry.setEnabled(true, for: targetID)` in the `.createNew + .builtin`
path. Edit-mode saves leave the enabled flag alone.

### macOS 13 deployment vs macOS 14 SwiftUI APIs

- `Text(...).foregroundStyle(...)` is macOS 14+. For Text use
  `.foregroundColor(_:)` instead — deprecated for general SwiftUI but
  still back-deployable on Text. Compile error otherwise.
- `Color.secondary.opacity(0.35)` wraps to `Color` explicitly — pure
  `.secondary.opacity(...)` ambiguates on older SDKs.

### NSAttributedString.data(...) throwing API

```swift
// WRONG (Swift compile error):
let data = attr.data(from: range, documentAttributes: opts, error: nil)
// RIGHT:
let data = try? attr.data(from: range, documentAttributes: opts)
```

### Direct-trigger commit must respect commit style (0.42.1)

`actionHotkeyDidFire(actionID:)` previously carried a wildcard pattern
`case .preview(let result), .alternativeCommit(let result, _):` that
collapsed every commit style into `performStandardPaste`. Result: a
per-action hotkey bound to Type Slowly would paste the whole text via
⌘V instead of typing character-by-character. BigHUD's `commitOutcome`
already handled the three commit styles correctly; the direct-trigger
path didn't. The contract: **whenever an ApplyOutcome is committed,
the commit style (`standardPaste` / `typeSlowly(delay, jitter)` /
`typeFast`) MUST drive a different sink** — never collapse them. #A39
will eliminate the class of bug by routing both paths through a single
`PasteCommitter`.

### Three-tier action visibility audit (#A36, 0.42.0)

`ActionEditor.availableBuiltins` previously filtered out
descriptor-backed handlers (md_to_plain, md_headings, md_links,
cyrillic_translit, the Unicode font family) from the "+ New Built-in"
picker, because they already have a Settings list row. That created
inconsistency. Filter removed — every `builtin.*` action is pickable
EXCEPT the identity anchor.

## APPENDIX G — Where each major capability lives

- **Streaming AI** → AIProvider.swift `stream(prompt:input:)` +
  BigHUD.swift `consumeStream` + MiniHUD.swift `consumeStream`.
- **Provider routing honesty** → `resolveExecutorProvider` helper
  used by Action editor, HUD chip, Settings list. Cost-aware fallback:
  `cheapestEnabledImageProvider()` cache.
- **Append accumulator** → AppendAccumulator.swift +
  `hotkeyEngineDidAppendCopy()` in main.swift.
- **Region capture** → ScreenRegionCapture.swift +
  `RegionCaptureCheatSheet.swift` for corner overlay.
- **Per-action hotkey direct+hold** → ActionHotkey.swift +
  HotkeyEngine.swift flagsChanged + main.swift
  `actionHotkeyDidFire(actionID:)`.
- **Themes** → AppTheme.swift; consumed by BigHUD / MiniHUD /
  RegionCaptureCheatSheet.
- **Test samples persistence** → ActionConfig.testSamples +
  ActionTestSamples.swift defaults.
- **Custom transformation runtime** → CustomTransformation.swift —
  `TransformationRuntime.apply(...)` for plain text;
  `applyToAttributed(...)` for rich text where engine flag
  `preservesRichTextFormatting` is true.

## APPENDIX H — Resuming work after a fresh start

If this context is lost and you need to resume:

1. Read this SKILL.md top to bottom — full project memory.
2. Read BACKLOG.md `Active backlog` section for #A1–#A38 — every
   planned feature has Status / Touches / Context / Requirements /
   Implementation notes. The user's design choices for each are baked
   into the Requirements bullets.
3. Read BACKLOG.md `Changelog` section for shipped milestones and the
   reasoning behind each release.
4. `git log --oneline --follow BACKLOG.md` shows the historical
   evolution of the backlog — pre-curated revisions were bilingual
   Russian / English.
5. Build with `swift build` from the repo root. No external deps.
6. Current version printed by `AppBrand.version` — bump in that
   single file when releasing.
7. End-user documentation in HELP.md (Russian, 16 sections, mirrors
   feature surface 1:1).
8. Marketing-facing description in README.md.

The user's working style: Russian first-language but tolerates English
in technical documentation; prefers descriptive multi-paragraph backlog
entries over terse checklists; values "honest" UI (no lying about
provider, version, status); strict about copy/paste latency (every
synthetic event must be tight, watchdogs must escape main-actor
congestion); does NOT want a SaaS lock-in (BYO AI is free forever).
