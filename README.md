# DrPaste

A press-and-hold clipboard utility for macOS.

DrPaste extends the system Paste gesture rather than replacing it. Hold `⌥⌘V`, browse your clipboard history and transformations in a HUD, release to paste. There is no separate window to manage, no panel to dismiss — the workflow is keyboard-first and gesture-driven.

Current version: **0.58.0** (alpha).

## Features

**Universal clipboard history.** Text, rich text, URLs, images, files, PDFs — preserved losslessly with original formatting and full source metadata (app, window title, timestamp). PDF and image items render as actual thumbnails in the HUD preview, not generic icons. Up to 500 items, automatic deduplication.

**Press-and-hold paste gesture.** Hold `⌥⌘V`, navigate the HUD with arrow keys, release to paste. The selected entry, optionally transformed by an action, is delivered to the frontmost app's text cursor. Esc cancels without pasting.

**Paste and keep (`⌥⌘⏎`).** Inside the HUD, paste the focused item while keeping the HUD open — useful for filling forms with several values from history in one gesture.

**Region capture (`⌥⌘ + drag`).** Hold `⌥⌘` and drag a rectangle anywhere on screen to capture that region as a PNG. The capture lands in clipboard history and the HUD opens focused on it. Release `⌥⌘` to paste it into the originating app. Source app is recorded automatically (HUD label "Captured from Safari", etc.).

**Multi-provider AI with token streaming.** Connect to Anthropic Claude, OpenAI, Google Gemini, OpenRouter, xAI Grok, Mistral, DeepSeek, Groq, Cerebras, Together AI, Cloudflare Workers AI, Ollama (local), LM Studio (local), llama.cpp (local), or any OpenAI-compatible endpoint. AI responses stream into the HUD preview token-by-token so you can read partial output on flaky networks instead of staring at a spinner. Provider routing is fully transparent — every UI surface shows the *real* executing provider, with a visible reroute indicator when a default chat provider can't run an image action and runtime falls back to a cheaper image-capable provider.

**Editable built-in actions.** Every bundled transformation lives in the same descriptor model as user-created ones. Rename them, change their parameters, scope them to specific content types, assign hotkeys, reorder freely, or delete the ones you don't want.

**Custom AI actions.** Built-in templates for translate, summarize, fix grammar, polish prose, explain code, and more. Each action is editable — change the prompt, switch the provider, scope it to specific content types. Three AI modes:

- **Text → Text** — translate / rewrite / fix grammar / extract.
- **Image → Image** — pencil sketch, watercolor, cartoon (seeded), or any custom style you write a prompt for.
- **Text → Image** — generate a fresh image from a text concept (e.g. "AI: Whiteboard sketch").

**Custom transformations.** Build deterministic text manipulations using ~24 engines: regex replace, find/replace, prepend, append, wrap, line filter, case change, sort, unique, JSON format (pretty / minify / extract keys), trim, slug, base64, URL percent-encode, word count, Markdown extract, URL strip tracking, Unicode pseudo-fonts (~20 styles), Cyrillic ↔ Latin transliteration with variant auto-detect, and more. Configure, test, and save without touching code.

**Rich text aware.** Translate, fix grammar, or rewrite while preserving bold, italic, links, headings, lists, and inline code via Markdown round-trip. Convert rich text to Markdown, HTML, or MediaWiki markup. Convert Markdown source to rich text (paste into Mail / Pages / Notes / Word with formatting intact). Image actions (OCR, decode QR, strip metadata, …) also reach into embedded image attachments inside rich text from Pages, Word, or Mail. Extract links and headings now work on rich-text clips by reconstructing the Markdown source from the attributed string.

**Image actions.** OCR (Apple Vision), decode QR / barcodes, strip EXIF and GPS metadata, resize, compress JPEG, rotate left/right, grayscale, invert, ASCII art (now rich-text monospaced output, 40 columns by default for inline chat / code-comment use), AI stylize (pencil sketch / watercolor / cartoon / custom). Local actions run offline; AI actions require a provider.

**Unicode pseudo-fonts.** Render ASCII as `𝐁𝐨𝐥𝐝`, `𝐼𝑡𝑎𝑙𝑖𝑐`, `Script`, `𝔉𝔯𝔞𝔨𝔱𝔲𝔯`, `Double-struck`, `Sans-serif`, `Monospace`, `Fullwidth`, `Sᴍᴀʟʟ Cᴀᴘs`, `Circled`, `Squared`, `Upside-down`, and more — useful for Twitter / X, Telegram, LinkedIn, Discord profiles where Markdown is not rendered. New **Markdown styles → Unicode** action interprets inline `**bold**` / `*italic*` / `` `code` `` / `~~strike~~` markup and applies the matching pseudo-font span-by-span, dropping the markup characters.

**Per-action hotkeys.** Assign any global `⌥⌘<letter>` hotkey to any action. Tap the chord for instant trigger — the action pastes immediately (or shows a MiniHUD streaming loading panel for slow AI calls). Holding `⌥⌘` after releasing the letter (≥250 ms) opens BigHUD pre-focused on that action, with normal navigation and Gesture-Mode release-to-paste. Conflicting bindings auto-steal: assigning `⌥⌘T` to one action automatically unbinds it from any other action that previously held it, with a visible notice in the editor. Reserved chords (`⌥⌘V/C/X/S/⏎`) and system chords (Force Quit, Show Dock, etc.) are blocked with a feature-name hint.

**Append Copy (`⌥⌘S`).** Accumulate multiple selections into one combined clipboard entry. Universal accumulator handles plain text, rich text, and inline image attachments via `NSAttributedString` with RTFD-survivable image attachments. Two tracks: rich-text (red menu-bar dot indicator) and files-strict (cyan dot). Bridges between them when files are images. Session times out after 120 seconds of inactivity, and resets the moment any other DrPaste hotkey is used.

**Quick Copy (`⌥⌘C`) and Cut & Replace (`⌥⌘X`).** `⌥⌘C` mimics `⌘C` with audio feedback (useful when standard `⌘C` is unreliable in a weak text field). `⌥⌘X` cuts the current selection, opens HUD, and lets you paste a different history item into its place — "swap selected text for something from history".

**Type Slowly action.** Types text character-by-character with a small delay (now 0.133 s / char by default — 1.5× faster than the original 0.2 s). Useful for input fields that don't accept paste, demos, screen recordings, or accessibility workflows. Auto-cancels on any user activity (keystroke, click, app switch). Playground preview animates at the production speed so you can dial the delay against perceived cadence before triggering.

**Per-provider usage stats.** OpenAI and OpenRouter providers show today's cost / requests inline in the Settings → AI row (other providers don't have a public billing API). Silent on insufficient-scope keys.

**Two operating modes.** Full Gesture Mode (with Accessibility permission) uses a CGEventTap for the press-and-hold gesture. Limited Mode (without Accessibility) falls back to Carbon hotkeys with a key-window HUD that uses Enter to commit.

**Themes.** Default, Vivid, Soft, Ocean — four bundled palettes that reach BigHUD, MiniHUD, and the region-capture cheat sheet. Switch on the fly without a restart.

**Factory Reset.** One button in Settings → General wipes every customization (actions, hotkeys, AI provider configs, API keys, preferences) and reseeds the bundled defaults. No reinstall required.

**Standard macOS UX.** Menu bar status item with quick access to recent clipboard items, Settings, Welcome / Hotkeys reference, and About. Import / Export of configuration as JSON for backup or migration. iCloud sync placeholder ready for signed releases.

## Hotkeys

| Hotkey | Action |
|---|---|
| `⌥⌘V` | Open HUD — press-and-hold, navigate with arrow keys, release to paste |
| `⌥⌘C` | Quick Copy — like `⌘C` with audio feedback |
| `⌥⌘X` | Cut & Replace — cut current selection, browse history, paste a different item in its place |
| `⌥⌘S` | Append Copy — accumulate selections into one combined entry |
| `⌥⌘ + drag` | Region capture — drag a screen region into clipboard + HUD |
| `⌥⌘<letter>` | Custom per-action hotkey — tap for instant paste; hold `⌥⌘` after the letter to open BigHUD focused on that action |

Inside the HUD:

- `↑↓` browse history
- `←→` switch action
- `⏎` paste + close (or release `⌥⌘` in Gesture Mode)
- `⌥⌘⏎` paste + keep HUD open
- `C` (or `⌥⌘C` in Limited Mode) — Copy preview to top of history
- `S` (or `⌥⌘S` in Limited Mode) — merge focused clip into accumulator
- `⌫` delete focused item
- `⌘+` / `⌘−` / `⌘0` adjust font scale
- `Esc` cancel

Custom per-action hotkeys can be assigned in Settings — tapping them applies the action to the current clipboard and pastes immediately (a MiniHUD loading panel appears while AI calls stream their result). Holding `⌥⌘` after the letter for ~250 ms opens **BigHUD focused on that action** instead — full preview, navigation, and Gesture-Mode commit semantics, identical to opening the HUD with `⌥⌘V` and arrowing to the same action.

## Installation

DrPaste is built with Swift Package Manager. Requirements:

- macOS 13 (Ventura) or later
- Xcode Command Line Tools

```bash
git clone https://github.com/ilya000/DrPaste.git
cd DrPaste
swift build -c release
.build/release/DrPaste
```

For full Gesture Mode, grant Accessibility permission in System Settings → Privacy & Security → Accessibility after first launch.

## Configuration

Open Settings from the menu bar status item. Configure:

- **General** — HUD font size, sound feedback per cue (volume slider + per-cue toggles), Cut & Replace cursor preferences, the ⌥⌘-hold cheat-sheet toggle, configuration import / export, and Factory Reset. iCloud sync and Launch on Login placeholders for future signed releases.
- **AI** — connect cloud providers, connect local providers (Ollama, LM Studio, llama.cpp), pick a default provider via radio button. Test connection before saving — the editor will only let you Save once the test passes. OpenAI and OpenRouter providers also show today's usage cost inline.
- **Appearance** — Default / Vivid / Soft / Ocean theme picker, with live preview.
- **Content tabs** (Plain text, Rich text, URL, JSON, Table, Markdown, Code, Image, Files) — per-tab playground: pick a sample, run any action, see the result. All actions — built-in, custom AI, custom transformations — live in one unified list. Reorder via drag, rename anything, assign hotkeys, edit AI prompts, build custom transformations. Disabled actions stay visible (dimmed) so they're easy to re-enable. Type Slowly preview animates at the production typing speed.

## Architecture notes

DrPaste is a native AppKit + SwiftUI app, single SwiftPM executable, no Xcode project, no external dependencies. The clipboard layer preserves full pasteboard payloads (every UTType representation, ordered) and reconstructs them losslessly on paste. AI actions, transformations, and built-in actions all share a single `ClipboardAction` protocol; bundled built-ins are seeded into the user's config as `CustomTransformationDescriptor` / `CustomAIDescriptor` so they're as editable as anything the user creates from scratch.

The HUD is split into two entities (since 0.19.0):

- **BigHUD** — the press-and-hold surface with full history, actions, preview, accumulator.
- **MiniHUD** — a transient mini-window shown for direct-trigger AI actions, with a streaming loading state, a 90-second watchdog (detached so the main actor's busy-streaming doesn't starve the timer), and a green "Done · X.Xs" completion pill.

Honest provider routing: when a default chat provider can't run an image action, runtime soft-falls-back to the cheapest enabled image-capable provider (Gemini → OpenRouter → OpenAI → Custom). The reroute is surfaced everywhere — Action editor's provider chip + orange reroute glyph + explanation hint, HUD action chip's provider icon, Settings list's provider badge. The UI never lies about which provider actually executed.

For deeper architectural notes — three-tier action hierarchy, two-surface design principle, HUD design highlights, hotkey engine selection — see [SKILL.md](SKILL.md).

## User guide

A 16-section Russian user guide is in [HELP.md](HELP.md), covering each feature with concrete real-world scenarios, settings reference, and a troubleshooting section.

## Acknowledgements

DrPaste's design is inspired by Flycut, Maccy, Paste, and Raycast — open clipboard utilities that paved the way for keyboard-first paste UX on macOS.

Built on Apple's AppKit, SwiftUI, Core Image, Vision, ScreenCaptureKit, PDFKit, and Carbon HIToolbox.

## License

GNU GPL v3.0-or-later with attribution requirement. See [LICENSE](LICENSE).

Copyright © 2026 iLya Os.
