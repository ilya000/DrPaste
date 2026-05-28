# DrPaste

A press-and-hold clipboard utility for macOS.

DrPaste is a native macOS tool designed as an extension of the system Paste gesture. Hold `⌥⌘V`, browse your clipboard history and transformations in a HUD, release to paste. No separate window to manage, no panel to dismiss — the workflow is keyboard-first and gesture-driven.

## Features

**Universal clipboard history.** Text, rich text, URLs, images, files, PDFs — preserved losslessly with original formatting and full source metadata (app, window title, timestamp).

**Press-and-hold paste gesture.** Hold `⌥⌘V`, navigate the HUD with arrow keys, release to paste. The selected entry, optionally transformed by an action, is delivered to the frontmost app's text cursor.

**Multi-provider AI.** Connect to Anthropic Claude, OpenAI, Google Gemini, xAI Grok, Mistral, DeepSeek, Ollama (local), LM Studio (local), llama.cpp (local), or any OpenAI-compatible endpoint. API keys are stored in Keychain.

**Custom AI actions.** Built-in templates for translate, summarize, fix grammar, polish prose, explain code, and more. Each action is editable — change the prompt, switch the provider, scope it to specific content types.

**Custom transformations.** Build deterministic text manipulations using regex replace, find/replace, prepend, append, wrap, or line filter engines. Configure, test, and save without touching code.

**Rich text aware.** Translate, fix grammar, or rewrite while preserving bold, italic, links, headings, lists, and inline code via Markdown round-trip. Convert rich text to Markdown, HTML, or MediaWiki markup.

**Image actions.** OCR, decode QR / barcodes, strip EXIF and GPS metadata, resize, compress, rotate, grayscale, invert — local, no network calls.

**Per-action hotkeys.** Assign any global hotkey to any action. Pressing the hotkey applies the action to the current clipboard and pastes immediately — no HUD shown. Useful for one-shot workflows like Translate or Paste as Text.

**Append Copy (`⌥⌘S`).** Accumulate multiple selections into one combined clipboard entry. Session-aware: first press starts a fresh accumulator, subsequent presses extend it. The session resets after 5 minutes of inactivity or any other DrPaste hotkey.

**Type Slowly action.** Types text character-by-character with a small delay between keys. Useful for input fields that don't accept paste, demos, screen recordings, or accessibility workflows. Auto-cancels on any user activity (keystroke, click, app switch).

**Two operating modes.** Full Gesture Mode (with Accessibility permission) uses a CGEventTap for the press-and-hold gesture. Limited Mode (without Accessibility) falls back to Carbon hotkeys with a key-window HUD that uses Enter to commit.

**Standard macOS UX.** Menu bar status item with quick access to recent clipboard items, Settings, Welcome / Hotkeys reference, and About. iCloud sync placeholder ready for signed releases.

## Hotkeys

| Hotkey | Action |
|---|---|
| `⌥⌘V` | Open HUD — press-and-hold, navigate with arrow keys, release to paste |
| `⌥⌘C` | Quick Copy — like `⌘C` with audio feedback |
| `⌥⌘X` | Cut & Replace — cut current selection, browse history, paste a different item in its place |
| `⌥⌘S` | Append Copy — accumulate selections into one combined entry |

Inside the HUD: `↑↓` browse history, `←→` switch action, `⌫` delete focused item, `⌘+` / `⌘−` / `⌘0` adjust font, `Esc` cancel, release to paste.

Custom per-action hotkeys can be assigned in Settings — pressing them applies the action to the current clipboard and pastes immediately without showing the HUD.

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

- **General** — HUD font size, sound feedback per cue (volume slider + per-cue toggles), Cut & Replace cursor preferences. iCloud sync and Launch on Login placeholders for future signed releases.
- **AI Providers** — connect cloud providers (key stored in Keychain) and local providers (Ollama, LM Studio, llama.cpp). Test connection before saving.
- **Content tabs** (Plain text, Rich text, URL, JSON, Table, Markdown, Code, Image, Files) — per-tab playground: pick a sample, run any action, see the result. Reorder actions via drag, rename built-ins, assign hotkeys, edit AI prompts, build custom transformations.
- **Import/Export** — back up your configuration. API keys are never included in exports.

## Architecture notes

DrPaste is a native AppKit + SwiftUI app, single SwiftPM executable, no Xcode project. The clipboard layer preserves full pasteboard payloads (every UTType representation, ordered) and reconstructs them losslessly on paste. AI actions, transformations, and built-in actions all share a single `ClipboardAction` protocol; user-created actions are stored as `CustomAIDescriptor` or `CustomTransformationDescriptor` in JSON and seeded on first launch.

## Acknowledgements

DrPaste's design is inspired by Flycut, Maccy, Paste, and Raycast — open clipboard utilities that paved the way for keyboard-first paste UX on macOS.

Built on Apple's AppKit, SwiftUI, Core Image, Vision, and Carbon HIToolbox.

## License

GNU GPL v3.0-or-later with attribution requirement. See [LICENSE](LICENSE).

Copyright © 2026 iLya Os.
