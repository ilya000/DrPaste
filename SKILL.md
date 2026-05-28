---
name: drpaste
description: Project memory and working context for DrPaste — a native macOS clipboard extension built around a press-and-hold philosophy ("an extension of the Paste gesture itself"). The "Dr" in DrPaste reads as "scholarly / educated" (PhD), not "doctor / medical". Load this skill whenever the conversation mentions DrPaste, Dr Paste, paste manager, paste extension, macOS clipboard manager, clipboard HUD, press-and-hold paste, ⌥⌘V HUD, intelligent paste, Flycut / Jumpcut / Maccy / Paste alternatives, or BYO-AI paste tools. The earlier working name was ClipMacPoC (also a trigger). Covers the full design brief, architectural decisions, file-by-file responsibilities, implementation subtleties (CGEventTap vs Carbon vs NSEvent.addGlobalMonitor, NSPanel non-activating vs key-window, simulated paste, keyboard layout repair, Full Gesture vs Limited Mode auto-detect), current status, and roadmap.
---

# DrPaste

Native macOS clipboard utility built around press-and-hold UX. Goal is not "yet another clipboard manager" but **an extension of the system Paste gesture itself**.

Original working name: **ClipMacPoC**. Final product name: **DrPaste** (chosen 25 May 2026). The "Dr" semantic is **PhD / scholar / educated**, not medical. The icon reflects this: clipboard + mortarboard cap, not a medical cross.

## Project location

```
~/Dropbox/Claude My/DrPaste/
  Package.swift
  README.md                         English, publishable
  LICENSE                           GPL-3.0-or-later + attribution §7(d)
  SKILL.md                          this file
  BACKLOG.md                        active items + condensed changelog
  .gitattributes                    LF for all text files
  Sources/DrPaste/
    main.swift                      AppDelegate, bootstrap, AX monitor
    AppBrand.swift                  AppBrand.name = "DrPaste", icons, About credits
    ClipboardModel.swift            ClipboardItem, Store, Watcher, AppStorage paths
    ContextDetector.swift           local content classifier
    Actions.swift                   protocol ClipboardAction + registry + Identity / LayoutRepair / CleanFormatting
    DefaultTransformationSeed.swift bundled builtin.* transformation descriptors (26 items, 24 engines)
    CustomTransformation.swift      TransformationEngine enum + runtime + descriptor model
    AIProvider.swift                multi-provider AI registry + AIAction + factory seed
    KeyboardLayoutRepair.swift      QWERTY ↔ ЙЦУКЕН swap + NSSpellChecker scoring
    HotkeyEngine.swift              EventTapEngine + CarbonHotKeyEngine + GlobalMonitorEngine + factory
    HotkeyRecorder.swift            assign-a-hotkey-to-an-action UI
    ActionHotkey.swift              per-action hotkey descriptor + Carbon manager
    HUD.swift                       HudState + HudPanel + HudView, single SwiftUI surface
    ProgressHUD.swift               transient mini-window shown during direct-trigger actions
    PasteSimulator.swift            ⌘V/⌘C/⌘X via CGEvent + PasteboardWriter
    SettingsWindow.swift            TabView Settings: General, AI, per-content tabs
    ActionEditor.swift              unified editor for builtin / AI / transformation actions
    ActionPaletteSheet.swift        "Browse" palette for re-enabling disabled actions
    BuiltinActionEditor.swift       descriptions metadata for built-ins
    BuiltinActionIcons.swift        SF Symbol mapping for built-in action ids
    CuratedDefaults.swift           default-enabled subset for first launch
    APIKeyStorage.swift             Keychain wrapper with plain-JSON fallback
    RichTextHelpers.swift           NSAttributedString ↔ Markdown / HTML / Wiki
    RichTextPreviewView.swift       NSTextView wrapper used by HUD and Settings
    AboutWindow.swift               custom 560×500 About panel
    WelcomeWindow.swift             first-launch panel with AX guidance
    SoundFeedback.swift             cue throttling and preview playback
    ContentMeta.swift               on-demand "N words, N chars" metadata cache
    TypeSimulator.swift             Type Slowly engine with auto-cancel
    TextActions.swift               Generate QR (image-producing action)
    JSONActions.swift               Flatten, Remove nulls (structure-rewriting actions)
    URLActions.swift                Just domain, Markdown / HTML link, query params
    MoreActions.swift               Table converters, Rich → MD / HTML / Wiki, Paste as text
    FileActions.swift               File-reference actions (paths, names, SHA, reveal)
    ImageActions.swift              OCR, decode QR, strip metadata, resize, grayscale, …
    MarkdownActions.swift           (empty placeholder; everything migrated to engines)
    ActionConfig.swift              ActionConfig Codable root + preferences + seed versions
    Resources/
      AppIcon.svg                   placeholder vector
      MenuBarIcon.svg               monochrome template (clipboard + ⌘V)
      RichTextSamples/              fixed RTF sample for the Rich Text playground
      Sounds/                       bundled aiff cues
```

The `.build/` directory contains many small build artefacts — exclude it from Dropbox Selective Sync.

## Concept (one-liner)

User holds `⌥⌘V` → HUD overlay appears → `↑↓` browses clipboard history, `←→` switches between actions, live preview updates → user releases the modifiers → the current preview is pasted at the cursor of the frontmost app. Escape aborts.

**Dr = "educated paste".** The product diagnoses content context (URL / JSON / wrong layout / Markdown / code) and surfaces only the relevant transformations.

## Design principles

- **Press-and-Hold** — "press, choose, release, paste".
- **Preview-First** — every transformation is shown before commit.
- **Context-Aware Actions** — determined locally; only the relevant ones are shown.
- **Local-first** — useful without AI and without an internet connection.
- **Bring Your Own AI** — no bundled backend.
- **Keyboard-first, mouse-available** — same posture as Spotlight or Cmd-Tab.
- **System HUD aesthetic** — translucent, light/dark, system accent.
- **Graceful degradation** — works without Accessibility permission (Limited Mode).
- **Open source** — GPL-3.0 with attribution, community-extensible.
- **Two-surface model — HUD runs, Settings manages.** The HUD is the runtime
  surface: it shows only what is `enabled && applicable && context-matching`,
  because the user is mid-paste and any extra row costs speed. The Settings
  window is the management surface: it shows **everything**, including
  disabled actions (rendered dimmed). Disabled rows in Settings are not noise
  — they are how users find and re-enable, rename, edit `Applies to`, or
  reassign hotkeys for actions they previously turned off. Never collapse
  the two surfaces into one; never hide disabled actions from Settings; never
  push runtime filtering into the management view.
- **Action hierarchy — three tiers of depth.** DrPaste curates the action
  surface so that each user goes only as deep as their actual need.
  - **Tier 1 — Out of the box (90% of users).** Each content type ships
    with a hand-picked default-enabled subset of about half a dozen actions
    chosen for "obviously useful, immediately." This is what the user sees
    in the HUD on day one without ever opening Settings. The
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
  Design implication: every new action ships **disabled by default**
  outside the curated set. The Tier 2 surface (Settings palette + per-tab
  list) must stay legible — that's why we filter the engine picker and the
  built-in handler picker by useful categories instead of dumping every
  internal capability on the user. The Tier 3 surface (ActionEditor) is
  expected to look denser — power users earn that density.

## Architectural decisions

**Stack.** Swift 5.9 + SwiftUI + AppKit + Carbon.HIToolbox, macOS 13+. SwiftPM executable, no Xcode project, no external dependencies.

**Hotkey: ⌥⌘V in both modes.** The conflict with Microsoft Word "Paste Special" is accepted deliberately.

**Three hotkey engines with auto-detect:**

| Engine | Use | Permission | Can swallow events |
|---|---|---|---|
| `EventTapEngine` | Full Gesture Mode (production) | requires AX | yes |
| `CarbonHotKeyEngine` | Limited Mode (fallback) | none | no |
| `GlobalMonitorEngine` | debug only | requires AX | no |

Selection rule: `AXIsProcessTrusted()` true → EventTap, false → Carbon. Environment override: `CLIPMAC_ENGINE=tap|carbon|monitor`.

**Single HUD for both modes.** This is a core architectural principle:

- **One** `HudView` (SwiftUI). Same body in both modes.
- **One** `HudState` (model).
- **One** `HudPanel` class (parameterised via `init(contentRect:allowsKey:)`).
- The only differences between Full Gesture and Limited Mode are: panel `styleMask` / `canBecomeKey`; one condition in HudView (`if state.mode == .summon { limitedModeBanner }`); one footer string (release vs Enter); and a local key event monitor installed only in summon mode (in gesture mode keys are caught by the engine).

So: no duplicate views, no duplicate logic. One surface, one state, one panel class. Differences are minimal and isolated in a single `state.mode == .gesture vs .summon` condition.

**Two panel variants (single class, parameterised):**

- **`.gesture`** (Full): `NSPanel` with `styleMask: [.borderless, .nonactivatingPanel]`, `canBecomeKey: false`, `level: .statusBar`. EventTap swallows all key presses while the HUD is active. Commit on release of modifiers.
- **`.summon`** (Limited): same `NSPanel` with `styleMask: [.borderless, .titled, .fullSizeContentView]`, `canBecomeKey: true`, brought up via `makeKeyAndOrderFront`. `NSEvent.addLocalMonitor` in the AppDelegate catches Enter / Esc / arrows / `⌘±`. Commit on Enter or double-click. A "Limited Mode — press Enter to paste. Enable Accessibility for release-to-paste" banner appears with an inline "Open Settings…" button.

**AX trust monitor.** A background `Timer` polls `AXIsProcessTrusted()` every 3 s. On `false → true` transition it shows an `NSAlert` offering to restart; on the reverse transition the next launch silently downgrades.

**HUD design highlights:**

1. **Actions bar:** horizontal `ScrollView` + `ScrollViewReader.scrollTo(actionIndex, anchor: .center)` with a 0.18 s animation. Edge `mask(LinearGradient)` for fade-out.
2. **Mouse support:** `HudHostingView<Content: View>: NSHostingView` overrides `acceptsFirstMouse(for:) -> true`. Single-click selects (updates preview, HUD stays open), double-click commits. `onHover` for highlight.
3. **Rich text preview:** `NSTextView` wrapped in `NSViewRepresentable` (RichTextPreviewView). Foreground colors are remapped to `NSColor.labelColor` so Dark Mode is legible.
4. **AppBrand** — single source of truth for name, icons, version, About credits. `Bundle.module.url(forResource:withExtension:)` via `.process("Resources")` in Package.swift.
5. **System accent + light/dark.** `Color(nsColor: .controlAccentColor)` throughout. `NSVisualEffectView.isEmphasized = false` for a lighter blur.
6. **Font scale:** `HudState.fontScale: CGFloat` persisted in `UserDefaults` (`drpaste.hud.fontScale`). Helper `sz(_ base: CGFloat) -> CGFloat { base * fontScale }`. Bounds 0.7..1.6 in 0.1 steps.
7. **Dynamic visibleRowCount + chevrons:** `Int(round(11.0 / fontScale))` clamped to `5...items.count`. Window centers on the active item and clamps to edges. `chevron.compact.up/down` above and below the column.

**Context detection.** `ContextDetector.detect(item) -> ContentContext` (bitmask). Local heuristics only, no AI / network call.

**Action registry.** `protocol ClipboardAction { id, title, isLocal, isApplicable, apply async }`. Local actions run synchronously. AI calls run async with a loading state and a `previewToken` so stale results from previous focus do not overwrite the current preview.

**Transformation engines.** Every bundled built-in transformation (UPPERCASE, sort lines, JSON pretty / minify / extract, slug, base64, URL percent-encode, word count, Markdown extraction, URL strip tracking, code wrap, tabs↔spaces, title / sentence / camel / snake / kebab case, trim, unique lines) is a `CustomTransformationDescriptor` seeded into `config.customTransformations` on first launch via `DefaultTransformationSeed`. Users rename, retitle, reorder, change parameters, or fully delete them through the same editor that handles user-created transformations.

**AI provider abstraction.** `protocol AIProvider`. Concrete implementations: Anthropic, OpenAI-compatible (covers OpenAI / Grok / Mistral / DeepSeek), Gemini, Ollama, LM Studio, llama.cpp, custom. Registry: `AIProviderRegistry.shared`. Keys live in Keychain via `APIKeyStorage`. Default provider chosen via radio button in Settings and auto-promoted after the first successful connection test.

**Persistence.** JSON + PNG blobs under `~/Library/Application Support/DrPaste/`. Up to 500 items, deduplication, trim. `AppStorage` enum encapsulates paths.

**Keyboard layout repair.** Character mapping QWERTY ↔ ЙЦУКЕН. Scoring via `NSSpellChecker.checkSpelling`. The Cyrillic table is the only non-English content left in the source tree — it's data, not a comment.

## Icon

"Dr" reads as **PhD / scholar / educated**, not medical. The current placeholder `AppIcon.svg` is a clipboard with a rounded square frame; a higher-quality color icon (clipboard with ⌘V glyphs, charcoal background, metallic clip) is supplied as PNG and picked up automatically by `AppBrand.nsIcon`. `MenuBarIcon.svg` is a monochrome template version of the same idea.

## Build & run

```bash
cd ~/Dropbox/"Claude My"/DrPaste
swift run
```

Release build: `swift build -c release && ./.build/release/DrPaste`.

With an environment-provided Anthropic key: `ANTHROPIC_API_KEY=sk-ant-... swift run`.

To force a specific engine: `CLIPMAC_ENGINE=monitor swift run`.

## License

GPL-3.0-or-later with attribution requirement via GPL §7(d). `LICENSE` contains the attribution clause and a pointer to the canonical text. The full canonical GPL is not reproduced — standard open-source practice. The license id is declared; the full text is publicly available.

Copyright `© 2026 iLya Os`. The handle `iLya Os` is the standard form used in copyright headers.

## Notable implementation gotchas

- **`ClipboardItem.semantic` must be `var`, not `let`.** Transformations mutate it.
- **Top-level `MainActor.assumeIsolated { ... }`** in main.swift. `AppDelegate` is `@MainActor`; its `init()` is main-isolated; top-level code in Swift 6 is not main-isolated by default.
- **Carbon `kVK_*` constants are `Int`; `CGKeyCode` is `UInt16`.** Use `switch Int(kc) { case kVK_UpArrow: ... }`.
- **CGEventTap callbacks arrive on the main runloop** when the source is added via `CFRunLoopGetCurrent()` from the main thread.
- **Carbon `RegisterEventHotKey` does not require Accessibility** — the foundation of Limited Mode.
- **Limited Mode panel** must use a styleMask **without** `.nonactivatingPanel` and override `canBecomeKey: true`. An `NSPanel` with `.nonactivatingPanel` cannot become key window.
- **`HudHostingView<Content: View>: NSHostingView`** overrides `acceptsFirstMouse(for:) -> true`. Without this, clicks in the non-activating panel are dropped.
- **`Bundle.module`** is generated only when `resources: [.process("Resources")]` is set in Package.swift.
- **`NSAttributedString` foreground colors** in RTF source are almost always literal black. Remap to `NSColor.labelColor` so Dark Mode renders correctly. Catalog colors (`linkColor`, `systemBlue`) adapt natively and must be left alone.
- **Pasteboard write order:** `clearContents` → `setString` / `setData` / `writeObjects` → set `watcher.ignoreNextChange = true`.
- **HudState threading** — `@MainActor`. AppDelegate is also `@MainActor`. CGEventTap callbacks arrive on the main runloop already.
- **Preview computation token** (`previewToken`) guards against stale AI results during fast action switching.
- **Synthetic CGEvents** carry `eventSourceUserData = DrPasteSyntheticMarker` so the EventTap recognises and skips its own posted events.

## Roadmap

The active backlog lives in `BACKLOG.md`. Highlights:

1. Ship as a signed `.app` bundle with `.icns` and notarization.
2. Real Launch on Login (`SMAppService.mainApp`).
3. iCloud Keychain sync for provider keys.
4. Unit tests for pure modules (initial cut in 0.12.0).
5. Per-app AI provider override.
6. Drag-and-drop image into HUD.
7. HUD search / filter (revisit with cleaner mode separation).
8. Skills / Marketplace registry for shareable action packs.

## Related notes in personal profile

iLya Os — engineer / inventor, 30+ patents, prefers embedded / edge AI, dislikes unnecessary wrappers. Comfortable working directly against low-level APIs (Carbon, CGEventTap, NSPanel) without third-party libraries. Open-source orientation. Copyright headers use the handle **iLya Os** (lowercase i, uppercase L, no period).
