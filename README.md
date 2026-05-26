# DrPaste

> Press, browse, paste — the Paste gesture, extended.

DrPaste is a native macOS utility that doesn't try to be another clipboard manager. It tries to be an **extension of the Paste gesture itself**.

Hold `⌥⌘V`, see a quiet HUD over your work, browse history and transformations with arrow keys, release — and the chosen result is pasted at your cursor. Plus `⌥⌘C` for Quick Copy, `⌥⌘X` for Cut & Replace, and a context-aware action registry that adapts to whatever's in your clipboard.

## How it feels

```
  press     ⌥⌘V                     → HUD fades in over your work
  ↑ ↓       in clipboard history    → preview updates instantly
  ← →       in transformations      → live preview of the result
  release                            → result is pasted at the cursor
  esc                                → HUD vanishes, nothing changes
```

Also:
```
  ⌥⌘C       Quick Copy (no HUD, audio feedback)
  ⌥⌘X       Cut & Replace — cut goes to history, then pick a replacement
  ⌘+ / ⌘-   Adjust HUD font size, persists across sessions
```

## What's in the box

**Universal semantic clipboard.** Each clipboard event captures every NSPasteboard representation losslessly — TSV from Excel, RTF + HTML + proprietary metadata from Word, file URLs from Finder. Paste-as-is restores every representation, so the destination app gets the exact same data the source put there. Semantic interpretation (URL / JSON / Email / code / markdown / table / files / image / PDF / unknown) is a layer on top, used only for preview and action filtering.

**Press-and-hold HUD.** Translucent overlay (`NSVisualEffectView.hudWindow`) over your active app. Non-activating — never steals focus. Two-dimensional navigation: vertical for history, horizontal for transformations. Release commits, Escape cancels.

**Context-aware actions, computed locally.** A URL gets "Clean URL" (strips `utm_*`, `fbclid`, `gclid` etc.). JSON gets pretty/minify/flatten/extract keys. Markdown gets HTML/extract headings/extract links. Files get paths, filenames, bash-quoted lists, Markdown links, SHA-256, reveal in Finder. Images get **OCR via Vision** (extract text), **QR/barcode decode**, grayscale, rotate, resize, compress, strip metadata. Plain text gets Title/Sentence/camel/snake/kebab case, base64 encode/decode, URL encode/decode, slugify, word count, sort & unique lines.

**★ Generate QR code from text or URL.** Highlight feature. Text → image QR through `CIQRCodeGenerator` locally. Share a link from laptop to phone by camera, no AirDrop or messaging.

**★ Type Slowly action.** Bypasses paste-blocking forms (banking, government, password fields with `onpaste="return false"`). Types character-by-character through `CGEvent.keyboardSetUnicodeString` with 200ms ± 20% jitter. Imitates human typing precisely enough that anti-paste detection treats it as real keystrokes.

**Bring Your Own AI.** Optional. Provide an Anthropic API key (env var `ANTHROPIC_API_KEY` or `~/Library/Application Support/DrPaste/providers.json`) and four AI actions become available: summarize, translate RU↔EN, fix grammar, formal tone. If no key — actions still appear in the list with a clear "AI provider not configured" notice, click recovery to set it up. The product is fully useful offline.

**Visible action failures.** "Неудачная попытка тоже попытка" — failures aren't hidden. AI without a key, malformed JSON, OCR with no recognized text, all show inline notices in the HUD preview with recovery actions. On commit, the original content is still pasted (paste-as-is) so you never end up with nothing.

**Two interaction modes, auto-selected.**

- **Full Gesture Mode** (the real thing): `CGEventTap` intercepts the hotkey and swallows it, the HUD is a non-activating `NSPanel`, modifier release commits. Requires Accessibility permission.
- **Limited Mode** (no permissions, no friction): `RegisterEventHotKey` summons the HUD, which becomes a regular key window. Enter commits, Escape cancels, mouse works. A banner explains how to upgrade to gesture mode.

When you grant Accessibility later, DrPaste detects it and offers to restart into Full Gesture Mode.

**Keyboard-first, mouse-available.** Like Spotlight, like Cmd-Tab. Mouse hover highlights, single click selects, double click commits. But you never have to leave the keyboard.

**Sound feedback.** Tink for copy success, buzz for copy failure (real detection via pasteboard.changeCount diff), click for paste success, tick for each Type Slowly character. Each sound toggleable in Settings (when Settings UI ships).

**Status menu with Recent items.** Click the menu bar icon — submenu "Recent clipboard" shows the last 15 items with type icons. Click any to paste-to-frontmost (saves the frontmost app via `menuWillOpen`, activates it, simulates ⌘V). Clear history at the top, Settings and About below.

**System-native styling.** Translucent HUD via `NSVisualEffectView(.hudWindow)`. System accent color follows your `System Settings → Appearance` choice. Light and dark mode automatic. Source label under HUD header: "Copied from Safari — OpenAI Docs", "Copied from Excel — Budget.xlsx", "Copied from VS Code".

## Install & run

Requires macOS 13 or later and Swift 5.9 / Xcode 15 or later.

```bash
git clone <repo-url>
cd DrPaste
swift run
```

Release build:

```bash
swift build -c release
./.build/release/DrPaste
```

On first launch macOS will prompt for Accessibility permission. If you grant it — DrPaste runs in Full Gesture Mode immediately. If you don't — it runs in Limited Mode and the HUD shows a button to enable gesture mode later.

### Optional AI

Create `~/Library/Application Support/DrPaste/providers.json`:

```json
{
  "anthropicAPIKey": "sk-ant-...",
  "anthropicModel": "claude-sonnet-4-6"
}
```

Or set `ANTHROPIC_API_KEY` in your environment.

## Keyboard reference

| Key                         | Action                                          |
|-----------------------------|-------------------------------------------------|
| `⌥⌘V`                       | Summon HUD                                      |
| `⌥⌘C`                       | Quick Copy (system ⌘C + audio feedback)         |
| `⌥⌘X`                       | Cut & Replace (cut → HUD → pick → replace)      |
| `↑` / `↓`                   | Navigate clipboard history                      |
| `←` / `→`                   | Navigate transformations                        |
| release `⌥⌘` (Full Mode)    | Commit — paste at cursor                        |
| `Return` (Limited Mode)     | Commit — paste at cursor                        |
| double-click                | Commit                                          |
| `Esc`                       | Cancel                                          |
| `⌘+` / `⌘-`                 | Increase / decrease HUD font size               |
| `⌘0`                        | Reset font size                                 |

## Architecture

```
NSPasteboard ──(0.5s)──► ClipboardWatcher ──► ClipboardStore
   |  ▲                                              │
   |  │   raw representations                  @Published items
   |  │   (UTType → Data) + source meta              │
   |  │                                              ▼
   └──┤   ┌──► hotkey ──► EventTap or Carbon ──► AppDelegate ──► HudState
      │   │                                                          │
      │   │   ContextDetector ───►                                    │◄──── ActionRegistry
      │   │                                                          ▼
      │   │                                                  HudView (SwiftUI)
      │   │                                                          │
      │   │                                       release / Enter / dbl-click
      │   │                                                          ▼
      │   │                                                ApplyOutcome routing
      │   │                                                          │
      │   │                              ┌─────────────┬─────────────┼──────────────┐
      │   │                              │             │             │              │
      │   │                            preview      failed      sideEffect   alternativeCommit
      │   │                              │             │             │              │
      │   │                       standard paste    paste-as-is   execute       Type Slowly
      │   │                              │             │             │              │
      │   └─── PasteboardWriter restores all representations + simulated ⌘V         │
      │                                                                              │
      └─── TypeSimulator: CGEvent.keyboardSetUnicodeString per character ────────────┘
```

Source layout:

- `ClipboardModel.swift` — Universal Semantic ClipboardItem with representations + Store + Watcher + SemanticClassifier + PreviewSynthesizer + SourceResolver
- `ContextDetector.swift` — ContentContext bitmask (URL/JSON/code/markdown/table/multiline/mixedScript/layoutWrong/qrEligible)
- `Actions.swift` — ApplyOutcome enum, ClipboardAction protocol, core actions, ActionRegistry
- `TextActions.swift` — case transforms, encoding, slugify, word count, **★ QR generation**
- `URLActions.swift` — clean URL, just domain, MD link, HTML link, query params
- `JSONActions.swift` — pretty, minify, extract keys, flatten, remove nulls
- `MarkdownActions.swift` — to plain, extract headings, extract links
- `MoreActions.swift` — code (wrap, tabs↔spaces), table (CSV→JSON/MD), rich→markdown
- `FileActions.swift` — paths, filenames, bash list, MD links, size, SHA-256, reveal
- `ImageActions.swift` — **★ OCR**, decode QR, strip metadata, resize, compress, grayscale, rotate, invert
- `KeyboardLayoutRepair.swift` — RU↔EN swap with NSSpellChecker scoring
- `HotkeyEngine.swift` — EventTap, Carbon, GlobalMonitor + 3 hotkeys (V/C/X)
- `TypeSimulator.swift` — Type Slowly via keyboardSetUnicodeString
- `SoundFeedback.swift` — 5 cues + per-cue toggle + global volume
- `HUD.swift` — HudState, HudPanel, HudView with failure/side-effect/alternativeCommit notices
- `AIProvider.swift` — Anthropic provider + AIAction returning ApplyOutcome
- `PasteSimulator.swift` — ⌘V/⌘C/⌘X + lossless PasteboardWriter from representations
- `AppBrand.swift` — name, icons (colored for HUD, template for menu bar), About credits
- `main.swift` — AppDelegate, status menu with Recent submenu, lifecycle

## Status

Working pre-release proof-of-concept. Most features from the original design are implemented. Settings UI with action playground (toggle/edit/Run on each action against a sample input) is the largest remaining piece — currently the "Settings…" menu item opens `providers.json` as a stub.

See [BACKLOG.md](BACKLOG.md) for planned features.

## License

DrPaste is licensed under **GNU GPL v3.0 or later**, with an additional attribution requirement under Section 7(d) of the GPL: derivative works must preserve the original author attribution.

In plain words: fork freely, build on it freely, but the result must also be open source under a compatible license, and "iLya Os" must remain credited as the original author. See [LICENSE](LICENSE) for the exact terms.

## Acknowledgements

Inspired in spirit by Flycut, Maccy, Paste, and Raycast — open clipboard utilities that paved the way for keyboard-first paste UX on macOS. Different from each of them in philosophy: DrPaste is not a database of your clipboard or a productivity dashboard. It tries to be invisible.
