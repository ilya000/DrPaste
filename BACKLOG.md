# DrPaste — Backlog

Active work, structured roadmap, and a condensed changelog. Historical
free-form notes were collapsed into this document; the long-form discussion
that preceded each shipped item lives in git history.

## Entry conventions

Every active entry uses the same template:

```
### #N — Short title

**Status:** planned | in progress | blocked.
**Touches:** files / modules affected.
**Context:** 1–2 paragraphs on the why.
**Requirements:**
- bullet 1
- bullet 2
**Implementation notes:** optional Swift sketches, edge cases, migration paths.
```

Tone is neutral, English, technical. No first-person, no emoji, no addressed
dialogue. Items are written so a reader picking the file up cold can act on
them.

---

## Active backlog

Sorted roughly by value-to-effort ratio, not strict priority. Pick whatever
matches the current session's focus.

### #A1 — Ship as a signed `.app` bundle with `.icns` and notarization

**Status:** planned. Structural blocker for several other features.
**Touches:** new build script, `Info.plist`, code-signing identity, notarization
pipeline, distribution channel.
**Context:** DrPaste currently builds as a SwiftPM executable and runs via
`swift run`. Without a `.app` bundle, the macOS Dock shows a generic icon,
the menu bar tooling has no proper Info.plist metadata, Login Item enrolment
can't be wired up, and the iCloud Keychain entitlement is unreachable.
**Requirements:**
- Generate a proper `.app` bundle from the SwiftPM build product
  (`Contents/MacOS/DrPaste`, `Contents/Info.plist`,
  `Contents/Resources/AppIcon.icns`, `Contents/PkgInfo`)
- Acquire an Apple Developer ID, sign with `codesign --options runtime`
- Notarize via `xcrun notarytool submit` and staple
- Build a DMG (`hdiutil create`) for distribution
- GitHub Release workflow that produces the DMG on tag push

**Implementation notes:** The simplest path is a `Makefile` or `scripts/build.sh`
that wraps `swift build -c release`, copies the binary into a staging
`DrPaste.app` skeleton, embeds the icon and Info.plist, codesigns, and
notarizes. Future contributors should not need Xcode.

**Release-day checklist (do not skip):**

- Default `APIKeyStorage.fallbackOnly` back to `false` for shipped builds
  (currently `false` already, but the per-user toggle in Settings → AI may
  have been flipped on by developers running unsigned `swift run`). Surface
  a migration path so users who have keys in the fallback file get moved
  back into Keychain on first signed launch: detect the fallback file at
  startup, prompt "Move N API keys from local file into Keychain?", on
  accept call `APIKeyStorage.save(...)` for each (which now hits Keychain
  cleanly thanks to the stable code signature), then delete the file. On
  decline, leave the toggle on for that install.
- Remove the "API key storage" section from Settings → AI **only after**
  the signed-build migration path is in place. Until then the toggle stays
  visible so power users still on unsigned builds keep their escape hatch.
- Re-evaluate whether iCloud Keychain sync (`kSecAttrSynchronizable`)
  should be on by default for cloud provider keys (depends on App Sandbox
  state and entitlements — see #A3).

---

### #A2 — Launch on Login (real implementation)

**Status:** planned. Depends on #A1.
**Touches:** new `LoginItemManager.swift`, `SettingsWindow.swift` General tab.
**Context:** The Settings → General toggle currently shows a placeholder. With
a signed `.app` bundle in place, this should switch to using
`SMAppService.mainApp` (macOS 13+) to register / deregister the app as a
login item.
**Requirements:**
- Toggle binds to `SMAppService.mainApp.status` and `.register()` / `.unregister()`
- Reflect actual current state in the UI, including the system-level
  "All login items" pane disabled state
- Surface errors (entitlement missing, OS too old) inline rather than via alert

---

### #A3 — iCloud Keychain sync for AI provider keys and preferences

**Status:** planned. Depends on #A1.
**Touches:** `APIKeyStorage.swift`, `ActionConfig.save()`/`.load()`,
`SettingsWindow.swift` General tab toggle.
**Context:** Keys are currently stored locally (Keychain when signed, plain
JSON fallback otherwise). Once a signing identity is in place, iCloud
Keychain sync can be enabled by flipping `kSecAttrSynchronizable = true`. The
action / transformation / preferences config can sync via ubiquitous
`NSUbiquitousKeyValueStore` or a CloudKit container.
**Requirements:**
- Sound default: keys sync, preferences sync, clipboard history stays local
- Migration: existing local-only keys move to synced container on first
  enable, with a confirmation step
- Settings UI: replace the existing "(coming soon)" copy with a working toggle

---

### #A4 — Unit tests for pure modules

**Status:** in progress (initial cut shipped in 0.12.0).
**Touches:** `Package.swift` (test target), `Tests/DrPasteTests/*Tests.swift`.
**Context:** No automated tests existed before 0.12.0. The pure-function
modules (`RichTextHelpers`, `TransformationRuntime`, `KeyboardLayoutRepair`,
`SemanticClassifier`, `ContextDetector`) cover the riskiest edits — they
break silently when downstream UI code is refactored. They're also cheap to
test: no AppKit, no async, no I/O.
**Requirements:**
- Test target in `Package.swift` linked only to the pure modules ✓ (0.12.0)
- Initial coverage for each public function with happy path + at least one
  edge case ✓ (0.12.0)
- Expansion: behavior-change regressions for every ID-stable transformation,
  fuzz-style inputs for the regex engines, golden-output tests for
  `attributedStringToMarkdown` round-trips
- CI invocation: `swift test` from the repo root passes locally and on Mac CI

---

### #A5 — Per-app AI provider override

**Status:** planned. Productivity nice-to-have.
**Touches:** `AIProvider.swift` (new override map), `ContextDetector` (record
`sourceBundleID`), Settings UI new section.
**Context:** Different frontmost apps benefit from different AI providers
(e.g. Anthropic for prose work in Pages, a local Ollama model for code in
Xcode). Today the active provider is global.
**Requirements:**
- Mapping `bundleID → providerID` stored in `ActionConfig`
- When an AI action runs, look up the override against the currently focused
  app's bundle ID; fall back to default if no entry
- Settings → AI new section to manage the mapping, with a "+ Add app override"
  picker using `NSOpenPanel` on `/Applications`

---

### #A6 — Drag-and-drop image into HUD

**Status:** planned. Onboarding affordance.
**Touches:** `HudPanel`, `HUD.swift`.
**Context:** Currently the only way to get content into DrPaste is to copy
it. Letting users drop an image (file or in-pane data) onto the HUD would
make image actions discoverable without a copy step.
**Requirements:**
- HudPanel registers as drag destination for image UTTypes
- On drop, synthesize a ClipboardItem from the dropped data (image data →
  image item, file URL → image item via NSImage(contentsOf:))
- Visual feedback: drop zone overlay, cursor change

---

### #A7 — HUD search / filter (revisit)

**Status:** planned. Previously reverted because of mode-switch UX.
**Touches:** `HudView`, `HudState`.
**Context:** A previous attempt added a search field that intercepted `↑↓`
navigation; the conflict made the gesture less reliable. Revisit with a
clearer mode separator: typing letters during a held HUD filters; arrow keys
always navigate the filtered set; `esc` clears the filter without closing.
**Requirements:**
- Filter buffer overlays the header, fades when empty
- Filter applies to title, source app name, content snippet
- Reset on HUD close
- No conflict with the existing `⌘+` / `⌘−` / `⌘0` font controls or `⌫` delete

---

### #A8 — Skills / Marketplace registry for shareable action packs

**Status:** planned. Larger initiative; revisit once core is stable.
**Touches:** new `ActionPack` JSON format, `ActionRegistry` import path,
network fetch / install UI.
**Context:** Custom AI prompts and transformation descriptors are already
JSON-exportable. Bundling a curated set of related actions as a downloadable
"pack" (e.g. "SQL helpers", "Translator suite for ES/RU/EN", "Markdown
toolkit") would give users an easy way to enrich their setup.
**Requirements:**
- Pack format: JSON with metadata (name, author, version, description) plus
  the actions array
- In-app pack browser: built-in curated list, plus URL-based import
- Sandboxing: imported actions can't escalate privileges or call URLs the
  app wouldn't already call

---

## Changelog

Shipped versions. Each bullet is one observable change. Implementation-level
notes that informed each item live in this file's git history — every
revision of `BACKLOG.md` going back to the project's first commit can be
recovered via `git log --follow BACKLOG.md` and inspected with
`git show <commit>:BACKLOG.md`. The early revisions are bilingual and
include verbose technical reasoning per "Правка"; this current revision is
the curated, English-only working document.

### 0.12.0 — Internal alpha: editable built-ins, design philosophy, polish

This is the first alpha cut suitable for internal testing. The action
surface has been thoroughly cleaned up, the two foundational design
principles (`two surfaces` and `three tiers`) are now recorded as project
philosophy in `SKILL.md`, and a long tail of UX paper cuts has been fixed.

**Action surface — editable built-ins**

- Full migration of bundled transformation actions (UPPERCASE, lowercase,
  sort lines, JSON pretty/minify/extract, slug, base64, URL percent-encode,
  word count, Markdown → plain, Markdown extract headings / links, URL strip
  tracking, code wrap, tabs↔spaces, title / sentence / camel / snake / kebab
  case, trim, unique lines) from hardcoded `ClipboardAction` structs to
  descriptors in `DefaultTransformationSeed`. 24 engines, 26 seeded actions.
  Users can rename, retitle, reorder, change parameters, or delete any of
  them just like a user-created transformation. Existing user
  customizations (titles, hotkeys, ordering, enabled flags) carry over via
  stable `builtin.*` IDs.
- Removed 5 hardcoded action structs with no marketing weight: Transpose,
  Bash-quoted list, Query params as table, Size info, SHA-256 hash. The
  bundled handler catalogue is now lean: 26 hardcoded handlers + 26 seeded
  transformation descriptors = clean, intentional, every entry earns its
  place.
- Engine picker in the New Transformation editor filters by
  `userPickable` so 10 composable building blocks are shown instead of all
  24 internal recipes (camelCase / slugify / mdExtract / ... are
  intentionally hidden — they back specific bundled built-ins).
- Built-in handler picker for new built-ins is now grouped by namespace
  into sections: Image / Rich text / URL / Table / JSON / Files / Text & utility.
  Automatic bucketing via ID prefix with a small explicit override map for
  the handful of cross-cutting handlers.
**Settings UX — Tier 2 promotions**

- Per-action hotkey assignment is now inline in the Settings row via the
  same `HotkeyRecorderField` the editor uses. Assigning a shortcut no
  longer requires opening the editor dialog (it was a Tier 2 operation
  trapped at Tier 3). The editor still exposes the recorder for power
  users tuning many fields at once.
- Settings → Actions list unified across all three action kinds (built-in,
  custom AI, custom transformation). One reorderable list. Disabled rows
  stay visible (dimmed) instead of disappearing.
- Removed the ambiguous trash button from the action row. Deletion of a
  descriptor now lives only inside the editor footer (pencil → Delete),
  where the destructive operation has the right gravity. Row UI is back
  to: drag · checkbox · type-icon · title · hotkey · pencil · Run.
- Hotkey recorder auto-steals: assigning a hotkey already held by another
  action transparently unbinds the previous owner, with a non-blocking
  notice in the editor. Orphan bindings (action no longer exists) are
  garbage-collected at startup and after every config mutation.
- Settings → General gained Import / Export of configuration and a Factory
  Reset button. The standalone Import / Export tab was removed.
- Settings → AI gained a "Skip macOS Keychain" toggle. Unsigned builds
  trigger a login-password prompt on every launch because Keychain ACL is
  bound to the binary's code signature; every rebuild changes the hash.
  When the toggle is on, keys go to a plain-JSON fallback file
  (`~/Library/Application Support/DrPaste/provider-keys-fallback.json`,
  user-only 0o600 permissions). Default off — flip on for dev workflow.
  Release-day checklist for #A1 records the migration-back path.
- Rich-text preview in Dark Mode: foreground colors embedded in RTF (always
  black in the source) are remapped to `NSColor.labelColor` so the text is
  legible. Catalog colors like `linkColor` remain untouched.
- Rich-text preview in HUD: removed the redundant outer SwiftUI ScrollView
  that collapsed the embedded NSScrollView to zero height.
- PDF items show a real first-page thumbnail in the HUD preview instead of
  a generic "PDF NN KB" placeholder. New snapshots render the thumbnail at
  snapshot time; previously-stored PDFs render lazily and cache the result.
- Image actions (OCR, decode QR, strip metadata, resize, grayscale, …) now
  also accept rich-text items that carry embedded image attachments from
  Pages, Word, or Mail. A `RichTextImageExtractor` walks the attributed
  string, caches the "has image" verdict per item ID, and extracts the
  first attachment when an action runs.
- All Russian comments and AI-conversational phrasing translated to neutral
  business English across 29 source files. Only the Cyrillic keymap data in
  `KeyboardLayoutRepair.swift` remains (required by the layout-repair feature).
- `.gitattributes` locks all text files to LF regardless of contributor
  platform. Audit confirmed every Swift file is already pure UTF-8 with LF.
- New menu-bar icon (clipboard + ⌘V monochrome template). New app icon
  loader path that prefers `.icns`, then PNG, then SVG. `NSApp.applicationIconImage`
  is now set at launch so the About panel and Cmd-Tab show the branded icon.
**Reliability fixes**

- Type Slowly was typing only the first character and stopping. Cause:
  synthetic events were not tagged with `DrPasteSyntheticMarker`, so the
  cancellation monitor (which watches keyDown to detect "user typed
  something — abort") saw the first synthetic key as user activity and
  flipped the abort flag. Both `postUnicode` and `postKey` now tag every
  posted CGEvent with the marker.

**Quality bar**

- Initial unit test cut: 72 tests across `RichTextHelpers`,
  `TransformationRuntime`, `KeyboardLayoutRepair`, `SemanticClassifier`,
  `ContextDetector`. `Tests/DrPasteTests/` directory, test target wired
  into `Package.swift`, `swift test` runs them locally.
- BACKLOG and README rewritten in strict English; this BACKLOG keeps a
  detailed per-version Changelog so the project's evolution is preserved
  inside the file (full pre-cleanup history is still in git).
- Recorded two foundational design principles in `SKILL.md` so future
  work doesn't violate them: (1) **Two-surface model** — HUD runs (shows
  only `enabled && applicable && context-matching`), Settings manages
  (shows everything including disabled, dimmed); (2) **Three-tier action
  hierarchy** — Tier 1 curated defaults for 90% of users out-of-the-box,
  Tier 2 Settings toggles for the next 9%, Tier 3 editor for the 1%
  power users. New bundled actions default disabled unless they earn a
  Tier 1 spot.

**State of the build**

- This release is the internal alpha. The action surface is intentional,
  the design principles are codified, the test target is real. Distribution
  via signed `.app` bundle + notarization + DMG (`#A1`) is the next stop;
  until then the app runs via `swift run`. The Skip-Keychain toggle is a
  recommended on for that workflow.

### 0.11.0 — Default AI provider, Progress HUD, light engine expansion

- Default AI provider radio button in Settings → AI. Auto-promotes to the
  first provider that passes its connection test, via `shouldAutoPromoteDefault()`
  in `ProviderEditor.saveWithTest()`. `reconcileDefaultProvider()` in
  `AIProviderRegistry.init` heals stale state (default referenced a provider
  that no longer has a key).
- Seeded AI actions follow the default dynamically — `providerID == ""` is
  a sentinel meaning "use whichever provider is currently default".
  `DefaultAISeed.currentSeedVersion = 2` migration rewrites previously
  hardcoded `"anthropic"` providerIDs to `""`.
- ProgressHUD mini-window appears instantly when a direct-trigger hotkey
  fires, hides on completion. `ProgressHUDController.shared.show(label:)`.
- Welcome window auto-show on first launch via `showIfNeeded()` (delayed
  0.5s so the menu bar item is ready).

### 0.10.0 — Engine architecture light, action editor polish

- `CustomTransformationDescriptor` model — users build deterministic text
  manipulations through a parameter editor instead of writing code. Initial
  engines: regex_replace, find_replace, prepend, append, wrap, line_filter,
  case_change, sort_lines, unique_lines, json_format.
- Unified ActionEditor — one dialog covers built-in, custom AI, custom
  transformation. Mode is locked when editing; only the title, hotkey,
  applicable types, and mode-specific config differ. Saves through a single
  `ActionEditorContext` switch.
- AI Action templates library with bundled translate / fix grammar /
  summarize / explain code / polish presets, seeded into `config.customAI`
  on first launch.
- Rich Text NSTextView wrapper (`RichTextPreviewView`) — bypasses SwiftUI's
  lossy `AttributedString(_, including: \.swiftUI)` conversion and renders
  the NSAttributedString natively, preserving bold, italic, links, colors,
  attachments.
- Welcome window on first launch with AX-permission warning section,
  hotkey reference, "Don't show again" toggle persisted to UserDefaults.

### 0.9.0 — Sound feedback, type icons, unified palette

- Type icons in HUD action chips and Settings action rows
  (`BuiltinActionIcons.iconName(for:)`).
- Sound feedback (copy / paste / type / delete) with per-cue toggles and a
  volume slider that previews on change. Bundled AIFF cues in
  Resources/Sounds/ with system NSSound fallback. 200 ms throttle to
  prevent duplicate firings.
- Curated default-enabled subset (`CuratedDefaults.enabledByDefault`) so
  new installs don't drown in actions — about 5–10 core actions per content
  type are enabled by default, the rest sit in the palette.
- Action palette ("Browse") popover for one-click enabling of disabled
  actions per content type. Categorized: Core / Plain text / URL / JSON /
  Table / Markdown / Code / Rich text / Image / Files / AI.
- Plus: Cyrillic samples removed, sound preview-on-toggle, drag-handle
  visual ("line.3.horizontal" icon), provider badge icons in HUD chips.

### 0.8.0 — Append Copy, AI test required, HUD polish

- `⌥⌘S` Append Copy with session-aware accumulator and 5-minute timeout.
  First press starts a fresh accumulator; subsequent presses (within 5 min
  and without any other DrPaste hotkey in between) extend the same entry.
- AI provider Save requires a passing connection test
  (`saveWithTest()` blocks commit unless `testConnection()` returned success).
- HUD zoom percentage shown in the footer; `⌘+` / `⌘−` / `⌘0` font controls
  persist via `drpaste.hud.fontScale`.
- Backspace in HUD deletes the focused history item (Limited Mode local
  monitor; Full Gesture Mode handled inside EventTap callback).
- Type Slowly action auto-cancels on user activity — global monitors for
  keyDown / mouse / app-change / space-change set `session.cancelled`.
- Welcome window AX-access warning section; "Applies to" full type domain
  in ActionEditor with disabled checkboxes for inapplicable types; bypass /
  banking / anti-cheat phrasing stripped per legal review.

### 0.7.0 — Unified Action Editor, per-action hotkeys

- One editor (`ActionEditor.swift`) for built-in / AI / transformation
  actions. Mode picker is segmented but locked when editing an existing
  action. Shared sections: title, hotkey, applicable types, test panel.
- Per-action global hotkey: assign any combination, pressing it applies the
  action to the current clipboard and pastes immediately into the frontmost
  app, no HUD. Carbon `RegisterEventHotKey` based (`ActionHotkeyManager`).
- HotkeyRecorder UI: click → press combination → captured. Esc cancels,
  Delete clears.

### 0.6.0 — Engine architecture (light), per-action hotkeys foundation

- First engine system for user-defined transformations (10 engines:
  regex_replace, find_replace, prepend, append, wrap, line_filter,
  case_change, sort_lines, unique_lines, json_format). Built-ins still
  hardcoded — full migration shipped in 0.12.0.
- `CustomTransformationDescriptor` data model with engineID + params dict.
  Rebuilt into runtime `CustomTransformationAction` on every config change.
- Reverted HUD search field (introduced earlier in 0.6 cycle) because the
  arrow-key mode-switch UX broke gesture reliability. Search idea is now
  tracked in the active backlog as #A7.

### 0.5.0 — Drag-reorder, palette, RTF playground

- Drag to reorder actions in Settings. Identity (Paste as is) stays pinned
  at position 0.
- Browse palette popover for adding actions from a categorized list. Single
  click toggles enabled.
- Real RTF sample in the Rich Text playground (programmatically generated,
  saved with a fixed filename so code edits propagate immediately).
- Provider badges in Settings AI action rows (provider icon + branded color).

### 0.4.0 — Settings two-column layout, custom titles

- Two-column Settings playground: sample input + Result pane, per content
  type tabs. Drag-reorder deferred to 0.5.0.
- Renaming built-in actions through the editor (`customTitles` map). The
  display title for any action is now `customTitles[id] ?? action.title`.
- Curated default-enabled subset (lite version) — full curation shipped in 0.9.0.
- Cut & Replace `⌥⌘X` UX option: cursor starts on second item (skip the
  just-cut item). Default off matches native cut+paste.

### 0.3.0 — Multi-provider AI, rich-text round trips, brand polish

- Multi-provider AI registry. Concrete providers: Anthropic, OpenAI,
  Gemini, Grok (xAI), Mistral, DeepSeek, Ollama, LM Studio, llama.cpp,
  custom OpenAI-compatible endpoint. Single `AIProvider` protocol; concrete
  implementations are tiny.
- Keychain-based API key storage (`APIKeyStorage`) with plain-JSON fallback
  for unsigned builds where Keychain rejects writes from non-signed
  processes. Keys are never persisted to `providers.json`.
- Rich text round trips: `RichTextHelpers` exposes
  `attributedStringToMarkdown`, `markdownToAttributedString`,
  `attributedStringToHTML`, `attributedStringToWiki`. Used by both
  rich-preserving AI actions and the dedicated Rich → MD / HTML / Wiki actions.
- Spanish translate seeded as default AI action.

### 0.2.0 — Iteration 2 polish

- Custom About window (560×500) — `NSApp.orderFrontStandardAboutPanel` is
  too cramped; new `AboutWindowController` provides breathing room with
  credits, version, links.
- Settings → General: iCloud sync placeholder, Launch on Login placeholder
  (both stubs awaiting code-signing).
- HUD polish: thumbnail for large images (max 600 pt, cached PNG in
  imagesDir, never renders full-size); corner-radius defensive re-apply on
  every layout (vibrant material has its own layer that was stripping the
  squircle); compact single-row header with close-X button; content-meta
  row above preview pane ("123 words · 4 KB · ru-RU").
- Cut & Replace `⌥⌘X` reliability fix (five-layer pipeline):
  layer 1 — programmatically release physical Option before posting
  synthetic ⌘X so the target app sees a clean ⌘X not ⌥⌘X;
  layer 2 — tag every synthetic event with `DrPasteSyntheticMarker` so the
  EventTap ignores them and avoids recursion;
  layer 3 — watchdog timer that force-resets `hudIsActive` if the HUD failed
  to open in time;
  layer 4 — visibility verification after a short delay and retry;
  layer 5 — event-driven verification (poll pasteboard changeCount) instead
  of fixed asyncAfter.
- GitHub handle aligned to `ilya000`; `/issues` removed from About credits
  pending public release readiness.

### 0.1.0 — Initial public version

- Universal Semantic Clipboard Layer (every UTType representation
  preserved losslessly).
- Visible action failures with recovery actions.
- Local image actions (OCR via Vision, QR decode, strip metadata, resize,
  grayscale, rotate).
- Content-aware action expansion including Generate QR from URL / text.
- Menu bar icon (template, standard width).
- Status menu reorganization with Recent submenu.
- Type Slowly action.
- `⌥⌘C` Quick Copy.
- Initial sound feedback prototype.
- Full Gesture Mode (EventTap) + Limited Mode (Carbon) with auto-detect.
- Press-and-hold HUD with mouse support, rich-text preview, branding,
  light/dark + system accent, font scaling.
- Initial AI provider (Anthropic-only).
- Universal clipboard layer skeleton, context detector, base local actions,
  keyboard layout repair, hotkey engines.
