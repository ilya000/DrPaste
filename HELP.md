# DrPaste — User Guide

DrPaste is a clipboard manager for macOS. Clipboard history, smart actions over content, AI transformations straight from any application — all behind a single gesture: **⌥⌘V**.

Current version: **0.57.0** (alpha).

This document describes every feature in plain language, with concrete real-world scenarios. If something's unclear, send feedback via the thumbs-down button.

---

## Table of contents

1. [What it is and why](#what-it-is-and-why)
2. [Smart, context-aware actions](#smart-context-aware-actions)
3. [Installation and permissions](#installation-and-permissions)
4. [The main gesture: ⌥⌘V](#the-main-gesture-v)
5. [Two modes: Gesture vs Limited](#two-modes-gesture-vs-limited)
6. [Global hotkeys](#global-hotkeys)
7. [Inside the HUD](#inside-the-hud)
8. [Actions](#actions)
9. [Custom actions](#custom-actions)
10. [AI providers](#ai-providers)
11. [AI image actions](#ai-image-actions)
12. [Cyrillic transliteration — 14 languages](#cyrillic-transliteration--14-languages)
13. [⌥⌘S Append Copy — merging clips](#s-append-copy--merging-clips)
14. [Region Capture — screen-region screenshots](#region-capture--screen-region-screenshots)
15. [Settings](#settings)
16. [Sounds and themes](#sounds-and-themes)
17. [Tips and tricks](#tips-and-tricks)
18. [Troubleshooting](#troubleshooting)

---

## What it is and why

Stock macOS only remembers the last copied fragment. Copy something new — the old one is gone. DrPaste solves three problems with one tool:

- **Clipboard history.** Every ⌘C is saved. You can go back to what you copied half an hour ago.
- **Actions over content.** From the clipboard itself you can run a transformation: translate text to Spanish, fix typos with AI, extract a table from JSON, convert an image to a pencil sketch.
- **Gesture instead of window.** No separate application to open and scroll. Hold ⌥⌘V, see history and available actions, release to paste the result.

It's a gesture like ⌘V, just more powerful. No standalone window to remember switching to.

---

## Smart, context-aware actions

DrPaste doesn't show you everything it can do. It shows what makes sense for what you just copied.

Most clipboard tools are smart lists — they help you get *back* what you copied. DrPaste goes one step further: it reads the **content** of the clip and surfaces the actions that fit it, right where your thumb already rests.

A few everyday moments:

- Copy a block of text with **email addresses** in it → **Extract emails** is the first chip, not buried in a row of twenty.
- Paste a paragraph from a **PDF** with broken line-wraps → **Remove line breaks** and **Normalize spaces** lead the strip.
- Copy text shouting in **ALL CAPS** → **Sentence case** jumps to the top.
- Copy gibberish typed in the **wrong keyboard layout** (`Ghbdtn` instead of `Привет`) → **Fix keyboard layout** appears.
- Copy **Cyrillic** text → **Cyrillic → Latin** is offered; copy plain English and it quietly stays out of the way.
- Screenshot some **uncopyable text** → **Extract text (OCR)**, and the instant you have the text, **Clean OCR text** is already there to tidy it. The steps chain themselves.

Why it matters:

- **Less hunting.** The obvious next step is already in front of you, so the press-and-hold gesture stays instant — a few relevant chips, not a wall of options.
- **"Messy in, clean out" becomes literally true.** "I copied something messy and DrPaste knew what to do" only works because it actually understands the content, instead of offering you twenty things you *could* theoretically do.
- **You discover the depth by using it.** DrPaste ships 100+ actions. You meet the powerful ones — Decode QR, Validate JSON, Preview card — exactly the first time they're useful, instead of scrolling a giant list to find them.
- **Every chip feels intentional.** Showing irrelevant actions signals a tool that doesn't get you; showing the right ones signals one that does.

This is what separates DrPaste from a clipboard *history*. A history helps you reach back. DrPaste **understands the clip and acts on it** — that's the whole point of the name: a paste that's done its homework.

You always stay in control. Context only decides the **default** — what appears first, before you touch anything. Any action can be pinned on, switched off, reordered, or given its own `⌥⌘`-letter hotkey in **Settings → Actions**.

---

## Installation and permissions

DrPaste needs **Accessibility** access once, so it can:

- Intercept ⌥⌘V and other global hotkeys.
- Paste the action result into the active app (programmatically press ⌘V).
- Capture the selection from the active app (programmatically press ⌘C for action mode).

**How to grant:** on first launch a Welcome Window appears with a hint and an "Open System Settings → Privacy & Security → Accessibility" button. Toggle DrPaste on and restart.

Without Accessibility the app still runs, but in **Limited Mode** — no ⌥⌘V gesture, history opens through the menu bar.

**Where it lives.** A clipboard ⌘V icon appears in the system menu bar (top right). Clicking opens a status menu with a list of actions and a Settings entry.

---

## The main gesture: ⌥⌘V

**Press and hold ⌥⌘V.** A HUD appears — a wide translucent window centered on the screen with three zones:

```
┌─────────────────────────────────────────────────┐
│ DrPaste · from Safari · 2 min ago               │  ← header
├─────────────────────────────────────────────────┤
│ ▸ Translate to Spanish                          │  ← actions bar (←→)
│   Paste as is                                   │
│   Reverse text                                  │
├─────────────────────────────────────────────────┤
│ Hello world!                                    │  ← preview pane
│                                                 │
│ ¡Hola, mundo!                                   │
├─────────────────────────────────────────────────┤
│ ↑↓ hist · ←→ act · ⌫ del · S merge · C copy …   │  ← footer hints
└─────────────────────────────────────────────────┘
```

- **History.** Top — the strip of the last 500 copied fragments. Arrows ↑↓ navigate.
- **Actions.** Below history — the list of actions applicable to the focused fragment. Arrows ←→ switch.
- **Preview.** The large area below shows the result of the focused action in real time.

**Release ⌥⌘V** — the preview is pasted into the application where your cursor was before HUD opened. To cancel — press **Esc** before releasing.

That's the whole core gesture. Everything else is optional.

---

## Two modes: Gesture vs Limited

**Gesture Mode** (Full) — the main mode. Requires Accessibility. Hold ⌥⌘V → HUD appears, release → it pastes. Fast, keyboard-driven, hands never leave the keys.

**Limited Mode** — fallback. If Accessibility is off or DrPaste hasn't gotten it, the HUD opens as a regular window: tap ⌥⌘V, the HUD stays on screen, navigate with arrow keys, press **⏎** to paste or **Esc** to cancel.

Default behaviour differences:

| Action | Gesture | Limited |
|---|---|---|
| Open HUD | Hold ⌥⌘V | Tap ⌥⌘V |
| Paste | Release ⌥⌘ | ⏎ |
| Cancel | Esc before release | Esc |
| Switch action | ←→ (while ⌥⌘ held) | ←→ |
| Switch in history | ↑↓ | ↑↓ |
| Delete item | ⌫ | ⌫ |

The mode is selected automatically: AX trusted → Gesture, otherwise → Limited.

---

## Global hotkeys

These chords work **from any application**, regardless of whether the HUD is open.

### ⌥⌘V — Open BigHUD (main)

Opens the HUD with clipboard history. Described above.

### ⌥⌘C — Quick Copy

Simulates ⌘C in the frontmost application and confirms with a sound that the copy landed in the clipboard. Useful when the standard "right-click → Copy" is awkward, or ⌘C doesn't respond (happens in some weak text fields).

### ⌥⌘X — Cut & Replace

A compound operation: cuts the current selection, opens the HUD, waits for you to pick a different clip, pastes it in place. Effectively "swap the selected text for something from history".

Scenario: in an email you have "sincerely, John", you need to change the signature to "best regards, Jane". Select `sincerely, John`, press ⌥⌘X, pick the previously-copied `best regards, Jane` in the HUD, release — the text is replaced.

Settings → General has a toggle **"Cut & Replace: start cursor on second item"** — when enabled, ⌥⌘X skips the just-cut fragment in history (it's at the top), and focus lands on the next item. Useful for sequential swaps.

### ⌥⌘S — Append Copy

Accumulates multiple copies into one larger clip. **Detailed below** in its own section.

### ⌥⌘+drag — Region Capture

Hold ⌥⌘ and drag a rectangle with the mouse on screen — that area is captured as a PNG and placed in the clipboard as an image. The HUD opens focused on this screenshot. **Detailed below**.

### ⌥⌘ + <letter> — Custom action hotkeys

Any action in Settings can be assigned its own hotkey. **Direct trigger** without opening the HUD: press → action is applied to selection, result is pasted (a MiniHUD loading panel appears while AI calls stream their result). **Hold ⌥⌘ after the letter** for ~250 ms — **BigHUD opens focused on that action** with the normal preview surface, history strip, action bar, and Gesture-Mode release-to-paste. The hold-preview surface is BigHUD, not MiniHUD.

Reserved chords (which **cannot** be assigned):

- `⌥⌘V/C/X/S/⏎` — used by DrPaste itself.
- `⌥⌘Q/D/M/H/L/N/O/P/T/Space` — system macOS chords (Force Quit, Show Dock, Minimize All, etc.). The recorder refuses and tells you who owns the chord.

---

## Inside the HUD

When the HUD is open, the following keys are available:

| Key | Action |
|---|---|
| ↑↓ | Navigate history |
| ←→ | Switch action |
| ⏎ | Paste + close HUD (or just release ⌥⌘ in Gesture Mode) |
| ⌥⌘⏎ | **Paste + keep HUD open** — for a series of consecutive pastes |
| C (Gesture) or ⌥⌘C (Limited) | **Copy preview** — current preview becomes a new clip at the top of history, focus jumps to it |
| S (Gesture) or ⌥⌘S (Limited) | **Merge** — add current clip to the accumulator |
| ⌫ | Delete focused clip from history |
| Esc | Close HUD without pasting |
| ⌘+/− or +/− (Gesture) | Increase/decrease HUD font size |
| ⌘0 or 0 | Reset font |

### Paste & Keep (⌥⌘⏎)

Pastes the focused clip into the target app, but the HUD stays open. You can do another ⌥⌘⏎ — it pastes the same clip, or (if you've arrowed to a different one) the new one.

Scenario: filling out a web form, you need to paste name, email, phone number sequentially from history. ⌥⌘V → pick name → ⌥⌘⏎ → arrow down → email → ⌥⌘⏎ → arrow down → phone → ⌥⌘⏎ → Esc.

### Copy preview (C / ⌥⌘C)

"Take what I see in the preview right now and put it back in the clipboard." Useful when you've applied an action (say AI translate) and want to save the result as a separate clip in history, so you can:

- ⌥⌘V → pick that result → apply another action on top (chain transformations).
- Paste ⌘V into any application outside DrPaste.

The new clip lands **on top** of history (as if it were a regular ⌘C), HUD focus jumps to it.

### Merge (S / ⌥⌘S) — see [its own section](#s-append-copy--merging-clips).

---

## Actions

DrPaste has three types of actions:

### Built-in

Hard-wired into the code. Not fundamentally editable, but can be renamed and given a hotkey. Examples:

- **Paste as is** — paste the buffer unchanged (always first in the list).
- **Reveal in Finder** — for file clips, opens Finder at the folder.
- **Open URL** — for URL clips, opens in the default browser.
- **Image: OCR** — extracts text from an image via Apple Vision.
- **Image: Grayscale / Invert / Rotate / Strip metadata / Compress JPEG / Decode QR** — local image transformations via CoreImage.
- **Image: ASCII art** — renders an image as a monospaced ASCII block. The output is **rich text** with a monospaced 11pt font (so columns survive when pasted into Mail/Notes/Pages). Default width is **40 columns** (convenient for chat messages, code comments, Twitter/X posts). Before 0.42.0 the width was 100 and the output was plain text — the upgrade doesn't touch copies already in history, but new runs of the action use the new parameters.

### Transformations

Deterministic operations over text via configurable engines:

- **caseChange** — UPPER, lower, Title Case.
- **regexReplace** — search/replace via regular expression.
- **findReplace** — simple string replace.
- **prepend / append / wrap** — add prefix / suffix / wrap.
- **trim / collapse spaces** — whitespace normalization.
- **unicodeStyle** — Unicode pseudo-fonts (𝐛𝐨𝐥𝐝, 𝑖𝑡𝑎𝑙𝑖𝑐, 𝓢𝓬𝓻𝓲𝓹𝓽, 𝔉𝔯𝔞𝔨𝔱𝔲𝔯, 𝙼𝚘𝚗𝚘𝚜𝚙𝚊𝚌𝚎, Sᴍᴀʟʟ Cᴀᴘs, Ⓒⓘⓡⓒⓛⓔⓓ, ∀ uʍop ǝpᴉsdn, etc. — about 20 styles) for Twitter/X, Telegram, LinkedIn, Discord — anywhere Markdown is not rendered.
- **markdown styles → unicode** (`builtin.font_markdown`, added in 0.42.0) — takes plain Markdown with inline markup (`**bold**`, `*italic*`, `***bi***`, `` `code` ``, `~~strike~~`) and replaces each span with the matching Unicode pseudo-font; markup characters are stripped. Plain text between markup stays unchanged.
- **markdown → rich text** (`builtin.md_to_rich`, added in 0.42.0) — converts plain Markdown source into NSAttributedString. When pasted into Mail / Pages / Notes / Word the formatting is preserved.
- **cyrillic → latin** / **latin → cyrillic** — transliteration across **14 Cyrillic languages** with automatic language detection, `Привет → Privet`. See [its own section](#cyrillic-transliteration--14-languages).
- **lineFilter** — filter lines by regex/keyword.
- **wikiMarkup** — conversion to Wiki markup.

You can create your own: Settings → Actions → +New → Transformation.

### AI (via language model)

A free-form prompt template that runs through the selected AI provider. Uses `{input}` as a placeholder for the clipboard content. Three kinds:

- **Text → Text** — text to text. Translate, rewrite, fix, summarize, etc.
- **Text → Image** — text to image. A new image is generated based on clipboard + prompt. Example seed action: **AI: Whiteboard sketch** — turns any concept into a whiteboard-drawn illustration.
- **Image → Image** — image transformation. Seed actions: **AI: Pencil sketch**, **AI: Watercolor**, **AI: Cartoon**.

More on AI — [below](#ai-providers).

---

## Custom actions

Settings → Actions → **+New** opens the action-creation dialog.

**Mode selector** at the top — three options:

1. **Built-in** — pick an existing handler from the list and rename it. Effectively "alias on top of a built-in".
2. **Transformation** — pick an engine (caseChange, regexReplace, ...) and configure parameters. The UI changes depending on the engine.
3. **AI** — pick an operation (Text→Text, Text→Image, Image→Image), write a prompt template, choose a provider.

**Applies to:** checkboxes per semantic content type — which clips this action should show in the list for. Text, Rich text, URL, JSON, Table, Markdown, Code, Image, Files. Default for AI text-text — all text-bearing types; for Image→Image — only image.

**Hotkey:** optional, ⌥⌘+letter for direct invocation. The recorder checks for collisions (see the global-hotkey chapter).

**Test panel at the bottom** — Sample Input + Output, "Run test" button. You can verify the action's behaviour on a sample without closing the dialog.

- For AI image actions there's a drop-image hint: drag your PNG/JPG into Input, or the bundled Mandrill is used.
- For text actions, each action has a curated sample — Translate sample for AI Translate, JSON sample for JSON Pretty, etc.
- Text typed into Input is remembered per-action, so the next time the editor opens you see the same sample.
- For Type Slowly, the playground animates the output at the production typing speed so you can dial the delay against perceived cadence.

**Duplicate** — button at the bottom. Creates a copy of the current action with a "2" suffix (or "3", "4" if already taken). The clone lands **immediately after the original** in the list. A separate editor window opens for the clone; the original stays open. Useful for "I already have AI: Translate to Spanish, I want to make AI: Translate to French — duplicate and change the prompt".

**Delete** — removes a user action. Built-in actions can't be deleted, only disabled (checkbox in Settings list).

---

## AI providers

DrPaste is not tied to a single vendor. In Settings → AI you can connect multiple providers and switch the default.

Supported providers:

| Provider | Where to get a key | Type |
|---|---|---|
| **Anthropic Claude** | console.anthropic.com | Cloud, text-only |
| **OpenAI** | platform.openai.com | Cloud, text + images |
| **Google Gemini** | aistudio.google.com | Cloud, text + images (cheapest for images) |
| **Grok (xAI)** | x.ai | Cloud, text-only |
| **Mistral** | mistral.ai | Cloud, text-only |
| **DeepSeek** | platform.deepseek.com | Cloud, text-only |
| **OpenRouter** | openrouter.ai | Proxy: one key — many models, images included |
| **Together AI** | together.ai | Cloud |
| **Groq** | groq.com | Cloud, very fast |
| **Cerebras** | cerebras.ai | Cloud |
| **Cloudflare Workers AI** | dash.cloudflare.com | Cloud |
| **Ollama** | localhost:11434 | Local |
| **LM Studio** | localhost:1234 | Local |
| **llama.cpp** | localhost:8080 | Local |
| **Custom** | your own URL | OpenAI-compatible endpoint |

### Default provider

A radio button to the left of each provider in Settings → AI marks who is used by default for all AI actions that don't have an explicit provider. Change the default — all default-bound actions switch instantly.

If the default provider can't perform the required operation (e.g. default = Anthropic, action = Text→Image, and Anthropic doesn't generate images), **runtime automatically switches to the cheapest provider that can** (priority: Gemini → OpenRouter → OpenAI → Custom). Meanwhile:

- The **provider icon** in Edit Action next to "Provider:" shows the **actual executor**.
- An **orange glyph 🠷** next to the chip signals that the chosen default didn't fit and runtime rerouted.
- A **hint under the picker** explains: "Default chat provider (Anthropic) can't run image actions. Routed to Gemini."

So the UI always honestly shows who actually executed, never lies.

### Per-action override

In Edit Action you can explicitly select a provider in the Provider picker. All configured providers are always visible, but **unsupported ones are disabled** (for image actions Anthropic will be greyed-out with a "no image support" tag). You can return to the Default sentinel — it will show as "Default · <name>".

### Connection test

In Settings → AI → Edit, next to each provider, there's "Test connection". Sends a short "Reply with the single word OK." prompt and verifies that the API key is valid and the endpoint responds. A green dot to the left of the row — the last test passed; red — failed (hover for the reason); grey — never tested.

After a successful Save, a new/changed provider is auto-tested and auto-promoted to default if the system doesn't have one.

### Usage stats (OpenAI, OpenRouter only)

Under the provider name, **"Today: $0.042 · 14 reqs"** is shown — today's spend, if the provider exposes billing data:

- **OpenAI** — via `/v1/organization/costs`. Uses the regular API key (no admin scope required since 0.35.1). If your key doesn't have billing scope — the row is silently hidden (HTTP 401/403 → silent hide).
- **OpenRouter** — via `/api/v1/credits`. Computes a delta from the first-seen reading of the day.

Click the row — refresh. Tooltip says "updated 3s ago".

Anthropic, Gemini and others don't have a public usage API — no row for them.

---

## AI image actions

### Text → Image

An action that takes the buffer text + your prompt → returns a newly-generated image.

In the prompt template you can use `{input}` as a placeholder for the clipboard text. If `{input}` is absent — the clipboard text is appended to the end of the prompt.

**Seed action: AI: Whiteboard sketch.** Copy a concept (e.g. "Build → Measure → Learn cycle with three arrows"), run it → you get a PNG that looks like a whiteboard drawing. Good for slides, notes, documents.

### Image → Image

An action that takes the image from the buffer + your prompt → returns a transformed image.

**Seed actions:**

- **AI: Pencil sketch** — a portrait-style pencil drawing.
- **AI: Watercolor** — watercolor stylization.
- **AI: Cartoon** — cartoon illustration with black outline.

You can duplicate and change the prompt: "AI: Oil paint", "AI: Stained glass", "AI: Pixel art", etc. Via Duplicate in Edit Action.

### Quality directive in prompt

Seed prompts contain the line **`Quality: low`** at the end. This is a directive for OpenAI gpt-image-1 that lowers the quality tier:

- `low` — ~$0.011 for 1024×1024 (good enough for sketches).
- `medium` — ~$0.042 (OpenAI default).
- `high` — ~$0.167 (gallery-grade detail).
- `auto` — OpenAI decides.

Want pricier and higher-quality? Open Edit Action, change `Quality: low` to `Quality: high` (or delete the line entirely — it becomes medium). The parser extracts it from the prompt and sends it as an API parameter. Does NOT apply to Gemini/OpenRouter (different APIs).

### Which provider? — Cost-aware fallback

DrPaste automatically picks the cheapest image-capable provider if none is explicitly chosen:

1. **Gemini** — ~$0.039 / image (cheapest).
2. **OpenRouter** — usually cheaper than OpenAI via flux/imagen models.
3. **OpenAI** — $0.011 (low) → $0.167 (high) for gpt-image-1.
4. **Custom** — unknown cost, last resort.

If you have both Gemini and OpenAI connected — auto-select for a new image action will take Gemini. Saves 75%+ on each request.

---

## Cyrillic transliteration — 14 languages

DrPaste ships two **fully offline, deterministic** transliteration actions. No AI, no network, no API key — they run instantly on any text clip and work the same on every machine.

- **Cyrillic → Latin** — romanize Cyrillic text. The language is **detected automatically**, so you just run the action.
- **Latin → Cyrillic** — the reverse. Here you **pick the target language** in the action editor (a Latin string is ambiguous without it).

Both preserve word case: `Привет → Privet`, `ПРИВЕТ → PRIVET`.

### Supported languages

All Cyrillic-script languages with more than ~1 million speakers. Each uses its own **national / common romanization**, not a single uniform scheme — so the output looks the way speakers of that language expect.

| Language | Example | Romanized | Detected by |
|---|---|---|---|
| Russian | Привет мир | Privet mir | default (no marker) |
| Ukrainian | Привіт Київ | Pryvit Kyyiv | і ї є ґ |
| Kazakh | Қазақстан | Qazaqstan | ұ қ ғ ә |
| Serbian | Џек и Ђоко | Džek i Đoko | ћ ђ џ |
| Bulgarian | ъгъл | agal | ъ without ы/э/ё |
| Tajik | Тоҷикистон | Tojikiston | ҷ ӣ ӯ ҳ |
| Mongolian | Өнөөдөр | Önöödör | ө ү |
| Belarusian | воўк | vowk | ў |
| Kyrgyz | өзүң | özüñ | ң ө ү |
| Tatar | җәй | cäy | җ |
| Chechen | Ӏан | 'an | Ӏ (palochka) |
| Macedonian | Ѓорѓи | Gjorgji | ѓ ќ ѕ |
| Bashkir | Башҡортостан | Başqortostan | ҙ ҫ ҡ |
| Chuvash | чӑваш | chăvash | ӑ ӗ ӳ |

### How auto-detection works (Cyrillic → Latin)

The detector compares the text against each language's **full alphabet**. A language is ruled out the moment the text contains a letter its alphabet can't spell — so a word is never assigned to a language that physically couldn't write it. Among the languages that *can* spell the text, the **more widely spoken** one wins.

In practice: «Џек» contains `џ`, which does not exist in Russian, so Russian is excluded outright; the word is valid in both Serbian and Macedonian, and the more widespread Serbian is chosen. Likewise a Tatar sentence with `җ` rules out Kazakh, since Kazakh has no `җ`. Bulgarian — whose alphabet is a subset of Russian's — is the one special case: it's recognized by a hard sign `ъ` used as a vowel with no Russian-only `ы/э/ё`. If nothing distinguishes the text, it's treated as Russian.

### Latin → Cyrillic — choosing the language

Open the action in **Settings → Actions**, and pick the target from the **Language** dropdown (14 options). The reverse mapping understands digraphs (`zh → ж`, `ch → ч`, `gj → ѓ`) and the national Latin's diacritic letters (`ä → ә`, `ö → ө`, `ü → ү`, `ñ → ң`). For best results, feed it text written in that language's standard Latin — plain ASCII (`a` for both `а` and `ә`) is inherently ambiguous.

### Typical uses

- Romanize names, place names, and addresses for forms, tickets, or international documents.
- Generate URL slugs and filenames from Cyrillic titles.
- Recover Cyrillic text someone typed in Latin (or vice versa).
- Chain into a Unicode pseudo-font style (Cyrillic → Latin → `𝐁𝐨𝐥𝐝`) for social profiles.

Assign a per-action `⌥⌘`+letter hotkey to either action for one-tap transliteration of the current selection.

---

## ⌥⌘S Append Copy — merging clips

**Goal:** copy multiple fragments one after another, and get **one combined** clip in the buffer.

### Basic scenario (text)

1. Select the first piece → **⌥⌘S**. The buffer now holds what you selected. A **red dot** ● appears on the menu-bar icon — the active-session indicator.
2. Switch to another place (or another app), select the second piece → **⌥⌘S** again. Success sound. The buffer now contains both pieces separated by `\n`.
3. And so on. Each ⌥⌘S adds a new fragment.
4. ⌘V in the final app — the entire accumulated chain is pasted.

### What can be merged

DrPaste supports two **tracks** that **don't mix**:

#### Track 1: Rich-text accumulator (red dot ●)

Accepts:

- Plain text
- Rich text with formatting (bold, italic, colors, links)
- Images (embedded as inline attachments in RTFD)
- Any mixture

**Images keep their format:** pasting into Mail, Notes, Pages or TextEdit gives a full document with inline images. Pasting into Slack/Terminal/code editor drops the images (those formats don't support them); only the text remains.

#### Track 2: Files accumulator (cyan dot ●)

Accepts **files only** from Finder. Multi-select files in Finder + ⌥⌘S → URL list. Next ⌥⌘S with files again → URLs combine.

### Crossovers and conversion

DrPaste auto-bridges between the tracks **when files are images**:

- **Files track, rich/text arrived:** checks whether all files are images (PNG/JPG/HEIC/...). If yes — files convert into inline attachments, the incoming rich is appended on top. The dot flips from cyan to red. The session is now rich.
- **Rich track, file arrived:** same logic. If the file is an image, it converts to attachment and is appended to rich. The dot stays red.
- **Files + a non-image (e.g. PDF, .zip)** + something non-file → **failure sound**, accumulator state unchanged. The session lives in the previous mode, try again.
- **Rich + non-image file (PDF, .zip)** → failure sound, rich unchanged.

### Sessions and timeout

**A session lives 120 seconds** since the last ⌥⌘S. After 2 minutes of inactivity, the next ⌥⌘S = **new session**: the current buffer goes into history, the new selection becomes the seed.

The session is **immediately reset** by any of:

- ⌥⌘V — open HUD.
- ⌥⌘C — Quick Copy.
- ⌥⌘X — Cut & Replace.
- Any custom ⌥⌘+letter action hotkey.
- Region capture (⌥⌘+drag).

Idea: "I switched to a different task — the accumulator is no longer needed."

### Indicator dot color

In the menu bar (top right), on the DrPaste clipboard icon:

- **● red** — rich-text session active. The next ⌥⌘S will add to it.
- **● cyan** — files session active. The next ⌥⌘S should be on a file.
- **(no dot)** — no session. Next ⌥⌘S = new session.

Color tells you at a glance where you stand.

### ⌥⌘S inside the HUD — different semantics

Inside the HUD, ⌥⌘S (or just **S** in Gesture Mode) works differently: it accumulates clips selected **from history** into a composite preview. The anchor row is marked green; consumed rows (already merged in) are visually hidden. It supports the same rich+image behaviour.

On commit (release of ⌥⌘ or ⏎), the entire accumulated composite is pasted, not the single focused clip.

---

## Region Capture — screen-region screenshots

### Gesture

Hold **⌥⌘** in any app. The cursor turns into a crosshair. **Without releasing** ⌥⌘, press and drag with the left mouse button — a rectangle is drawn. Release the mouse — the PNG of that area is automatically captured:

- Placed into the system clipboard as PNG.
- Saved into DrPaste history.
- HUD opens focused on this screenshot, ready to paste.

Release ⌥⌘ — the screenshot is pasted into whichever app you were in before the gesture.

### Cheat sheet in the corner

While ⌥⌘ is held (even without a drag), a small keyboard hint appears in the bottom-right corner with a legend:

```
⌥⌘ + drag    capture region (highlighted)
⌥⌘V          open BigHUD
⌥⌘C          quick copy
⌥⌘X          cut & replace
⌥⌘S          append copy
⌥⌘<letter>   your custom actions (if any)
```

The cheat sheet softly "fades" when the cursor approaches it so it doesn't get in the way of selecting an area.

**You can disable it.** Settings → General → "Show keyboard cheat sheet on ⌥⌘ hold". The gesture keeps working, just without the hint.

---

## Settings

Settings opens via menu bar icon → Settings, or via ⌘, when Settings is already open.

### General

- **HUD font scale** — slider 0.7×–2.0×. Persistent font size in the HUD. Override on the fly via ⌘+/⌘− inside the HUD.
- **Cut & Replace: start cursor on second item** — described above.
- **Show keyboard cheat sheet on ⌥⌘ hold** — toggle for the corner cheat sheet.

### Sound feedback

- **Volume** — global volume.
- Per-cue toggles:
  - Copy success / failure
  - Paste success / failure
  - Append copy
  - Type Slowly tick
  - Delete from history

On toggle, a preview plays so you can hear the sample.

### Configuration

- **Export…** — saves actions, hotkeys, transformations, prompt templates as JSON. **API keys are not exported** — they're stored separately.
- **Import…** — merges into the current configuration.
- **Replace from file…** — full replacement.
- **Factory Reset** — wipes EVERYTHING (actions, hotkeys, providers, keys) and reseeds defaults. Confirmation dialog.

### AI

The list of providers with the default-radio, connection status, usage stats. **+ Add provider** button — pick a kind and configure.

ProviderEditor shows:

- Display name (editable).
- Base URL (for local / custom).
- API key (with show/hide eye button, and "A key is already saved. Leave blank to keep it." hint).
- Model — text field + chips with `suggestedModels` per kind (one-click insert).
- **Image-capability note** — explains what DrPaste does with image actions via this provider: "Image actions: supported (OpenAI gpt-image-1)" / "Image actions: not supported" / "Image actions: OpenAI wire format" (for Custom).
- **Test connection** button.
- Save + Cancel + **Delete** (with a confirmation dialog).

### Actions

The main list of actions with a content-type filter (tabs: Text, Rich text, URL, JSON, Table, Markdown, Code, Image, Files).

Each row:

- Type icon (gear for built-in, function for transformation, sparkles for AI).
- Title (rename via Edit).
- Provider badge (for AI) — provider icon, brand color, greyscale+slash if the provider doesn't fit.
- Usage line under the name (for usage-tracked AI providers).
- Hotkey indicator (if a ⌥⌘+letter is assigned).
- Edit button.
- Drag handle (two horizontal lines) — drag to reorder.
- Enabled toggle.

**+ New action** in the top-right corner. **+ Add more actions** popover — a palette of built-in actions not yet in the list.

### Appearance

- **Theme** picker — Default, Vivid, Soft, Ocean. Changes colors of HUD, MiniHUD, cheat sheet. Live preview in the picker.

---

## Sounds and themes

DrPaste plays tasteful sounds on key events: copy success/failure, paste success/failure, append, type-slowly tick, delete. All toggle-able and previewable in Settings.

Themes: 4 presets. Vivid — saturated gradients, Soft — muted, Ocean — blue palette. Change on the fly, no restart.

---

## Tips and tricks

### Chain transformations

In the HUD: pick a clip → action → result in preview → press **C** (copy preview) → new clip at the top of history with focus on it → apply another action.

Example: Russian text → AI Translate → result in Spanish → C → AI Tone polish → polished result.

### Prompt templates via `{input}`

In AI action prompts, `{input}` is substituted with clipboard text. Without it — the text is just appended to the end. Use the placeholder for control, so the model sees a clear structure.

Example Text → Image prompt:
```
Generate a minimalist black-and-white icon representing: {input}

Style: flat, vector, single-color silhouette, no text, on white background.
Quality: low
```

### Per-action hotkey hold-preview

Assign `⌥⌘T` to "AI: Translate to Spanish". Normal use: select text → ⌥⌘T → translation is pasted. But if you **hold ⌥⌘ after the letter T** for 250 ms — **BigHUD opens focused on that action** with full preview. From there you can release ⌥⌘ to commit, press Esc to cancel, ←→ to swap action, ↑↓ to pick a different clip — same as opening the HUD with ⌥⌘V and arrowing to the action.

### Region capture in Mail

⌥⌘+drag in any app → PNG in clipboard → quickly in Mail compose → ⌘V → image inline.

### Append from multiple apps

Scenario: collect the titles of three writeups into one block of text.

1. Open the first writeup, select the title → ⌥⌘S. Red dot.
2. ⌘Tab → another app → select the second title → ⌥⌘S.
3. ⌘Tab → the third → ⌥⌘S.
4. Switch to email/Notes/doc → ⌘V — three titles separated by `\n`.

### Themes for presentations

Doing a screencast about DrPaste — switch to **Vivid** or **Ocean** theme: the HUD looks more contrasty on video.

### Image test-sample placeholder

In Edit Action for image-actions, the Input pane needs a sample image so you can see what the action does without affecting your clipboard. DrPaste tries, in order: (1) a `Mandrill.png` if it's been bundled into Resources for this build (classic image-processing test image — not always present in the repo build), (2) a previously cached / user-dropped image in Application Support, (3) a stock photo from `/Library/User Pictures`, (4) an SF Symbol silhouette. Want your own — drag-and-drop an image into the Input pane. It will persist across the next openings of the editor.

---

## Troubleshooting

### Hotkeys don't fire

1. Check System Settings → Privacy & Security → Accessibility: is DrPaste enabled?
2. Restart DrPaste after toggling (once).
3. If you use Karabiner or another keyboard remapper — check it doesn't intercept ⌥⌘V.

### HUD opened but it's empty

No clips in history. Copy something with regular ⌘C — it'll appear.

### AI action returns an error

- HTTP 401 — invalid API key, double-check in Settings.
- HTTP 403 — key is valid but lacks permission for that endpoint (typical for OpenAI image without org scope).
- HTTP 429 — rate limit, wait or switch to a different provider.
- "Network: ..." — connection issue. Local providers (Ollama, LM Studio) — check the local server is running.

### Image in the append accumulator is dropped on paste

The target app doesn't support RTFD (images inside text). Test in Notes or Mail — they should work. Slack/Terminal/code editor don't support inline images by design.

### Cheat sheet is annoying

Settings → General → disable "Show keyboard cheat sheet on ⌥⌘ hold".

### Arrow keys don't work in HUD (Limited Mode)

The HUD must be the key window. Click in the HUD with the mouse to regain focus, then use arrows.

### MiniHUD got stuck after a long AI request

Clicking ✕ in the corner of MiniHUD cancels the request and closes the window. Since 0.41.0 a 90-second watchdog is built in: if the provider goes silent for 90 seconds (e.g. keep-alive pings without data chunks), MiniHUD cancels the request itself. If it hangs sooner — that's usually a network timeout; try a different provider.

### Type Slowly types too fast / too slow

Since 0.42.0 the base delay is 0.133 seconds per character (was 0.2). If you want it different — open Settings → Actions → Type Slowly → Edit; the UI parameter isn't there yet (see backlog #A16), but the Playground preview now shows the actual production speed, so you can dial it in by eye before committing.

### Append session unexpectedly started a new one instead of continuing

More than 120 seconds of inactivity passed, or you accidentally did ⌥⌘V / ⌥⌘C / ⌥⌘X / per-action hotkey between the ⌥⌘S presses. The colored dot in the menu bar tells you whether a session is active.

---

## Version and updates

The current version and changelog — in the About window (status menu → About DrPaste). Source: GitHub `ilya000/DrPaste`. A release ships a `.app` bundle; the alpha is built via `swift build` from the repository.

Feedback is welcome — describe a concrete scenario, what you expected, and what you got.
