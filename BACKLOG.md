# DrPaste — Backlog

Active work, structured roadmap, and a condensed changelog. Historical
free-form notes were collapsed into this document; the long-form discussion
that preceded each shipped item lives in git history.

Current version: **0.57.0** (alpha). `AppBrand.version` is the live
source of truth — bump there per release. The version string in this
file's header and in `SKILL.md` / `README.md` / `HELP.md` is updated
alongside. See [SKILL.md](SKILL.md) for
the project's full architectural memory, file-by-file responsibilities,
and a "resume work from cold start" guide. See [HELP.md](HELP.md) for
the end-user feature documentation.

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

## Product strategy & monetization (planning — not yet implemented)

Strategic framing for how DrPaste will monetize without compromising the
free-and-local-first product philosophy. Captured here as the canonical
reference for future feature work that touches AI providers, plans,
billing, onboarding copy, or upgrade prompts. NOT a feature spec — no
code changes from this section.

### Decisions locked-in (revision 2)

  - **Hosted Starter pricing**: $2/month or $20/year (~17% annual
    discount, also helps cash flow). $2 was chosen over the earlier
    $1 to keep economics workable after Apple IAP's 15–30% cut and
    OpenRouter token costs.
  - **Hosted Plus pricing**: $5/month (annual variant TBD, suggested
    $50/year for consistency with Starter's discount ratio).
  - **Hosted backend = OpenRouter pass-through, not self-hosted
    inference.** DrPaste does NOT run model inference, does NOT
    maintain a multi-vendor billing matrix, does NOT host GPUs. A
    thin auth proxy (Cloudflare Worker / Vercel Edge Function-sized)
    validates the user's Apple IAP receipt, checks remaining quota,
    and forwards the request to OpenRouter using DrPaste's own
    OpenRouter API key. OpenRouter then routes to whichever
    underlying model the user's tier permits (Anthropic / OpenAI /
    Gemini / Llama / etc.). This eliminates almost all of the
    "build your own inference infra" problem; we become a thin
    billing + quota wrapper around an existing aggregator.
  - **Privacy story** flows from this architecture:
      • **Hosted users** — content goes through OpenRouter, which has
        explicit no-training / no-logging policies for its routed
        traffic. We surface OpenRouter as the named upstream so users
        can read those policies themselves; we don't make claims we
        can't back.
      • **BYO users** — content goes directly from the user's machine
        to the user's chosen provider via the user's own API key.
        DrPaste has zero visibility into the request. This is the
        cleanest possible privacy story and the one we lead with.
  - **Billing = Apple IAP.** Adapt to its rules (auto-renewable
    subscriptions, subscription groups, receipt validation).
    Implies Mac App Store distribution OR an MAS-companion build —
    needs to be confirmed whether macOS direct-download apps can
    use StoreKit outside the store (see "open questions" below).
  - **No Lifetime License.** Earlier suggestion withdrawn. Hosted
    inference has ongoing token-cost overhead; a one-time payment
    creates a permanent liability we can't price for new model
    expense curves. BYO remains free forever, which already covers
    the "I'll pay once and be done" audience by being free.
  - **Tagline stays as-is**: *"Press, hold, paste — the Paste gesture,
    extended"*. The "clipboard layer for the AI era" framing is a
    secondary marketing line, not a replacement.
  - **Ship BYO + Hosted together in v1.0.** Not phased (BYO first,
    hosted later). With OpenRouter-as-backend, hosted infra is
    small enough that it doesn't push v1.0 out by months — the
    risk of phasing was based on the old "self-hosted proxy"
    assumption, which is now rejected.

### Rejected ideas (recorded so they don't get re-proposed)

  - **Tier-split AI model quality (Starter = cheap open-source,
    Plus = frontier closed model).** Tempting because it would
    improve Starter margins and create a "tangible" upgrade
    incentive. Rejected: users have no context for "this would
    be better on the higher tier" — if the bottom tier gives
    mediocre output, they conclude *the product* is mediocre
    and churn entirely. ChatGPT-style "Free=3.5, Plus=4" works
    because GPT-4 is a famous brand the user is comparing to; a
    new product like DrPaste has zero such brand context.

    **Both tiers ship the SAME model quality**. Differentiation
    is two axes — both quota-shaped, neither quality-shaped:

      1. **Action count per day.** Starter ~200 actions/day,
         Plus ~1,000/day (exact numbers TBD after real cost
         analysis). Resets midnight. Easy to communicate.

      2. **Maximum request size in bytes.** Starter caps the
         combined prompt + input payload at ~4 KB (≈ 1,000 tokens,
         enough for normal paragraphs, emails, short snippets).
         Plus raises the cap to ~64 KB (≈ 16,000 tokens, enough
         for whole documents, code files, long articles). When
         a user on Starter pastes content larger than their cap
         and triggers an AI action, the request is REJECTED
         before being sent upstream, with a clear inline
         message: *"Request size 12,400 B exceeds Starter limit
         of 4,096 B. Upgrade to Plus for up to 65,536 B per
         request."* — actual numbers in the message, upgrade
         path obvious, no model substitution.

    Both axes preserve the principle "hosted plans monetize
    convenience, not restrictions": quota = inconvenience (you
    can wait until tomorrow); size cap = inconvenience (you can
    break the content into chunks OR upgrade). Quality is never
    touched, so the product itself is never blamed.

    Why size cap matters as a tier axis: token cost scales with
    input length. A 64 KB request at frontier-model rates is
    materially more expensive than a 4 KB one. Without a per-tier
    size cap, one Starter user pasting a long document drains as
    much budget as 20 typical Starter users put together. With
    the cap, our economics stay predictable, and the user with a
    long-document workflow has an obvious upgrade trigger.

  - **Replace OpenRouter with Cloudflare Workers AI as hosted
    backend.** Tempting because (a) we're already on Cloudflare,
    (b) it's cheaper, (c) one vendor instead of two. Rejected:
    CF Workers AI hosts only open-source models — no Claude, no
    GPT, no Gemini Pro. Frontier proprietary models are exactly
    what justify the hosted tier's price; without them, hosted
    juice loses against BYO (where the user could just connect
    their own Claude / OpenAI account). Stay on OpenRouter for
    hosted — it has access to the full frontier-model catalogue,
    including the daily-key + credit-cap pattern that simplifies
    abuse mitigation. CF Workers AI remains in the **BYO** list
    (revision 4) as a power-user option for those who specifically
    want CF's privacy posture or cheap open-source inference.

### Decisions locked-in (revision 4)

  - **Distribution = Mac App Store only.** Most-trusted channel from
    the user's perspective; gives IAP for free; handles updates +
    refunds + parental controls + family sharing automatically; one
    payment relationship (Apple) instead of two (Apple + Stripe).
    Trade-offs accepted: 15–30 % Apple commission, App Review cycles,
    sandbox restrictions.
  - **First-submission strip strategy** — risky entitlements stripped
    from 1.0 to maximise approval odds; added back via incremental
    updates after the app has standing in MAS:
      • **Defer #A11 region capture** —
        `NSScreenCaptureUsageDescription` gets the strictest
        scrutiny. Add in a post-1.0 update with a Welcome-window
        explainer screen.
      • **CGEventTap (Full Gesture Mode) deferred to 1.1.** v1.0
        ships **Carbon-only / Limited Mode**: ⌥⌘V opens the
        BigHUD as a key window, Enter / click-to-commit, no
        press-and-hold gesture. Worse UX but ships clean
        through review. The press-and-hold gesture lands in 1.1
        once we have MAS reviewer trust and can argue for the
        entitlement with a track record behind us.
      • Keep all AI provider integrations (BYO + Hosted) — pure
        network code, no sandbox concerns.
      • Update Welcome window's tagline/copy for 1.0 to reflect
        Limited-Mode-only ("Open with ⌥⌘V, pick a clip, hit
        Enter") and quietly drop the press-and-hold mention until
        1.1 brings it back.

### Hosted backend — final architecture (revision 4)

Build out as planned. Two refinements vs. revision 3:

  - **Daily OpenRouter keys** instead of hourly. User's instinct
    was right — the hourly TTL was over-cautious. Leak blast radius
    is bounded by the per-key credit cap regardless of TTL (an
    attacker can't drain more than the key's cap, however long
    they have it). Daily TTL halves Worker request volume,
    massively improves offline tolerance (user opens DrPaste once
    a day, fetches a key, works offline for the rest of the
    session), and simplifies the user-facing quota mental model:
    "200 AI actions per day on Starter, 1,000 on Plus" — resets
    every midnight, no monthly accumulation headaches.

  - **RevenueCat from day 1** for Apple IAP receipt validation
    instead of writing the Apple `verifyReceipt` code ourselves.
    Free tier up to $2.5k MTR (covers all of year 1 even with
    optimistic projections). After that, RevenueCat takes 1 % of
    revenue past the free threshold — material but not painful at
    scale. Gives us:
      • Apple receipt validation handled (saves ~30 lines of
        Worker code we'd otherwise maintain forever);
      • Subscriber dashboard out of the box;
      • Webhooks for renewal / cancellation events (lets us purge
        stale OpenRouter sub-keys when a sub lapses);
      • Cross-platform ready if we ever ship iOS / web versions.
    Trade-off — another vendor dependency. If RevenueCat goes down
    we can't issue keys for new sessions; existing daily keys
    keep working until they expire. Acceptable.

**Final architecture:**

```
DrPaste client → Apple IAP (purchase)
                ↓
                receipt
                ↓
        RevenueCat (validates Apple receipt,
                    surfaces entitlement "drpaste_plus_v1")
                ↓
                entitlement
                ↓
DrPaste client → Cloudflare Worker (~70 lines now that
                                    RevenueCat handles receipts)
                — checks RevenueCat API for active entitlement
                — checks KV: is there a current daily key for
                  this user?
                — if not, creates an OpenRouter sub-key with
                  the tier's daily credit cap (e.g. $0.20/day
                  Starter, $1.00/day Plus), stores in KV with
                  24 h TTL, returns it
                ↓
                daily OpenRouter key
                ↓
DrPaste client → OpenRouter directly with the daily key
                ↓
                AI response
```

**Worker request volume on this architecture:** ~1 request per
user per day (fresh-key fetch on app launch, key reused all day).
Cloudflare free tier 100 k requests/day = headroom for ~100 k
active paid subscribers. Effectively zero server cost until DrPaste
has tens of thousands of paid subs.

### Open questions still to resolve before v1.0

  - **OpenRouter dependency risk.** If OpenRouter goes down, raises
    prices, or changes ToS, our hosted tier is directly affected.
    Mitigation: keep the Worker's outbound abstraction generic
    (interface, not concrete `OpenRouterClient`) so we can swap
    aggregators (Replicate, Together AI, Fireworks) by editing one
    file. No client-side code knows the upstream brand.
  - **Quota model.** Per-action count or token cap? Settled on
    daily credit cap per OpenRouter sub-key for simplicity. User-
    facing copy: "200 AI actions per day on Starter, 1,000 on
    Plus". Behind the scenes it's actually a credit limit (e.g.
    $0.20/day) sized so that average actions land in the advertised
    count range. Heavy actions (long context, expensive model)
    consume more "actions" — fair behaviour, just needs honest
    Settings copy.
  - **Abuse mitigation.** One pathological user shouldn't be able
    to drain our OpenRouter balance via prompt-injection or
    automated scripting. The per-user daily-key + scoped credit
    cap structurally handles this: blast radius of any single
    compromise is at most that user's daily cap. Worker also
    rate-limits key-issuance requests per RevenueCat user ID
    (one per minute) to defeat key-rotation abuse.
  - **Annual pricing for Plus = $39/year.** Locked in. Reasoning is
    psychological rather than math-driven: $39 sits firmly in the
    "under $40" mental bracket and reads as a clear discount from
    12 × $5 = $60 (35 % off vs the monthly rate). Higher prices
    like $50 or $48 (the symmetrical 17 %-off-Starter math) test
    worse in indie SaaS A/B's — the $40 ceiling is a known
    psychological cliff. Cash flow benefit is the same (yearly
    paid upfront), churn benefit is bigger (the bigger up-front
    commitment correlates with longer retention).
  - **What happens when subscription lapses mid-day.** RevenueCat
    webhook fires `EXPIRATION` event → Worker deletes the active
    OpenRouter sub-key for that user. Client's daily key stops
    working immediately on next request; client surfaces a friendly
    "subscription expired, renew?" prompt routing back to Apple
    IAP. Never a "switch to BYO" prompt — same rule as quota
    exhaustion (strategic rule from revision 1).

---

### Core philosophy

DrPaste is a local-first clipboard operating system for the AI era.
Seven principles guide every product decision:

  1. Your clipboard belongs to you.
  2. Your AI providers belong to you.
  3. Bring Your Own AI is free forever.
  4. Paid plans exist only for convenience.
  5. No vendor lock-in.
  6. Local-first whenever possible.
  7. Advanced users should always stay in control.

DrPaste must never feel like a locked SaaS platform or an AI
subscription trap. The product should feel fast, native, keyboard-first,
developer-friendly, privacy-respecting, optional-cloud,
optional-hosted-AI. The application itself is free to install and use.

### AI usage modes

DrPaste supports two fundamentally different AI usage modes.

**1. Bring Your Own AI (free forever)** — Advanced users connect their
own AI providers. Supported: OpenAI, Anthropic Claude, Gemini,
OpenRouter, Ollama, LM Studio, llama.cpp, Mistral, DeepSeek, xAI Grok,
custom OpenAI-compatible endpoints. When using personal providers, ALL
AI features unlocked, DrPaste does not charge any fees, does not meter
usage, does not limit functionality. The user pays providers directly.
Permanently free.

Product messaging must explicitly state:
*"Bring Your Own AI — completely free forever."* and
*"DrPaste does not charge for AI features when you use your own
providers."*

This is a critical trust-building element of the product philosophy.
BYO must NOT be presented as a workaround, fallback, downgrade, or
hidden feature. It must be positioned as an advanced mode, a power-user
feature, a developer-friendly philosophy.

**2. Hosted AI plans** — For regular users who don't want to deal with
API keys, providers, billing, token limits, model selection, or
technical setup, DrPaste offers simple hosted AI subscriptions.
Messaging focuses on simplicity and convenience: *"Enable AI
instantly. No API keys required. Just works."*

### Subscription tiers (hosted AI)

**Hosted AI Starter — $1/month.** Casual / non-technical users,
lightweight AI usage. Simple AI setup, no API keys, limited AI quota,
limited clipboard size, basic AI models, smaller daily/monthly usage
caps. Aggressively token-limited, designed to stay safely profitable,
optimised for inexpensive models.

**Hosted AI Plus — $5/month.** Active users, frequent clipboard AI
workflows, professional usage. Larger AI quota, larger clipboard
processing, better AI models, more AI actions, higher usage limits,
faster processing priority. Still feels simple, non-technical,
effortless.

### Critical strategic rule

Hosted quota exhaustion must NEVER suggest switching to Bring Your Own
AI.

  - **Wrong:** *"Your quota ended. Connect your own provider."*
  - **Right:** *"Upgrade for higher AI limits."*

Bring Your Own AI is NOT part of the monetization funnel. It is a
separate product philosophy. The hosted AI plans monetize convenience
and simplicity, not restrictions.

### Marketing positioning

DrPaste must NOT market itself as *"another AI app"*, *"an AI wrapper"*,
or *"a chatbot"*. Instead: *"The clipboard layer for the AI era"* /
*"Supercharge Copy & Paste"* / *"AI-powered clipboard workflows"*.

The core user experience is: press and hold paste → preview clipboard
history → transform content instantly → release to paste. This
interaction model is the heart of the product identity.

### Product identity

DrPaste should feel magical, lightweight, native to macOS, productivity-
focused, fast enough to become muscle memory. The AI feels integrated
into the clipboard workflow itself — not like opening a website,
launching a chatbot, or switching contexts.

### UX philosophy

Advanced users want control, custom providers, local AI, unrestricted
workflows. Regular users want simplicity, instant setup, "it just
works". DrPaste must support both groups equally well without forcing
either workflow onto the other.

### Trust & transparency

The application clearly communicates: what is processed locally, what
is sent to AI providers, which provider is being used, when hosted AI
is active, when personal providers are active. Privacy-respecting
behaviour is part of the brand identity.

### Long-term strategic advantage

This model creates strong developer goodwill, trust from power users,
recurring revenue from convenience, low-friction onboarding, high
community loyalty, reduced backlash against subscriptions. The product
becomes easy for normal users, powerful for advanced users, sustainable
as a business — without compromising user freedom.

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

- **Replace `try!` in `AppStorage.dataDir` with a boot-phase fatal-UI
  panel.** Today the line force-creates `~/Library/Application
  Support/DrPaste/` and crashes the process if it can't. In the
  unsigned alpha that's defensible — there's no recovery surface
  for a user. In a signed, sandboxed MAS build the failure modes
  are richer (denied container migration, full disk during iCloud
  hydration, temporary path unavailability during sandbox
  bootstrap) and at least some are user-recoverable. Replacement:
  a tiny pre-init `NSAlert`-style panel with three buttons:
  - **"Open Application Support folder"** — Finder reveals the
    parent so the user can free disk or fix permissions.
  - **"Reset storage"** — wipes `~/Library/Application Support/DrPaste/`
    and retries directory creation.
  - **"Quit"** — graceful exit.

  Implementation note: do NOT thread `dataDir` through the codebase
  as `URL?`. The directory must exist by the time `ActionRegistry.init`
  runs. The boot-phase panel either succeeds (sets a permanent
  `URL` and continues) or terminates the process via the Quit
  button. The `try!` stays defensible *only* if the boot-phase UI
  is the recovery path; without it, sandboxed-build crashes are
  silent for the user. Surfaced by the adversarial review pass.
- **Re-enable Keychain code paths in `APIKeyStorage.swift`.** In 0.14.0
  every call to `save`, `load`, `remove` was hardwired to route through
  the plain-JSON fallback file because unsigned builds were prompting
  for the login password on every rebuild (Keychain ACL is bound to
  the code signature, which changes per build). The original Keychain
  code is preserved verbatim as block comments inside each function,
  prefixed with `/* ORIGINAL KEYCHAIN CODE — restore in #A1 ... */`.
  Restoring is mechanical: remove the comment markers, delete the
  temporary `return saveFallback(...)` / `return loadFallback(...)` /
  `return true` early returns, flip `fallbackOnly` back to reading
  `UserDefaults.standard.bool(forKey: fallbackOnlyDefaultsKey)`, and
  delete the `_ = enabled` no-op in `setFallbackOnly`.
- **Migrate JSON-file keys into Keychain on first signed launch.**
  Detect `~/Library/Application Support/DrPaste/provider-keys-fallback.json`
  at startup, prompt "Move N API keys from local file into Keychain?",
  on accept call `APIKeyStorage.save(...)` for each (which now hits
  Keychain cleanly thanks to the stable code signature), then delete
  the file. On decline, leave the file in place and keep
  `fallbackOnly` toggleable for the install.
- **Restore the Settings → AI key-storage section.** In 0.14.0
  `keyStorageSection` was hidden behind `keyStorageDisabledNotice` in
  `SettingsWindow.swift`. Restore by un-commenting the
  `keyStorageSection` line and removing `keyStorageDisabledNotice`
  along with its single call site. The toggle reactivates the moment
  `fallbackOnly`'s getter and setter touch UserDefaults again, so no
  further UI work is required.
- **Re-evaluate iCloud Keychain sync.** Decide whether
  `kSecAttrSynchronizable` should be on by default for cloud provider
  keys (depends on App Sandbox state and entitlements — see #A3).

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

### #A6 — Bidirectional drag-and-drop in HUD

**Status:** planned. Promotes the HUD from a passive picker to a real
workspace surface — content flows in from Finder / browsers / Mail and
out to folders / apps without the user ever pressing ⌘C.
**Touches:** `HudPanel` (drag destination registration), `HUD.swift`
(row drag source, drop overlay), new `ClipboardImporter.swift` for
turning dropped payloads into `ClipboardItem`s, new `ClipboardExporter.swift`
for the inverse — turning items into temp files with sensible names and
extensions, `ClipboardModel.swift` (optional `originalFileName` field
to round-trip file names across drop-in / drag-out).

**Context:** Today the only way to get content into DrPaste is to copy
it. The user mostly works inside the HUD while holding ⌥⌘V — letting
them drag a file from Finder straight onto the open HUD (and having
the HUD accept it even with the modifiers held, as a held gesture)
removes the "copy first, then open HUD" step entirely. The inverse —
dragging a clip out of the HUD into a folder — turns the HUD into a
stash drawer for files-in-flight without needing to commit anything
to the pasteboard.

**Requirements — drag IN:**

- `HudPanel.contentView` registers as a drag destination for
  `kUTTypeFileURL`, `kUTTypeImage`, `kUTTypeRTF`, `kUTTypeRichTextFormat`,
  `kUTTypeURL`, `kUTTypeText`, `kUTTypePlainText`, and the generic
  `kUTTypeData` fallback.
- Drops are accepted even when ⌥⌘ are currently held (NSDraggingDestination
  delegate methods fire regardless of held modifiers, but verify on a
  real machine — the EventTap in Gesture Mode could theoretically
  intercept the drag flag-change events; if it does, allow-list those
  events through.
- During `draggingEntered` / `draggingUpdated`, render a soft accent
  overlay on the HUD panel (rounded rect, 2 pt accent stroke, faint
  accent tint) as a "drop here" affordance. Hide on `draggingExited` /
  `performDragOperation`.
- On `performDragOperation`, classify the payload via
  `ClipboardImporter.importDrop(_:)`:
  - File URLs: read the file's UTType, build a matching ClipboardItem.
    Text files → `.text` (or `.markdown` / `.code` if classifier
    recognises the extension), images → `.image` (PNG / JPEG / HEIC /
    TIFF), PDFs → `.pdf`, anything else → `.files` with the URL
    preserved in representations.
  - Inline text drops (no file) → `.text` item.
  - Inline image drops (e.g. drag from Safari) → `.image` item with
    PNG re-encoded for storage.
  - URL drops (e.g. drag a link from the browser address bar) → `.url`
    item using the URL string as previewText.
  - Rich text drops → `.richText` item with the RTF data preserved as
    `public.rtf` representation.
- Imported item lands at index 0 (top of history) via `store.add(_:)`,
  same path as a fresh pasteboard observation. The HUD list refreshes
  and the new item becomes the focused row so the user can immediately
  apply an action.
- Preserve the source file name when dragging in a single file: add
  `originalFileName: String?` to ClipboardItem; populate it from the
  dropped URL's `lastPathComponent`. Used later by drag-out to
  round-trip the same name back into Finder.

**Failure handling — drag IN:**

- If the import fails after `performDragOperation` returns true
  (file disappeared between `draggingEntered` and the actual read,
  permission denied on the source path, corrupt image data,
  unsupported binary format, OOM on a huge payload), the importer
  returns nil and no ClipboardItem is added to the store.
- User-visible response: play the `copyFailure` sound cue once,
  remove the drop-zone overlay. No alert, no notification, no inline
  failure banner inside the HUD. The HUD stays open with the existing
  history intact so the user can try dragging something else or
  switch to copy / paste.
- Rationale: same as drag-out — convenience layer, not a primary
  flow. If a file vanishes mid-drop the user's mental model already
  expects the drop to "not work"; a modal would just add a click.
- Error is NSLog-ed (`"DrPaste: drag-in import failed: <reason>"`)
  so issues are diagnosable without disrupting the user.

**Requirements — drag OUT:**

- Each history row in the HUD is a drag source via SwiftUI's
  `.onDrag { ... }`. The closure builds an `NSItemProvider` configured
  for the appropriate UTType and a file representation that lazily
  writes a temp file on demand (so the disk write only happens if the
  user actually drops on a destination, not on every drag-attempt).
- Format selection by semantic kind:

  | Semantic | File extension | Notes |
  |---|---|---|
  | text | .txt | UTF-8, no BOM |
  | url | .webloc | Standard macOS draggable URL |
  | email | .txt | Just the address; .vcf is overkill (we don't store full contact) |
  | json | .json | Pretty-printed (2-space indent) |
  | code | .txt | Language unknown; shebang preserved when present |
  | markdown | .md | Standard |
  | table | .csv | Universal import; .tsv if source contained tabs |
  | richText | .rtf | Native macOS, opens in TextEdit / Pages / Word with formatting intact |
  | image | .png by default, .jpg when `imageFormat == "JPEG"` | Lossless default; preserve JPEG to avoid 10× size inflation |
  | pdf | .pdf | Passthrough from representations |
  | files (single) | original URL | No re-encode — Finder copies the file directly |
  | files (multiple) | original URLs | Multi-item drag, each with its own URL |
  | unknown | .bin, or .txt when previewText present | Catch-all |

- Filename rules:
  - Primary: `originalFileName` when present (round-trip from drag-in).
  - Otherwise: first 40 characters of `previewText`, sanitized — replace
    `/ \ : * ? " < > |` with `_`, collapse runs of whitespace into a
    single `_`, trim trailing `.` and `_`.
  - Fallback when previewText is empty: `<semantic>-<yyyyMMdd-HHmmss>`
    (e.g. `image-20260530-143022.png`).
  - For images carrying source-app metadata: `<sourceApp>-<timestamp>.png`.
- Temp file location: `FileManager.default.temporaryDirectory`. Files
  are written into a per-launch subfolder so the system cleans them up
  naturally; never written into the user's clipboard storage directory.

**Failure handling — drag OUT:**

- If the destination refuses the drop (write-protected folder,
  read-only volume, disk full, sandbox denial, network share lost),
  the file-promise closure completes with `(nil, false, error)` and
  the system informs the drag source that the drop failed.
- User-visible response: play the `copyFailure` sound cue once, and
  that's it. No alert, no notification banner, no inline notice, no
  follow-up prompt. The HUD stays open with the clip intact so the
  user can drop somewhere else.
- Rationale: drag-out is a convenience layer over the existing
  copy / paste flow, not a primary workflow. Modal interruption on a
  drag failure would be more disruptive than the failure itself. The
  user already has clear sensory feedback (the drag preview snaps back,
  the failure sound fires) — that's enough to tell them "try a
  different folder" without yanking their focus.
- Error is still NSLog-ed for debugging (`"DrPaste: drag-out write
  failed: <reason>"`) so issues are diagnosable without surfacing the
  detail to the user.

**Implementation notes:**

- The NSItemProvider file-representation closure runs on a background
  queue. It must be self-contained — no main-actor calls — and complete
  with `(URL, coordinated: false, nil)` on success or `(nil, false, error)`
  on failure.
- For multi-representation items (e.g. an image clip that also carries
  RTF), register multiple type identifiers on the same NSItemProvider so
  the drag destination picks the best one (e.g. Finder picks the image
  type, Mail picks RTF).
- Drag preview: SwiftUI snapshots the row view by default, which is fine.
  If row width is too wide (~260 pt) consider providing a custom
  preview via `.itemProvider { ... }` with a smaller composite icon.
- Drop overlay: a single overlay state on `HudState` (e.g.
  `@Published var isReceivingDrop: Bool`) toggled by the
  NSDraggingDestination methods, consumed by the HUD root view to
  render the overlay.

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

### #A9 — Stream AI responses token-by-token into HUD preview pane

**Status:** ✅ Shipped in 0.14.0. Entry kept for historical context;
the implementation rationale (offline-on-a-plane use case) is the
canonical record of why streaming is non-negotiable for this product.
**Touches:** `AIProvider.swift` protocol (new streaming entry point),
provider concrete classes (Anthropic / OpenAI-compatible / Gemini SSE),
`HUD.swift` (preview pane that accumulates partial tokens), `main.swift`
(refreshPreview path that consumes the AsyncSequence).
**Context:** 0.12.0 added a transparent loading panel for AI actions —
spinner + provider name + model + elapsed seconds. That tells the user
the call is alive but not what is coming back. The next step is to
stream the response: switch `AIProvider.run` to an async sequence
(`AsyncThrowingStream<String, Error>` of partial tokens), have the HUD
preview pane append tokens as they arrive, and surface the partial text
exactly like the final result would look. Result: the user sees the
translation / summary materialize live, no opaque wait.
**Why this matters for real users:** offline-tolerant workflows. People
work on planes, trains, hotel Wi-Fi, conference networks — connections
drop, slow down, and occasionally come back. Without streaming, a
flaky link means staring at a spinner for 20+ seconds and either
getting the whole answer or nothing. With streaming the user sees
content materializing token by token, and if the link cuts at 60%
they've still got 60% of the translation visible in the preview pane
to read, copy, or send to ⌥⌘Space chain. The provider-elapsed badge
already in the preview pane stays valuable as a heartbeat — combined
with visible token flow it makes the difference between "is this
hung?" and "this is working, just slow".
**Requirements:**
- Add `func stream(prompt:input:) -> AsyncThrowingStream<String, Error>`
  next to the existing `run(...)`. Default implementation: call `run`,
  emit the whole string, complete.
- Override for Anthropic (`messages` SSE), OpenAI-compatible
  (`chat/completions` SSE with `stream:true`), Gemini
  (`streamGenerateContent`). Local providers (Ollama / LM Studio /
  llama.cpp) already expose SSE — wire them up too.
- `AIAction.apply` accepts an optional progress callback; if set,
  consume the stream and emit partial `.preview(updatedItem)` outcomes.
- `refreshPreview` for AI actions consumes the stream and updates
  `hudState.outcome` on every chunk. previewToken still guards against
  stale chunks from a previously-focused action.
- Rich-text-preserving path: re-render Markdown round-trip on every
  chunk, but throttle to 5–10 Hz so reflow doesn't thrash NSTextView.
- Cancel: when previewToken bumps or HUD closes, cancel the in-flight
  URLSession data task. Provider implementations need to expose
  cancellation handles.
**Implementation notes:** URLSession's `bytes(for:)` API gives an async
byte sequence; combined with a simple SSE line parser this is ~80 lines
per provider. The Anthropic messages stream uses `event: content_block_delta`
+ `data: { delta: { text: "…" } }`. OpenAI uses `data: { choices:
[{ delta: { content: "…" } }] }`. Termination event differs per provider.

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

### #A10 — Per-action hotkey: late-binding preview when ⌥⌘ stays held

**Status:** ✅ Shipped in 0.18.0 (C1 — per-action hotkey hold-preview
wire-up). Entry kept for historical context; the rationale captures
*why* this UX is critical. Implementation details live in
ActionHotkey.swift / HotkeyEngine.swift / main.swift
`actionHotkeyDidFire(actionID:)`.

**Touches:** `ActionHotkeyManager.swift` (release detection + grace-period
timer), `HotkeyEngine.swift` (release-vs-still-holding-modifiers tracking),
`main.swift` (`hudPanel` show / preselect path that points at the just-fired
action instead of the default focused row).
**Touches:** `ActionHotkeyManager.swift` (release detection + grace-period
timer), `HotkeyEngine.swift` (release-vs-still-holding-modifiers tracking),
`main.swift` (`hudPanel` show / preselect path that points at the just-fired
action instead of the default focused row).

**Context:** Per-action hotkeys like ⌥⌘E for "Translate to English" paste
the result instantly with zero confirmation — fast, fluid, but blind. Users
occasionally want to peek before committing: "is this the right clip", "did
the AI rewrite preserve the tone", "should I chain another action before
pasting". Today they have to either swallow the result, undo in the target
app, or learn to open HUD with ⌥⌘V first and then hunt for the action — at
which point the speed advantage of per-action hotkeys is gone.

Extend the existing press-and-hold gesture so per-action hotkeys gain the
same opt-in preview behaviour as ⌥⌘V:

- Tap-and-release ⌥⌘E quickly → instant paste (current behaviour, unchanged).
- Tap E, release E, but keep ⌥⌘ held → HUD opens pre-focused on that exact
  action with the preview rendered, just like if the user had opened HUD via
  ⌥⌘V and arrowed onto the action manually.
- Once HUD is open the user can:
  - release ⌥⌘ → commit (paste the previewed result),
  - press Esc → cancel,
  - navigate to a different action with ←/→ to swap the transformation,
  - run ⌥⌘S accumulator / ⌥⌘Space chain / Backspace delete just like in any
    other HUD session.

**Requirements:**

- Detection of "hotkey letter released while modifiers still down" lives
  in `ActionHotkeyManager` (Carbon `RegisterEventHotKey` based today). The
  letter is bound as the hotkey trigger; modifier state is tracked through
  the system flags. On key-up of the letter, check whether the modifier
  flags are still asserted.
- Grace period before HUD pops, to filter out "I just lifted my whole
  hand off the keyboard" cases where the letter releases a few ms before
  the modifiers. **250 ms is the recommended default.** Short enough to
  feel responsive when the user genuinely intended to inspect; long
  enough that an ordinary release sequence (letter then modifiers, all
  within ~80–150 ms) doesn't trigger the HUD as a flash of UI.
- The action that was about to be triggered must NOT actually run during
  the grace period — schedule its execution behind the release-of-
  modifier event, not the release-of-letter event. If the user lifts the
  modifier before the 250 ms elapses, the originally-intended direct
  paste fires (current behaviour). If the modifier is still down at
  250 ms, the HUD opens with that action preselected.
- HUD show path needs a new entry point analogous to the gesture-mode
  open but with a `(focusedItem, focusedAction)` pair instead of "show
  default focused row". Reuse the existing `HudState.itemIndex` and
  `actionIndex` plumbing; only the "where to anchor on first paint"
  initialization changes.
- The preview rendering is the standard HUD preview pane — for AI
  actions this naturally inherits the streaming preview from #A9, so the
  user can watch tokens arrive while still holding ⌥⌘.
- Cancellation paths inside the HUD work the same as gesture mode (Esc,
  modifier release outside of the HUD's gesture, navigation does not
  commit). Commit = release of modifier while focus is on the desired
  action. No new sounds, no new visual chrome — reuses the existing HUD
  surface verbatim.

**Implementation notes:**

- Carbon `RegisterEventHotKey` fires only on press of the chord; modifier
  release isn't surfaced through that API. Track modifier release via the
  existing `EventTap` flag-change handler used by Full Gesture Mode for
  ⌥⌘V, or fall back to `NSEvent.addGlobalMonitorForEvents` watching
  `.flagsChanged` for the modifier-down state.
- Race to consider: while the 250 ms timer is running, the user might
  release the letter and then press a DIFFERENT hotkey letter (e.g. ⌥⌘E
  then quickly ⌥⌘R). Cleanest behaviour — cancel the pending grace timer
  the moment any other key event arrives so we don't open HUD focused on
  a stale action; let the new chord run through its own normal path.
- Stickiness with the existing modifier-held gesture mode (⌥⌘V): both
  detection paths watch the same modifier flags. The action-hotkey
  late-binding logic must run before / not conflict with the ⌥⌘V
  gesture-mode handler. Easiest gate: only arm the grace timer when an
  action hotkey was actually pressed and released within the current
  modifier-held window.
- Discoverability: this is a Tier 3 power-user feature. No new UI
  affordance — it has to feel like an extension of the existing gesture,
  not a separate feature. Three documentation touchpoints to add **at the
  same time as the implementation lands** (so the wording above is the
  canonical reference and doesn't drift):

  1. **Welcome window — Hotkeys section.** Add a hint row after the
     existing `⌥⌘V / ⌥⌘C / ⌥⌘X / ⌥⌘S` rows, before the "Your custom
     action hotkeys" subheader:

     ```
     ⌥⌘<key>  Custom action hotkeys — tap for instant paste, or keep
              ⌥⌘ held after the key to preview in HUD before pasting
     ```

     Use a generic `⌥⌘<key>` badge (not bound to any specific letter)
     and the same `hotkeyGridRow` styling as the other system hotkeys.
     The row only makes sense once `registry.config.actionHotkeys` is
     non-empty, so guard it the same way the "Your custom action
     hotkeys" subheader is guarded — appears only when the user has at
     least one per-action hotkey configured. Avoids cold-start noise
     for users who haven't discovered per-action hotkeys yet.

  2. **Settings → Actions, action row hotkey badge tooltip.** Add a
     `.help(...)` modifier on the hotkey badge that, when the action
     has a hotkey assigned, says: "Tap the hotkey for instant paste.
     Keep ⌥⌘ held after releasing the letter to preview in HUD before
     pasting." Verbatim — kept short so it fits the tooltip width.

  3. **Welcome window — Key features grid (optional).** If the
     "Per-action hotkeys" row already exists in Key features, extend
     its caption from "Per-action hotkeys — direct trigger without
     HUD" to "Per-action hotkeys — direct trigger, or hold ⌥⌘ to
     preview in HUD". Single-line, no new row needed — surfaces the
     idea on first launch without requiring the user to set a hotkey
     first to see the hint in (1). Strictly an upsell teaser, the
     real instruction lives in (1) and (2).

---

### #A11 — Screen-region capture into clipboard history via ⌥⌘ + mouse drag

**Status:** ✅ Shipped in 0.22.0 (C1 + C2 — ScreenRegionCapture + EventTap
wiring + crosshair overlay). The corner cheat sheet and ⌥⌘ hold-toggle
followed in 0.23.x / 0.24.x. Entry kept for historical context. Files:
`ScreenRegionCapture.swift`, `RegionCaptureCheatSheet.swift`.

**Touches:** new `ScreenRegionCapture.swift` (overlay window, drag-rectangle
rendering, capture API call), `HotkeyEngine.swift` (mouse-down with ⌥⌘
detection inside the EventTap session loop), `ClipboardStore`
(new `addImage(_ data: Data, sourceApp: NSRunningApplication?) -> ClipboardItem`
helper). Possibly a new entitlement / `Info.plist` key for Screen Recording
permission (#A1 will sort that out together with codesigning). macOS native equivalent is ⌘⇧⌃4 (region → clipboard),
but the native version is decoupled from DrPaste's history, source-metadata
capture, action surface, and ⌥⌘Space chain — so dropping in a DrPaste-native
trigger that lands the result directly in the HUD action pipeline is the
real value-add, not the capture itself.
**Touches:** new `ScreenRegionCapture.swift` (overlay window, drag-rectangle
rendering, capture API call), `HotkeyEngine.swift` (mouse-down with ⌥⌘
detection inside the EventTap session loop), `ClipboardStore`
(new `addImage(_ data: Data, sourceApp: NSRunningApplication?) -> ClipboardItem`
helper). Possibly a new entitlement / `Info.plist` key for Screen Recording
permission (#A1 will sort that out together with codesigning).

**Component breakdown:**

- **C1** — mouse-down detection, selection rectangle, capture pipeline,
  HUD handoff. The core gesture flow described below.
- **C2** — visual cursor feedback via crosshair overlay. After a
  250 ms grace period of bare ⌥⌘ hold (no other key, no mouse-down),
  the cursor switches to a crosshair so the user knows region-capture
  mode is armed. Described in its own subsection below.
- **C3** — multi-display polish, ScreenCaptureKit path vs.
  CGWindowListCreateImage fallback, source-app metadata extraction.

**Trigger and gesture flow (C1):**

The earlier "auto-change cursor on bare ⌥⌘ hold" idea was initially
rejected because cursor-flipping during the normal letter-hotkey flow
(where ⌥⌘ is held for ~80 ms before the letter arrives) would cause
visible UI flicker on every ⌥⌘V / ⌥⌘C / ⌥⌘X / ⌥⌘S press. **C2 below
resurrects the idea** by guarding it behind the same 250 ms grace
timer that #A10's hold-preview uses — the cursor only changes if
⌥⌘ was held alone past the grace window. Normal letter-hotkey
sequences complete inside the window and never trigger the cursor
swap. With that guard in place, the cursor feedback is purely additive
to the C1 flow described here.

- **Bare ⌥⌘ tap-and-release does nothing new** — short presses
  (< 250 ms) remain the prelude for all existing system hotkeys
  (⌥⌘V / ⌥⌘C / ⌥⌘X / ⌥⌘S and the per-action hotkeys in #A10's
  hold-to-preview path). C2's cursor swap is gated past the same
  grace window so these don't flicker.
- **Explicit entry:** mouse-down anywhere on screen *while* ⌥⌘ is held
  enters capture mode. The CGEventTap sees the `.leftMouseDown` event
  with `[.command, .option]` flags, swallows it (so the underlying app
  doesn't receive a stray click), and presents the capture overlay.
- **Drag** with mouse button still down updates the selection rectangle.
- **Release mouse** with a non-empty rectangle → capture the region,
  write it to `ClipboardStore` as a `.image` item with source-app
  metadata (no sound — the next step is what the user actually
  notices). Then **immediately open the HUD in Gesture Mode** with
  the captured image as the freshest clip and the focused row. The
  user is still holding ⌥⌘, so this is bit-for-bit the same modal
  state they'd be in had they pressed ⌥⌘V with the captured image
  already at the top of history.
- **Inside the HUD (⌥⌘ still held):** all standard Gesture Mode
  behaviour applies. Navigate to a different image action with
  ←/→ to swap the transformation, switch focused clip with ↑/↓
  if the user wants to operate on something other than the
  captured image, run ⌥⌘S accumulator / ⌥⌘Space chain / Backspace
  delete just like any other HUD session.
- **Release ⌥⌘ in HUD → paste.** The current preview (Paste-as-is
  by default for the just-captured image, or whatever transformation
  the user navigated to) commits into the frontmost app. No new
  release semantics — the gesture is a perfect overlay onto the
  existing Gesture Mode commit path.
- **Release ⌥⌘ before mouse-up (during drag)** → cancel selection,
  dismiss overlay, NO capture, NO HUD. Defensive — the user changed
  their mind mid-drag.
- **Esc during drag** → cancel as above.
- **Esc inside HUD** → standard Gesture Mode cancel (HUD closes, no
  paste). The captured image stays in history since it was already
  written to `ClipboardStore` at mouse-up.

**C2 — visual cursor feedback via crosshair overlay:**

The grace-timer pattern from #A10 generalises naturally. EventTap's
`flagsChanged` handler already detects bare ⌥⌘ press; on press start
a 250 ms grace timer. Any of the following within the window cancels
the timer and prevents the cursor swap: another keyDown, mouse-down,
or modifier release. If the timer expires with ⌥⌘ still held alone,
the cursor-overlay window is shown (described below) and the system
cursor automatically becomes a crosshair over it.

- **Cursor-only overlay** (separate from the selection overlay
  described below). Full-screen, completely transparent `NSPanel`
  at `level: .screenSaver`, `ignoresMouseEvents: false` so the
  cursor rectangle takes effect. `addCursorRect(_:cursor: .crosshair)`
  covers the entire frame. AppKit handles cursor management — no
  manual `NSCursor.hide()`, no custom-drawn cursor needed. The
  underlying screen content shows through unchanged because the
  overlay is fully transparent and has no dim layer at this stage.
- **Spawned once per display** in `NSScreen.screens`, so the cursor
  stays a crosshair as the user moves between monitors.
- **Dismissed** when (a) the user releases ⌥⌘ without mouse-down
  (capture mode disarmed, cursor returns to system arrow, no
  side effects), or (b) the user mouse-downs, at which point the
  cursor-only overlay is replaced by the dim+selection overlay
  described next.
- **Why a window-based overlay vs. `NSCursor.crosshair.set()`:**
  `NSCursor.set()` only takes effect over `NSWindow`s belonging
  to the calling app — over Safari or Finder the cursor would
  stay a system arrow. The overlay window approach is how macOS's
  own ⌘⇧4 region-capture works.
- **Optional badge** (cosmetic, defer to later iteration): a small
  "DrPaste region capture" pill near the cursor signals what mode
  the user is in. Same monospace styling as MiniHUD's elapsed
  counter. Skip until C1+C2 ship without it.

**Overlay rendering (selection — appears at mouse-down):**

- Full-screen transparent `NSPanel` (`level: .screenSaver`,
  `styleMask: .borderless`, ignores activate) covering each connected
  display. Same panel kind we use for BigHUDPanel, just sized to the
  display's full bounds. Replaces the C2 cursor-only overlay when
  the user begins dragging (mouse-down).
- Dim layer: 35 % black fill over the whole screen except the
  selection rectangle, which stays at 0 % opacity (the actual screen
  content shows through). The dim is the "you are now selecting"
  signal — distinct from the cursor-only state where the screen is
  unmodified.
- Selection rectangle stroke: 1 pt accent colour, with a thin dashed
  shadow for visibility against bright backgrounds.
- Cursor stays a crosshair (inherited from C2's `addCursorRect`,
  carried over by `addCursorRect(_:cursor: .crosshair)` on this
  panel too — no need to hide/render manually).
- Dimensions readout near the cursor: "1280×720" updating live as
  the user drags. Aligns to the size convention shown in
  macOS's native ⌘⇧4 overlay.

**Capture API:**

- ScreenCaptureKit (macOS 12.3+) preferred — Apple's modern path,
  performant, future-proof. `SCContentFilter` for the display +
  `SCStreamConfiguration` clipped to the selection rect.
- Fallback for ≤ 12.2: `CGWindowListCreateImage(rect, .optionAll,
  kCGNullWindowID, .bestResolution)` — covers everything pre-SCK.
- Either path produces a `CGImage`. Convert to PNG `Data` via
  `NSBitmapImageRep(cgImage:).representation(using: .png,
  properties: [:])` and hand it to the new
  `ClipboardStore.addImage(_:sourceApp:)`.

**Permissions:**

- macOS 10.15+ requires Screen Recording permission for any capture
  of pixels outside the app's own windows.
- First attempt triggers the system prompt. Subsequent attempts on
  denial: show an inline failure HUD (same "Limited mode" pattern as
  AX denial — a soft banner pointing at System Settings →
  Privacy & Security → Screen Recording).
- The Screen Recording permission entry needs to be requested by
  calling a capture API once at startup or first use — there's no
  "ask politely first" API like AX has. Match the AX onboarding flow
  from the Welcome window.

**Source-metadata capture:**

- At capture time, record the `NSRunningApplication` whose window was
  topmost under the selection rectangle. Best signal source is
  `NSWorkspace.shared.frontmostApplication` at capture time — close
  enough for most cases. For precision use `CGWindowListCopyWindowInfo`
  to query which window's bounds contain the centre of the selection
  rect; map back to the owning app via `kCGWindowOwnerPID`.
- Store `sourceBundleID` / `sourceAppName` on the resulting
  `ClipboardItem` so the HUD's source label shows "Captured from
  Safari" / "Captured from Pages" etc., matching the pattern used
  for normal clipboard observations.

**Chains worth showcasing in docs:**

All of these are single-gesture flows — the user holds ⌥⌘ continuously
from the initial mouse-down until the final release-to-paste. Capture,
transformation, and paste are one continuous press-and-hold session
because mouse-up rolls directly into HUD Gesture Mode without ever
giving up the modifier.

- **Region → OCR → paste text.** Hold ⌥⌘, drag a rectangle over a
  PDF / image / window with text, release mouse → HUD opens with the
  capture focused, arrow to "Extract text (OCR)", release ⌥⌘ → the
  recognised string lands in the target app. Two clicks + arrow keys
  from pixels to text, never lifting ⌥⌘.
- **Region → AI "Describe this image" → paste description.** Same
  flow with "Describe this image" instead of OCR. Useful for
  accessibility, alt-text generation, content reports.
- **Region → ASCII art → code block → Discord.** Drag, navigate to
  "ASCII art", ⌥⌘Space to promote the ASCII to a new clip, navigate
  to "Wrap in code block", release ⌥⌘ → fenced ASCII paste lands
  in the Discord text field.
- **Region → ⌥⌘S accumulator on existing clip.** Capture, then ⌥⌘S
  to anchor the captured image as the accumulator carrier, navigate
  to a previous text clip and ⌥⌘S again to fold its text in, release
  ⌥⌘ → captured image followed by the text drops into the target
  app as a multi-clip merge.

**Discoverability:**

- Welcome window — Hotkeys section, new row appears unconditionally
  (no guard needed; the feature is always available once permission
  is granted):

  ```
  ⌥⌘ + drag   Capture screen region — drag a rectangle while
              holding ⌥⌘; release the mouse to open the HUD focused
              on the capture; release ⌥⌘ to paste
  ```

  This row teaches the full single-gesture loop in one sentence —
  the user doesn't have to learn that capture is a "separate step"
  from paste, because it isn't.

- Welcome window — Key features grid, new row:

  ```
  Screen region capture — ⌥⌘-drag any rectangle, then transform and
  paste in one continuous press-and-hold (OCR, AI describe, ASCII
  art, …)
  ```

  Icon: `rectangle.dashed`, colour: blue. The "one continuous
  press-and-hold" framing matches the existing Key features wording
  for the standard paste gesture, signalling that capture is part
  of the same modal family.

**Implementation notes:**

- The EventTap handler is the right place for `.leftMouseDown` /
  `.leftMouseDragged` / `.leftMouseUp` interception. It already runs
  in headInsertEventTap mode at session level, so capture begins
  before the underlying app sees the click. Swallow these events
  (return nil) while capture is active so e.g. Pages doesn't
  interpret the drag as a text selection.
- The overlay panel must NOT take key focus — `NSApp.activate` is
  off-limits during capture, otherwise the previously-focused app
  loses focus and the capture's "Captured from <app>" metadata
  becomes stale ("Captured from DrPaste"). `NSPanel` with
  `.nonactivatingPanel` in styleMask + `isFloatingPanel = true`
  is the right configuration for both the C2 cursor-only overlay
  and the C1 selection overlay.
- Grace timer for C2 lives in the EventTap engine alongside #A10's
  `holdPreviewGracePeriod` (currently 250 ms). Reuse the same
  constant or share state if the two grace branches end up needing
  different windows in future tuning. Cancellation triggers:
  another `keyDown`, `.leftMouseDown`, or `.flagsChanged` with
  ⌥⌘ no longer asserted. The timer fires on the main queue so
  panel creation runs on the main thread.
- Multi-display: spawn one overlay panel per `NSScreen.screens`
  entry. Track the mouse across displays via the EventTap's global
  coordinates; the active selection rectangle clamps to the screen
  the mouse is currently on. Capture only the active screen's
  region (cross-display drags become single-screen captures at
  release time).
- Performance: the overlay redraws on every `.mouseMoved` event.
  Use a CAShapeLayer for the rectangle stroke and dim layer, not
  full SwiftUI redraws, to keep the overlay buttery at 120 Hz on
  ProMotion displays.
- Cancellation correctness: if the user lifts ⌥⌘ mid-drag the
  EventTap sees `.flagsChanged` with no ⌥ or ⌘ bit. Immediately
  dismiss the overlay and DO NOT capture — even if mouse is still
  down. Treat the mouse button as released for our state machine.

---

### #A12 — Unified hotkey contract: tap-vs-hold semantics for ⌥⌘C/S/X with content preview

**Status:** planned. Biggest single UX upgrade after streaming + accumulator
landed.
**Touches:** `HotkeyEngine.swift` (hold-detection for C/S/X, currently only V
has it), `MiniHUD.swift` (multi-mode content preview: text / image / files),
`main.swift` (release-vs-still-held action dispatch).
**Context:** Currently only ⌥⌘V has the dual-mode hold gesture (quick =
nothing, hold = open BigHUD). ⌥⌘C / ⌥⌘S / ⌥⌘X always trigger their action
on press, with no preview. Users want symmetric semantics: a quick chord
performs the action silently (current behaviour), a held chord shows a
small MiniHUD with the actual content that was captured / about to be
performed, and Esc cancels.
**Requirements:**
- ⌥⌘C quick → copy + sound + flash (current behaviour, unchanged).
- ⌥⌘C hold (release-grace 250 ms, same as #A10) → MiniHUD with rendered
  content preview (text excerpt, image thumbnail, file list). Release ⌥⌘
  → close MiniHUD with no extra action (item already at top of history).
  Esc → revert: pop the just-added item back off the history stack.
- ⌥⌘S quick → append (red/cyan dot, current behaviour).
- ⌥⌘S hold → MiniHUD showing the accumulated composite + a "just added"
  highlight on the latest fragment. Release → leave accumulator as-is.
  Esc → revert the latest fragment from the accumulator.
- ⌥⌘X quick → cut + replace (current behaviour).
- ⌥⌘X hold → MiniHUD showing what was cut. Release → no extra. Esc →
  revert cut (paste original back into source field — best-effort via
  saved selection range).
- ⌥⌘V hold continues to open BigHUD (current behaviour).
- Modifier transition rule: if user releases C then presses V while
  ⌥⌘ still down, **close MiniHUD first, then open BigHUD** (cleaner
  state machine). Backlog follow-up: investigate transparent in-place
  promotion MiniHUD → BigHUD once base flow is stable in users' hands.
- All MiniHUDs in hold-mode are non-draggable, decorative-only, no X
  button — gesture is the only commit / cancel surface.

**Implementation notes:**
- Reuse `MiniHUDState.attr` rendering for text+image composites.
- For files-only payload, render a vertical stack of file rows (icon +
  name) similar to Append-Copy session indicator.
- Hold-detection: extend the existing #A10-style 250 ms grace timer
  inside `HotkeyEngine.detectHold(for chord:)`.

---

### #A13 — Search inside HUD with date / source-app filter

**Status:** planned. Revisits #A7 with a different gesture.
**Touches:** `BigHUD.swift` (inline search bar above history strip),
`ClipboardModel.swift` (search index over previewText + sourceAppName +
date), `HudState.swift` (filter state).
**Context:** When history grows past 20–30 items the strip is hard to
scan. macOS Spotlight pattern: a contains-search field that shows results
inline.
**Requirements:**
- Press `F` (or `⌘F`) inside BigHUD → animated inline search bar slides in
  above history strip.
- Live filter: contains-match across `previewText`, `sourceAppName`,
  formatted `createdAt`. Case-insensitive.
- Search history is **time-history only** (does not search across content
  types / actions — those have their own surfaces).
- Empty-result state: "No matches" inline label, no sound.
- Esc clears the filter and closes the search bar without closing HUD.
- Filter persists across modifier release inside the same HUD session;
  cleared on HUD close.

---

### #A14 — Resize Images universal transformation

**Status:** ✅ Shipped. `builtin.image.resize` (universal: image / file-list / rich-embedded), small-image preview 1:1 fix in 0.57.x.
**Touches:** new `ImageResizeTransformation.swift` (or extension to
`ImageActions.swift`), `DefaultTransformationSeed.swift` (registry entry),
applicableTypes wiring on three input kinds.
**Context:** Today users have to round-trip through Preview / Pixelmator
to resize. Native action would close the loop for screenshot-and-share
workflows.
**Requirements:**
- Single transformation, applies to three input kinds:
  - `.image` (in-history image) → resize the image.
  - `.files` (list of image files) → resize all, batch.
  - `.richText` (NSAttributedString with image attachments) → resize each
    embedded image, preserve text layout.
- Param: target longer-side in pixels, default **1920**. User can edit
  in action settings.
- Resize logic: longer side scales to target, shorter side scales
  proportionally. Never enlarge — if image's longer side ≤ target, leave
  untouched.
- High-quality resampling: `NSImageInterpolation.high` /
  `CIFilter.lanczosScaleTransform` for ≥ 2× downscales.
- Output preserves format (PNG → PNG, JPEG → JPEG with quality 0.92).
- Files variant writes resized copies to temp dir with `-resized` suffix,
  promotes URL list to clipboard.

---

### #A15 — CSV → Wiki table and CSV → Rich (RTFD) table

**Status:** ✅ Shipped. `builtin.table.to_wiki` / `to_rich` (RTFD) / `to_html`.
**Touches:** `TableActions.swift` (new file or add to `TextActions.swift`),
two action seeds, `RichTextHelpers.swift` (NSTextTable builder).
**Context:** Already have CSV-passing-through actions and the wiki engine
exists for other transformations. Two outputs:
1. CSV → MediaWiki / DokuWiki table markup (text output).
2. CSV → NSTextTable RTFD (rich output, best-effort — renders perfectly in
   Mail / Notes / Pages, falls back to plain text in Slack / Notion).
**Requirements:**
- Parser handles standard CSV quoting + escaped quotes + trailing comma
  + CRLF / LF line endings.
- Wiki table: `{| class="wikitable"` header + `! col1 !! col2` row +
  `|-` separators + `| cell |` rows + `|}` footer.
- RTFD table: `NSTextTable` with `numberOfColumns` from CSV header,
  one row per CSV row, NSTextTableBlock cells, written as RTFD to pasteboard.
- Both actions accept the same input (CSV string), produce different
  semantic outputs.
- Documentation note: RTFD tables don't survive Slack / Notion paste —
  this is acceptable (user's call confirmed in design discussion).

---

### #A16 — Built-in action editor redesign: handler-picker like Transformation

**Status:** planned. UX consistency fix.
**Touches:** `BuiltinActionEditor.swift`, `ActionEditor.swift` (router),
`Actions.swift` (`upsertBuiltinHandler` symmetric helper).
**Context:** Today Built-in actions are second-class: no Duplicate, no
proper Edit dialog. They're hardwired to a fixed handler. User wants
parity with Transformation actions: open a sheet, see a dropdown of all
built-in handlers (grouped by category, current dropdown design), pick
one, save. Duplicate copies the handler + adds suffix + opens sibling
sheet.
**Requirements:**
- BuiltinActionEditor sheet shows:
  - Title field (editable).
  - Handler dropdown (categorised, current trim from
    `trimBuiltinHandlerPicker`).
  - Applicable types grid (already exists, kept).
  - Hotkey recorder (already exists, kept).
  - NO parameters — handler is fixed by category.
- Duplicate button creates a clone with handler unchanged, new title,
  inserts after original via existing `upsertBuiltinAction(_:after:)`
  pattern (mirror Transformation flow).
- Built-in handler structure stays grouped + extensible: new handlers
  migrating from Transformations (per #A19, #A20) drop into the category
  layout without manual UI changes.

---

### #A17 — Paste-as-is: text sample + file icons rendering

**Status:** planned. Small UX gap.
**Touches:** `ActionTestSamples.swift` (replace Mandrill bias for non-image
sample), `BigHUD.swift` row rendering for `.files`, `RichTextHelpers.swift`
(NSWorkspace icon → NSAttributedString attachment).
**Context:** Two issues currently:
1. The "Paste as is" action's test sample defaults to Mandrill image,
   which is misleading for plain-text use. Show a representative text
   sample instead.
2. When a `.files` clip is rendered in the HUD or pasted as rich text,
   file rows have no icon. Should show NSWorkspace icon (blue folder for
   directories, arrow overlay for symlinks).
**Requirements:**
- Action test sample for "Paste as is" → short text sample (not Mandrill).
  Mandrill stays for image-mode actions only.
- File row rendering across HUD + accumulator:
  - Regular file → `NSWorkspace.shared.icon(forFile: path)`.
  - Folder → standard blue folder icon (system).
  - Symlink → icon with arrow overlay (system already provides).
- Icon size: 16 pt in HUD row, 24 pt in accumulator preview.

---

### #A18 — Latin → Cyrillic: deterministic + AI parallel actions

**Status:** ✅ Shipped. `builtin.text.latin_to_cyrillic` (deterministic) + `ai.text.latin_to_cyrillic`.
**Touches:** new `TransliterationLatinToCyrillic.swift`,
`AIPromptTemplates.swift` (seed), `DefaultTransformationSeed.swift`.
**Context:** Have Cyrillic → Latin transliteration with variant detection.
Reverse direction is missing. Two implementations in parallel because
context-aware transliteration is genuinely AI territory but the
deterministic path is enough for 80% of cases.
**Requirements:**
- Deterministic action: parameter `target language` enum (Russian,
  Ukrainian, Bulgarian, Serbian — same set as Cyrillic → Latin).
  Default: Russian. Uses standard GOST / BGN-PCGN tables per language.
- AI action: prompt template asks the model to transliterate to Cyrillic,
  preserving proper-noun conventions and dialectal target.
- Both appear in the user's action list independently (like the existing
  trim deterministic + AI text-cleanup pairing).

---

### #A19 — Pretty Code: two parallel actions — local (deterministic) + AI

**Status:** ✅ Shipped. `builtin.code.pretty_local` (offline) + `ai.code.pretty`.
NOT merged into one.
**Touches:** new `LocalPrettyCode.swift` (deterministic
JSON/XML/HTML/CSS + simple code reformat), `AIPromptTemplates.swift`
(AI Code Formatter seed), `DefaultTransformationSeed.swift`.
**Context:** Local action gives instant offline reformatting for common
structured formats and a "good enough" code reformat (whitespace, brace
position). AI action gives quality reformatting for arbitrary code with
language auto-detection and idiomatic style — slower, online, but high
quality.
**Requirements — local (Pretty Code: Local):**
- JSON → `JSONSerialization` with `.prettyPrinted + .sortedKeys`.
- XML → `XMLDocument` with `.nodePrettyPrint`.
- HTML → simple regex-based reformat: newlines after `>`, indent by tag
  depth, collapse multi-space. Targets 90% common cases.
- CSS → simple regex: newline after `;`, indent rule body 2 spaces.
- Generic code (no language detected) → whitespace normalization only:
  collapse 3+ blank lines, trim trailing whitespace, normalize
  line-ending to LF, expand tabs to 4 spaces (parameter).
- Format auto-detect by content: leading `{`/`[` → JSON, leading `<?xml`
  → XML, leading `<!DOCTYPE`/`<html` → HTML, leading selector + `{` → CSS,
  else generic.
- Fully offline, < 50 ms for typical sizes.

**Requirements — AI (Pretty Code: AI):**
- Prompt template: "Format this code idiomatically. Detect the language.
  Preserve semantics. Use 2-space indent unless language convention
  differs. Return only formatted code, no commentary."
- `Quality: high` directive in prompt (this is one of the cases where
  quality matters).
- Works on any language the model knows.
- Slower (typical 3–8 s), requires internet.

---

### #A20 — Unit conversion: local action with metric ↔ imperial round-trip

**Status:** ✅ Shipped. Hardened extensively in 0.57.x; remaining edge cases tracked in #A83.
(immigrant from metric country grappling with imperial measurements).
**Touches:** new `UnitConversionAction.swift`,
`DefaultTransformationSeed.swift`, parser tables for each unit category.
**Context:** Selection like "6 feet 7 in" → "200.7 cm"; "200 kg" →
"441 lb"; "75 °F" → "23.9 °C". Auto-detect source system, convert to the
opposite, replace in place. Works offline.
**Requirements:**
- Categories supported in v1:
  - Length: m / cm / mm / km ↔ in / ft / yd / mi.
  - Weight: g / kg ↔ oz / lb.
  - Temperature: C ↔ F (no Kelvin per user spec).
  - Volume: L / mL ↔ fl oz / gal / qt / pt.
  - Speed: km/h ↔ mph.
  - Area: m² ↔ ft².
- Parser handles:
  - Single value: "6 ft", "200kg", "75°F", "5 km/h".
  - Compound: "6 feet 7 in", "5 ft 11", "200 lb 4 oz".
  - Implicit unit pairs: "5'11"" (feet + inches via primes).
  - Decimal + comma decimals: "5.5 kg" and "5,5 kg" both work.
- Direction param: `auto` (default — detect source system, convert to
  opposite), `to metric`, `to imperial`.
- Output precision: 1 decimal for most categories, 0 for whole-pound
  weights and whole-Fahrenheit temperatures.
- In-place replacement: walk the input string with a regex; replace
  each match with the converted equivalent in parentheses or inline
  per parameter `replace | append`.
- Default behaviour: append in parentheses → "It's 75 °F (23.9 °C)
  outside". Replace mode swaps fully: "It's 23.9 °C outside".

**Implementation notes:**
- Use SI conversion factors as the single source of truth. All
  conversions go through SI base unit (meter, kilogram, kelvin, liter,
  m/s, m²) and back, never directly between non-SI units.
- Regex-driven scanner with a unit-keyword lookup table — keep simple,
  no NL parsing.
- Currency / time / bytes deferred to v2 (live API needed for currency).

---

### #A21 — File → Image extraction (PDF first page, simple)

**Status:** ✅ Shipped. `builtin.files.extract_image` (PDF page 1 + HEIC/TIFF/BMP/GIF → PNG).
**Touches:** new `FileToImageAction.swift`, `DefaultTransformationSeed.swift`.
**Context:** A clip containing a single PDF / image-format file should
have an action that extracts the first page (PDF) or just re-encodes the
file (HEIC / RAW → PNG). Scope is intentionally narrow per user: only
first page, only simple cases.
**Requirements:**
- Input: `.files` clip with exactly one file URL.
- PDF → render page 1 via `PDFKit` at 2× scale, output as PNG.
- HEIC / HEIF → re-encode to PNG via `CIImage(contentsOf:)` +
  `NSBitmapImageRep.representation(using: .png)`.
- TIFF / BMP / GIF → same, simple format conversion.
- Output replaces clip with `.image` containing the PNG data.
- Multi-page PDFs: page 1 only (per user spec).
- Anything else (video, archives, unknown) → action disabled / inapplicable.

---

### #A22 — URL preview cards via local HTML parsing

**Status:** ✅ Shipped. `builtin.url.preview_card` (Open Graph / title / description, local fetch).
**Touches:** `URLActions.swift` (new fetch + parse), `BigHUD.swift` /
`RichTextPreviewView.swift` (card rendering).
**Context:** URL-type clips currently show as plain links. A "Preview"
action could fetch the page, extract `<title>` and `og:image`, render a
small card.
**Requirements:**
- Action applicable to `.url` clips only.
- Local HTML fetch via `URLSession` (5 s timeout).
- Parse `<title>`, `<meta property="og:title">`, `<meta property="og:image">`,
  `<meta property="og:description">` via simple regex (NSXMLParser is
  overkill for malformed HTML; regex on the head section is fine).
- Build NSAttributedString:
  - First line: og:title or `<title>`, bold.
  - Second line: og:description (truncated to 200 chars), regular.
  - Third line: original URL, link-styled.
  - If og:image present: download it, inline as attachment above title.
- Output is rich-text clip replacing the original URL (or appended,
  parameter).
- Fallback: any fetch / parse failure → leave URL clip untouched, play
  failure sound.

**Implementation notes:**
- No JS execution — single GET, parse raw HTML.
- User-Agent set to a reasonable browser string (some sites block
  curl-style UAs).
- Domain-aware enhancements (Twitter/X, GitHub, YouTube) deferred to
  later iteration.

---

### #A23 — macOS Services menu integration (right-click context menu)

**Status:** planned. Largest single inflow channel we don't yet support.
**Touches:** `Info.plist` (NSServices array), new
`DrPasteServicesProvider.swift` (NSServices handler class),
`main.swift` (`NSApp.servicesProvider`).
**Context:** macOS Services are the system-wide right-click → "Services"
submenu surface. Letting users send selected text / files into DrPaste
actions from any app's context menu is a massive discoverability boost.
**Requirements:**
- Register Services entries in `Info.plist` with `NSMessage`,
  `NSPortName`, `NSSendTypes` (`public.utf8-plain-text`, `public.file-url`,
  `public.image`), `NSReturnTypes`.
- Entries to expose (v1):
  - "Add to DrPaste history" (sendTypes: text, file, image).
  - "DrPaste: Translate to English" (sendTypes: text; reuses default
    Translate action).
  - "DrPaste: Quick Copy" (sendTypes: text/file/image — same as ⌥⌘C).
- Service handler reads pasteboard, performs the action, returns
  result (for actions that produce output) or returns nothing (for
  history-add).
- User can extend the list via Settings → Services → "Expose action
  as Service" toggle per action (deferred to v2).
- Documentation in HELP.md: how to enable / where to find them.

**Implementation notes:**
- Services entries land in `Info.plist` and require the app to be a
  proper `.app` bundle (depends on #A1).
- Service handlers are invoked on background threads; route to MainActor
  for any state mutation.

---

### #A24 — Markdown → Rich Text action

**Status:** ✅ Shipped in 0.42.0 as `builtin.md_to_rich` in
`MarkdownActions.swift`. Curated-on by default. Pastes into
Mail / Pages / Notes / Word with formatting intact. Entry kept for
historical context.
**Touches:** `MarkdownActions.swift` (MarkdownToRichTextAction),
**Touches:** new `MarkdownToRichTextAction.swift` (or extension to
`MarkdownActions.swift`), `DefaultTransformationSeed.swift`.
**Context:** Convert markdown source to rendered NSAttributedString (with
bold / italic / headings / lists / code blocks / links). Output is
RTFD-compatible so it pastes into Mail / Notes / Pages with formatting.
**Requirements:**
- Input: plain text containing markdown syntax.
- Output: NSAttributedString with proper styles, written to pasteboard as
  4 representations (RTFD / RTF / HTML / plain) per existing accumulator
  pattern.
- Renderer reuses `RichTextHelpers.attributedStringFromMarkdown(_:)` if
  it covers needed syntax; otherwise fold in `Down` or `cmark`-style
  parsing. Internal pure function — no UI.

---

### #A25 — Unicode Fancy on markdown: convert markup to unicode-styled

**Status:** ✅ Shipped in 0.42.0 as `builtin.font_markdown` (seed v6).
`UnicodeStylizer.applyMarkdown(to:)` walks the input, matches markup
tokens longest-first (`***` before `**` before `*`, same for `__` /
`_`, plus `~~strike~~` and `` ` ``), applies the matching style
span-by-span, and drops the markup characters. Entry kept for
historical context.
**Touches:** `UnicodeStyles.swift` (UnicodeFontStyle.markdownAware),
**Touches:** `UnicodeStyles.swift` (new `stylizeMarkdown(_:)` entry
point), `DefaultTransformationSeed.swift` (new seed or replace existing).
**Context:** Current Unicode Stylize applies one style to the whole
selection. Markdown-aware variant interprets `**bold**` / `*italic*` /
`__under__` / `~~strike~~` / `` `code` `` and renders each span with the
corresponding unicode pseudo-font, then strips the markup characters.
**Requirements:**
- `**bold**` → 𝐛𝐨𝐥𝐝 (sans-serif bold).
- `*italic*` → 𝑖𝑡𝑎𝑙𝑖𝑐 (sans-serif italic).
- `***bold-italic***` → bold-italic glyphs.
- `__bold__` (alt syntax) → same as `**`.
- `_italic_` (alt syntax) → same as `*`.
- `~~strike~~` → S̶t̶r̶i̶k̶e̶ (combining overline `̶` per character).
- `` `code` `` → monospace block glyphs (𝚌𝚘𝚍𝚎).
- Plain text outside markup stays unstyled.
- Markup characters fully removed from output.

---

### #A26 — ASCII art transformation: rich text + monospaced + maxWidth param

**Status:** partially shipped in 0.42.0 — rich-text output + monospaced
NSFont + 40-column default landed (`ImageToASCIIArtAction.swift`).
`render(image:outWidth:)` exposes the width parameter at the API
level. **Remaining work** before this can fully close: surface the
`maxWidth` slider in the Settings UI so users can dial it without
editing code. Needs to wait for **#A16** (Built-in editor redesign with
handler picker) — descriptor-based parameter editing infrastructure
isn't ready for hardcoded ClipboardAction subclasses yet.
**Touches (remaining):** `ImageActions.swift` exposes a `maxWidth`
input through #A16's parameter editor scaffolding.

---

### #A27 — Type Slowly preview: animated, 1.5× faster than default

**Status:** ✅ Shipped in 0.42.0. `TypeSimulator.defaultBaseDelay` =
0.133 s/char (was 0.2). `TestOutputPane.TypeSlowlyPreview` animates the
output character-by-character at the same delay as production so the
playground is bit-for-bit honest. The 0.42.1 hot-patch additionally
fixed Type Slowly via per-action hotkey committing as plain ⌘V — see
the 0.42.1 changelog entry. Entry kept for historical context.

---

### #A28 — Engine consolidation: merge prepend / append / wrap, trim / collapse

**Status:** planned. Reduces user-pickable engine count without losing
function.
**Touches:** `CustomTransformation.swift` (engine enum + handler),
`TransformationEditor.swift` (engine picker), `DefaultTransformationSeed.swift`
(seed migrations).
**Context:** Today the engine picker has separate entries for prepend,
append, wrap, trim, collapse. Logically these are subsets of more
general engines: wrap-with-fixed-strings (covers all three of
prepend/append/wrap by setting one side empty), and normalize-whitespace
(covers both trim and collapse via parameter combinations).
**Requirements:**
- Single "Wrap with text" engine with `prefix` + `suffix` parameters
  (either can be empty). Replaces prepend / append / wrap.
- Single "Normalize whitespace" engine with `trimEdges: bool` and
  `collapseRuns: bool` flags. Replaces trim / collapse.
- Migration: existing custom transformations using old engines
  auto-migrate to new engines with equivalent parameters on first
  launch (seed v8 bump).
- Parameter-less engines (e.g. uppercase / lowercase / title case) move
  back to built-in handlers — not exposed in transformation engine
  picker (they shouldn't be there since no param to vary).
- Find/Replace and Regex stay separate (genuinely different from wrap).

---

### #A29 — Color, Email, PDF, Wiki, HTML semantic kinds + applicable types

**Status:** planned. Expands the semantic-type grid for action targeting.
**Touches:** `SemanticClassifier.swift`, `ClipboardModel.swift` (`SemanticKind`
enum), `ActionEditor.swift` (applicable-types grid expansion).
**Context:** Today the applicable-types grid covers text / url / email /
files / image / richText / pdf / code / markdown / json / table. Missing:
- Color (hex / rgb / named).
- Wiki markup.
- HTML source.
- Math / coordinate / phone / date are interesting but deferred.
**Requirements:**
- Add `.color` semantic kind, detector matches `#rgb`, `#rrggbb`,
  `rgb(r,g,b)`, `hsl(h,s,l)`, CSS named colors. Color is genuinely useful
  for designers — gets immediate value via Resize / Stylize / Preview
  actions.
- Add `.wiki` for content containing `{|` table markers or `[[link]]`
  syntax. Detect first.
- Add `.html` for content with `<` `>` tag pairs > 3.
- Settings → applicable-types grid grows to include new entries.

---

### #A30 — HUD Pin button (per-session sticky stay-open)

**Status:** ✅ Shipped. `bigHUDState.isPinned` per-session sticky stay-open.
**Touches:** `BigHUD.swift` (header pin button next to ✕), `HudState.swift`
(`isPinned` flag).
**Context:** When working through multiple clips iteratively, the user
sometimes wants HUD to stay open across action runs. Pin button (toggle)
disables the auto-close on commit for the duration of the session.
**Requirements:**
- Pin button rendered in HUD header next to ✕, same size, pin icon.
- Click → toggles `isPinned`. When true: action commit does not close
  HUD, paste flow runs, then HUD stays open with the next item focused.
- Reset to false on every HUD reopen (no persistent pinning).
- Visual indicator: pinned state shows pin icon filled / accent color.

---

### #A31 — Clickable legend items

**Status:** planned. Discoverability nudge.
**Touches:** `BigHUD.swift` footer legend, `MiniHUD.swift` footer legend.
**Context:** The single-word footer legend ("↑↓ hist · ←→ act · ⌫ del ·
S merge · C copy · ⏎ paste/keep · esc close") is currently text-only.
Making each item clickable triggers the corresponding action — saves a
mouse-only user from learning the keybinds.
**Requirements:**
- Each legend chip is a button.
- Click → dispatches the corresponding action via the same path as the
  keybind.
- Hover → underline + accent color.
- Disabled state (action not applicable) → gray + no click.

---

### #A32 — Bug: Unicode fancy reverse table is wrong (𝐓𝐡𝐞 → "The bnick")

**Status:** ✅ Shipped. `UnicodeStylizer.normalize` round-trips A–Z / a–z / 0–9 and every style; covered by `UnicodeStylizerTests`.
**Touches:** `UnicodeStyles.swift` reverse lookup table.
**Context:** When pasting unicode-styled text back through the
`unicodeStyle` action's denormalize-then-restyle path, the reverse
mapping produces garbage. Likely off-by-one or wrong-base in the lookup
table.
**Requirements:**
- Audit `UnicodeStyles.reverseGlyphMap` (or equivalent name) for off-by-N
  errors.
- Test cases: `𝐀-𝐙`, `𝐚-𝐳`, `𝟎-𝟗` round-trip to ASCII.
- Test all 12 styles in both directions.
- Once fixed, Unicode Stylize's denormalize-then-restyle (#A33) becomes
  reliable.

---

### #A33 — Bug: Unicode Stylize doesn't denormalize its own outputs

**Status:** ✅ Shipped. Denormalize-then-restyle; `UnicodeStylizerTests.testStylingAlreadyStyledTextDenormalizesFirst`.
**Touches:** `UnicodeStyles.swift` (stylize entry point), seed metadata.
**Context:** Applying Unicode Stylize to already-styled text should first
strip the existing style (using the reverse table) and then apply the
new one. Today it just stacks combining marks on already-styled glyphs,
producing junk.
**Requirements:**
- Before applying new style, call `denormalize(_:)` to recover ASCII.
- Then apply the new style table on the recovered ASCII.
- This naturally falls out of #A32 being correct.

---

### #A34 — Bug: Save button broken in New Built-in action

**Status:** ✅ Resolved. The standalone `BuiltinActionEditor` was replaced by the unified `ActionEditor`; `.createNew` + `.builtin` Save is wired in `ActionEditor.save()` (enables + dismisses).
**Touches:** `BuiltinActionEditor.swift` Save action wiring.
**Context:** Creating a new Built-in action from the "+ New" palette and
hitting Save does nothing — the sheet doesn't dismiss, the action isn't
persisted. Probably stale binding from an earlier refactor.
**Requirements:**
- Debug Save closure binding in BuiltinActionEditor's "+ New" mode.
- Ensure `onSave` callback fires `registry.upsertBuiltinAction(...)`.
- Sheet dismisses on success.

---

### #A35 — Bug: Extract links / Extract headings × Rich Text input

**Status:** ✅ Resolved. `builtin.md.extract_headings` is seeded with `types: [.markdown, .richText]`; the universal `builtin.text.extract_links` handles links across types.
**Touches:** `MarkdownActions.swift` (extractLinks / extractHeadings handlers),
applicable-types metadata.
**Context:** When a `.richText` clip is input to Extract Links or Extract
Headings, the action crashes or returns empty because it expects plain
text input.
**Requirements:**
- Either: cast input to plain `.string` before processing (preserves
  applicability across rich text).
- Or: mark the actions as inapplicable for `.richText` in the
  applicable-types grid (cleaner UX).
- User preference: applicable (process the `.string` of the rich text).

---

### #A36 — Bug / audit: engine visibility inconsistency in pickers

**Status:** ✅ Resolved. Engine pickers consolidated into the single `ActionEditor`; the separate `TransformationEditor` surface no longer exists.
**Touches:** `TransformationEditor.swift` engine picker, registry pass.
**Context:** Markdown → Plain text and Extract headings engines are
visible in one engine picker dropdown but not another. Same engine,
inconsistent visibility based on which surface invokes the picker.
**Requirements:**
- Single source of truth: `CustomTransformation.userPickableEngines`.
- All UI surfaces use that list.
- Audit pass: confirm parity across Settings action editor + Playground +
  ⌥⌘E inline picker.

---

### #A37 — AX text operations for full-document context

**Status:** planned. Power feature, large scope. Deferred but recorded.
**Touches:** new `AXTextOperations.swift`, ContextDetector enhancements.
**Context:** Today AI actions see only the clipboard content. For
translation / summarization the model would do dramatically better
with surrounding context (paragraph, page, full document). Use macOS
Accessibility API to read the focused text field / web area's full
content.
**Requirements:**
- AX-read the focused text-bearing element's full string.
- Pass surrounding context as a secondary input to AI prompt (separate
  field, model sees it but knows the primary input is the clipboard
  fragment).
- Privacy: opt-in per action (checkbox in action settings: "Include
  surrounding context"); default OFF.
- Failure modes: AX denied → silently skip context, action runs with
  clipboard only.

---

### #A63 — Visual distinction: selected clip vs selected action + failure / side-effect outcome clarity

**Status:** partial. Outcome-clarity half landed organically in earlier
versions — BigHUD already shows notice blocks for `.failed`,
`.sideEffect`, and `.alternativeCommit` (Type Slowly / Type Fast).
**Remaining work** is scoped to the clip-vs-action *selection style*:
both currently use the same solid accent fill, which conflates
"object" (the clip) with "command" (the action).
**Touches:** `BigHUD.swift` action-chip styling only.
**Context:** Today the focused clip in the history strip and the
focused action in the action bar both use the same accent-color
fill style. Visually they read as "the same kind of selected" —
but they are different kinds of objects: a clip is *what will be
pasted*, an action is *what will be applied to it*. Conflating
their visual treatment costs scanability.

**Requirements (remaining):**

- **Clip selection** keeps the current solid accent fill — clips
  *are* objects, that style fits.
- **Action selection** switches to a thinner outline / underline
  treatment (accent border or accent underline, no fill). Reads as
  a *command*, not a contained object.
- Footer chip `⏎ keep / paste / cancel` stays the same wording —
  the existing outcome notices already answer "what will the commit
  do", the chip answers "which key fires the commit".

**Already done (ships in baseline, do not re-implement):**

- `.preview(item)` → no notice (preview answers).
- `.alternativeCommit(item, .typeSlowly(_, _))` / `.typeFast` →
  inline notice block above the preview.
- `.failed(original, reason, _)` → muted-red notice.
- `.sideEffect(_, _)` → blue notice with a description.

---

### #A64 — Title / description model split (data + UI)

**Status:** planned. P0 per UX review — biggest single architecture
win for action discoverability. **Depends on #A41 (import/export merge
audit + ImportReport)** for the conflict-resolution policy below.

**Adversarial-pass refinements (must follow):**

- **Built-in description overrides store a base-hash**, not just text.
  Schema: `{ text: String, baseDefaultHash: String, editedAt: Date }`.
  When the bundled `BuiltinActionMetadata.descriptions[id]` changes
  in a later release, the user's stored override is silently stale
  if we only compare strings; with a hash we detect "the default I
  was overriding has changed" and surface an editor conflict UI
  with "Keep mine / Use new default / Compare". Export / import
  preserves the hash so the same conflict surfaces on the next
  machine.
- **Never render an empty line 2** in the Settings row. Fallback
  chain: `customDescriptions[id]` → `BuiltinActionMetadata.
  descriptions[id]` → **generated descriptor summary** built from
  the engine + parameters ("Regex replace · Applies to Text, Code"
  for a CustomTransformationDescriptor; "AI via OpenAI · Prompt
  starts: …" for a CustomAIDescriptor). Only omit line 2 when even
  the generated summary returns nil.
- **No backfill into config for i18n**. Built-in default descriptions
  are read from the bundle at display time, NOT copied into
  `customDescriptions` at any point. Only user overrides land in
  config. This forecloses the trap where a later Russian-UI ship
  would find user configs holding English defaults that pre-date
  localisation.
- **Import merge policy required.** For the same action ID with a
  non-empty `customDescriptions[id]` on both sides:
  default = keep current, log as conflict in ImportReport with
  "Replace / Keep / Duplicate as new action" options. Same policy
  surface as the `customTitles` merge work in #A41.

**Touches:** `CustomTransformationDescriptor.swift` +
`CustomAIDescriptor` gain `description: String?`;
`ActionConfig` gains `customDescriptions: [String: DescriptionOverride]`
where `DescriptionOverride = { text, baseDefaultHash, editedAt }`;
`BuiltinActionEditor.swift` metadata dictionary remains
authoritative bundle-only for hardcoded built-ins (no backfill into
config); `SettingsWindow.swift` action row becomes 2-line;
`ActionEditor.swift` gains a Description field; `BigHUD.swift`
keeps showing title only.

**Context:** Today action data has only a `title` field. Built-in
actions have descriptions in a side table (`BuiltinActionMetadata.
descriptions`), but custom transformations and custom AI actions
have no description at all — the user can name an action
"Translate to Spanish" but cannot add "Uses formal register, treats
code blocks as untranslatable" anywhere persistable. Settings list
rows show only the title, which leaves no scannable answer to
"what does this disabled action actually do".

**Requirements (data) — single schema, do not deviate:**

- Add `description: String?` field directly to
  `CustomTransformationDescriptor` and `CustomAIDescriptor`.
  Decoding default = nil; old saved configs migrate cleanly (no
  version bump needed unless we want to backfill).
- Add `customDescriptions: [String: DescriptionOverride]` to
  `ActionConfig` for built-in description overrides. **Do not**
  expand `customTitles` into a multi-purpose map — keep titles
  and descriptions as separate side tables so each can evolve
  independently and Codable migrations stay narrow.
- `DescriptionOverride = { text: String, baseDefaultHash: String,
  editedAt: Date }` per the 0.50.0 adversarial-pass refinement —
  hash detects bundle-default change so a stale override surfaces
  the conflict editor.
- Built-in actions: `ActionMetadata.description(forActionID:)` looks
  up `customDescriptions[id]` first, then falls back to
  `BuiltinActionMetadata.descriptions[id]` (which itself never
  lands in config — bundle-only, per the no-backfill i18n rule).

**Requirements (UI):**

- **Settings action row** becomes 2-line:
  - Line 1 (current): icon · title · provider badge · usage · hotkey
    badge · drag handle · enabled toggle · Edit button.
  - Line 2 (new): description in secondary font, truncated to
    1 line with tail ellipsis. Empty if no description set.
- **Action editor** gains a "Description" `TextField` directly
  under Title. Same visual treatment for built-in / transformation
  / AI mode. Editable for ALL action kinds — the colleague's
  "read-only for built-in unless cloned" rule is rejected:
  consistency with custom-title behaviour wins, and a user who
  renames a built-in already proved they want to customise.
- **HUD** stays title-only. Description never paints in HUD.
- **+ Add more actions palette** uses description as the
  secondary line under each available action's title.

**Requirements (editor layout per UX review):**

- Order of fields in `ActionEditor`:
  1. Title
  2. Description (new)
  3. Enabled toggle + Applies-to grid
  4. Hotkey recorder
  5. Provider picker (AI only)
  6. Prompt template / engine parameters (mode-specific)
  7. Test panel
  8. Duplicate / Delete footer
- Visual hierarchy: bold section dividers, comfortable spacing on
  fields 1-4 (the "I just want to rename / reassign" use case),
  more dense layout on 5-7 (power-user surface).

---

### #A65 — Append Copy lightweight feedback toast

**Status:** ✅ Shipped. Append-copy toast via `ToastController` (toggle `appendToastsEnabled`).
**Touches:** new `ToastController.swift` (or extend MiniHUD),
`main.swift` `hotkeyEngineDidAppendCopy()`.
**Context:** The menu-bar dot is the primary append-session
indicator (correctly so), but a new user may not look at the menu
bar after pressing ⌥⌘S. A brief inline toast bridges the gap:
explicit confirmation of what just happened.

**Requirements:**

- Three messages (short, secondary tone):
  - First ⌥⌘S of a session → "Append started"
  - Subsequent ⌥⌘S of same session → "Appended (\(n) clips)"
  - Session ended (timeout / other hotkey) → "Append ended"
- Render as a small NSPanel toast (matching MiniHUD chrome) anchored
  near the menu-bar icon, auto-dismiss after 1.5 s.
- Settings → Sound feedback section: separate toggle "Show append
  toasts" — some users will find it noisy, default-on.

---

### #A66 — Region Capture: "Captured X×Y" toast + permission hint

**Status:** planned. UX from review.
**Touches:** `ScreenRegionCapture.swift` post-capture path,
permission-denied path.
**Context:** Today the only post-capture feedback is the captured
PNG appearing as a clip in BigHUD (which auto-opens). A short toast
with the captured dimensions ("Captured 1280×720") gives explicit
confirmation. For permission-denied case: a clear "Screen Recording
needed — open System Settings" toast instead of silent failure.

**Requirements:**

- Successful capture → 1.0 s toast: "Captured \(w)×\(h)" anchored
  near the captured area (or near menu-bar icon if the area is
  off-screen). Reuses the toast surface from #A65.
- Permission denied → modal-ish toast: "Screen Recording needed"
  + "Open System Settings" button. No silent failure.
- Source-app label inside the HUD ("Captured from Safari") stays
  unchanged — it's already useful context.

---

### #A67 — Cheat sheet line: "Tap to run · hold ⌥⌘ to preview"

**Status:** ✅ Shipped. Per-action rows read 'tap run, hold preview'; empty-state hint states the mechanic too.
**Touches:** `RegionCaptureCheatSheet.swift` legend, Welcome
window per-action hotkeys section, Hotkey Recorder helper text.
**Context:** Per-action hotkey "tap = direct, hold = BigHUD preview"
semantics are explained in HELP.md but nowhere in-product near the
recorder itself. A single-line hint at the bottom of the recorder
+ a line in the cheat sheet closes the discovery gap.

**Requirements:**

- `HotkeyRecorder` view gains a static footer line under the
  recording field: "Tap to run · hold ⌥⌘ to preview"
- `RegionCaptureCheatSheet` per-action chord legend rows gain a
  ` — tap run, hold preview` suffix:
  `⌥⌘T  Translate to Spanish  — tap run, hold preview`
- Welcome window per-action hotkeys section already explains this;
  no change needed there.

---

### #A68 — Theme picker preview shows mini-HUD, not abstract swatches

**Status:** ✅ Already shipped. `ThemeThumbnail` already exists in
`AppTheme.swift` and is consumed by the Settings Appearance tab —
verified during cleanup pass. The original concern (abstract swatches)
no longer applies. Entry kept for historical context; if a future
"even more realistic BigHUD-shaped thumbnail" is desired (real action
chips, footer chip, actual history rows instead of stripes), file a
fresh narrower entry.

---

### #A69 — MiniHUD explicit failure state

**Status:** planned. UX from review. Currently MiniHUD plays the
`pasteFailure` sound and closes without showing *what* went wrong.
**Touches:** `MiniHUD.swift` view, `main.swift` failure-completion
path in `actionHotkeyDidFire`.
**Context:** Direct-trigger AI / image failures currently disappear
silently after the sound. The user doesn't know whether the network
failed, the model rejected, the key is bad, the source was too
large. They have to repeat the action, possibly in BigHUD, to see
the failure reason.

**Requirements:**

- MiniHUD gains a `.failure(reason: String, recovery: RecoveryHint?)`
  state alongside `.loading` / `.complete`.
- Failure state shows: ✕ icon (red), action title, one-line reason
  ("Network error", "Image too large for OpenAI (>4 MB)",
  "Provider key unauthorized — check Settings"), and an optional
  recovery button (e.g. "Open Settings", "Resize and retry" once
  #A55 lands).
- Auto-dismiss timer: 4 s for failure (longer than success 0.6 s
  Done pill), or user clicks the ✕.
- The same failure surface is used by the BigHUD's commitOutcome
  failed path, eventually — pair with #A39 PasteCommitter work.

---

### #A59 — Discoverability hint: "hold to browse · release to paste"

**Status:** planned. UX. The central gesture of the product
(release-to-paste in Gesture Mode) is not surfaced anywhere visible
inside the BigHUD itself. Welcome window covers first-launch, but
after a few days the user is relying on memory. New users who
re-discover the app months later have no in-HUD reminder.
**Touches:** `BigHUD.swift` header row, possibly a one-time
fade-out inline tip.

**Context:** Footer hints were intentionally kept terse to avoid
wrapping (`↑↓ hist · ←→ act · …`); the comment in `footer` explicitly
notes that "release pastes" was removed for width reasons. But the
removal leaves the most important affordance invisible. The other
modes ARE surfaced: Limited Mode shows a banner; per-action hotkey
hold-preview is described in Welcome. Only the core ⌥⌘V release
gesture is undocumented in-HUD.

**Requirements:**

- In Gesture Mode only, surface a small inline hint above the
  history strip or in the header sub-line: "hold ⌥⌘V to browse ·
  release to paste · esc to cancel". Single line, secondary
  foreground, monospaced 10pt so it doesn't compete with content.
- **State schema for the auto-fade counter** (per adversarial pass —
  a naive "N successful commits" counter goes wrong on Factory Reset,
  fresh-install-on-second-machine, and year-old users):

  ```
  struct HintState: Codable {
      var successfulCommits: Int           // total, monotonic
      var lastShownVersion: String         // AppBrand.version on last paint
      var lastCommitDate: Date             // for staleness detection
      var resetGeneration: Int             // bumped by Factory Reset
  }
  ```

  Stored under `drpaste.hint.releaseToPaste`. Default: show until
  `successfulCommits` ≥ 5 within the current `resetGeneration`.

- **Re-education rules** (also adversarial-pass-driven):
  - Factory Reset → `resetGeneration += 1`, counter starts over.
    Same user re-learns from a clean state.
  - Fresh install on a second machine → UserDefaults doesn't sync
    by default, so the counter starts at zero anyway.
  - **Staleness window**: if `lastCommitDate < now − 90 days`,
    show the hint exactly once on the next HUD open even if the
    counter is past threshold. Captures the "year-old user reopens
    the app" case. Sets `lastCommitDate = now` on display so it
    doesn't fire again unless another 90-day gap occurs.
- Settings → General → "Show release-to-paste hint" toggle to
  re-enable for users who want it permanent.
- Hint NEVER appears in Limited Mode (it's wrong for that mode and
  the Limited banner already covers the topic).

---

### #A60 — Append session indicator tooltip + Settings explanation

**Status:** planned. Small UX gap.
**Touches:** `main.swift` (status item NSView + tooltip),
`SettingsWindow.swift` (Sound feedback section already exists; add
indicator explanation row).

**Context:** The colored dot on the menu-bar icon (red = rich-text
accumulator, cyan = files-strict accumulator) is silently informative.
A user who hasn't read HELP.md just sees "a colored dot appeared on
the icon" with no in-product explanation. Tooltip + a "How it works"
row in Settings would close this loop.

**Requirements:**

- `NSStatusItem.button.toolTip` updated dynamically:
  - No active session → "DrPaste — clipboard history" (current).
  - Rich session active → "Append Copy: rich-text accumulator
    active (red). Press ⌥⌘S to add more, ⌥⌘V to paste."
  - Files session active → "Append Copy: files accumulator active
    (cyan). Drag/select more files and press ⌥⌘S."
- Settings → General → new "Append Copy" section with a one-paragraph
  explanation of red vs cyan dot + the timeout (120 s).
- Optional: clicking the colored dot opens HELP.md anchored at the
  Append Copy section (depends on #240 User Guide menu item).

---

### #A61 — Empty-history HUD onboarding

**Status:** planned. UX polish.
**Touches:** `BigHUD.swift` history strip empty state.

**Context:** Pressing ⌥⌘V on first launch (or after Factory Reset)
opens the HUD against an empty history. Unclear what the current
empty state looks like, but the right behaviour is a Welcome-like
inline panel: "Your clipboard history is empty. Copy something with
⌘C and try again." with a small ⌘C key chip and a "What is DrPaste?"
link to Welcome / HELP.md.

**Requirements:**

- Detect `store.items.isEmpty` → render onboarding panel instead of
  the (empty) history strip.
- Keep the action bar still hidden (no actions apply to nothing).
- Keep release/esc semantics the same — releasing on empty just
  closes the HUD with no failure sound.
- Add the same panel after Factory Reset until the first new clip.

---

### #A62 — Assign-hotkey shortcut from HUD action chip

**Status:** planned. Discoverability. Power-user feature, but it has
no current discovery path inside the HUD.
**Touches:** `BigHUD.swift` action chip context menu / long-press,
`ActionHotkeyManager.swift`.

**Context:** Today the only way to assign ⌥⌘<letter> to an action is
Settings → Actions → Edit → Hotkey recorder. Five clicks deep, and
the user has to leave their press-and-hold gesture to do it. A user
who keeps reaching for Translate to Spanish has no in-HUD signal
"hey, you can put this on a hotkey." Two affordances would close
this:

**Requirements:**

- Right-click (or long-press) on an action chip in the HUD → context
  menu with:
  - "Assign hotkey…" → opens an inline recorder anchored to the
    chip, captures the next ⌥⌘<letter>, saves through
    `setHotkey(_:for:)`.
  - "Open in Settings…" → opens Settings → action editor for this
    action (existing behaviour).
- Hotkey recording uses the same conflict / reserved-chord rules
  as the Settings recorder (auto-steal + system-chord block).
- After a hotkey is bound, the chip grows a small ⌥⌘<letter> badge
  inline, the same badge that appears in the Settings row.
- Optional second affordance: usage telemetry (local-only) tracks
  which actions a user runs more than 5 times via HUD without a
  hotkey, and surfaces a one-time "Want to put Translate on ⌥⌘T?"
  prompt. Defer this — needs careful tuning to not be naggy.

---

### #A46 — Persistence I/O: debounce + off-main + image cache

**Status:** planned. Performance. Targets perceivable HUD/Settings
lag on large clips and on slow disks (Dropbox-resident
Application Support, iCloud-hydrated files).
**Touches:** `ActionConfig` didSet save, `ClipboardStore.save`,
`BigHUD.swift` image preview load, `Settings*` blob reads.

**Requirements:**

- **Config save debounce.** `actions.json` is rewritten on every
  `config` didSet. Coalesce writes via a 200 ms debounce; flush
  immediately on `applicationWillTerminate` and Factory Reset.
- **ClipboardStore.save debounce.** Same pattern for `index.json` —
  rapid copy bursts trigger a flush after the last one settles, not
  per copy. Immediate flush on remove/clear.
- **BigHUD image preview cache.** `NSCache<NSString, NSImage>`
  keyed by blob rel. Bounded total cost; thumbnail loads stay on
  main but full-size loads go through `Task.detached`.
- **APIKeyStorage fallback file I/O off main.** Reads on launch are
  fine; writes from "Save key" flow should not block the editor.

---

### #A47 — Image rendering: drop `lockFocus`, prefer CGContext / CIImage

**Status:** planned. Reliability + perf.
**Touches:** `ImageActions.swift`, `AppendAccumulator.swift`,
`ClipboardModel.swift`, `ActionTestSamples.swift`.
**Context:** `NSImage.lockFocus()` is the old AppKit path: main-thread,
backing-scale-fragile, less predictable for resize / colour-space
operations. Switching to CGContext / CIImage gives deterministic
output + thread-safety.

**Requirements:**

- New shared helper `ImageRenderer.downscale(_:maxSide:)` returning
  PNG `Data`, no `lockFocus`. Uses CGContext at integer pixel sizes
  with Lanczos interpolation.
- All four call sites migrate to the helper.
- Output size + colour-space deterministic across light/dark mode and
  Retina/non-Retina.

---

### #A48 — Image actions: load *original* representation, not preview

**Status:** planned. Correctness. Image transformations (Grayscale,
Rotate, AI Watercolor) may currently operate on the cached preview
thumbnail rather than the raw `public.png` / `public.jpeg` /
`public.tiff` / `public.heic` representation when both are stored.
**Touches:** `ImageActions.swift` `loadImage`, `AIImageActions.swift`
loading helpers, `ClipboardModel.swift` representation lookup.

**Requirements:**

- Split into two helpers:
  - `loadOriginalImage(_ item:)` — prefer `representations["public.png"]
    / .jpeg / .tiff / .heic` over `previewImageRel`.
  - `loadPreviewImage(_ item:)` — prefer `previewImageRel` (small,
    fast for HUD chrome).
- Image actions call `loadOriginalImage`; HUD chrome calls
  `loadPreviewImage`.
- Regression test in #A45 against a clip that has both representations:
  action output dimensions match the original, not the thumbnail.

---

### #A49 — `withWatchdog(timeout:)` helper

**Status:** planned. Refactor. The 90 s detached-task watchdog pattern
exists in two places (BigHUD AI streaming, direct-trigger AI). Code
+ comments are duplicated.
**Touches:** new helper in `Concurrency+Util.swift` (or similar);
`main.swift` call sites.

**Requirements:**

- Generic helper:

  ```swift
  func withWatchdog<R>(timeout: Duration,
                       cancelling tasks: () -> [Task<some Sendable, Error>],
                       _ body: () async throws -> R) async rethrows -> R
  ```
- Watchdog is `Task.detached(priority: .background)` (escape MainActor
  congestion — see #245 lesson).
- Both BigHUD streaming and direct-trigger streaming switch to the
  helper.

---

### #A50 — Central elapsed-time ticker (replace scattered Timers)

**Status:** planned. Refactor.
**Touches:** `BigHUD.swift` AI elapsed, `MiniHUD.swift`,
`SettingsWindow.swift` test result, `ActionEditor.swift` playground.

**Context:** Several `Timer.scheduledTimer` instances tick at 0.1 Hz
for the elapsed-time UI. Each surface must manually invalidate on
disappear. A single shared `ElapsedClock` ObservableObject (or async
task loop) per surface lifecycle would auto-cancel via SwiftUI's
.task modifier.

**Requirements:**

- `ElapsedClock(startedAt:)` ObservableObject. Internally drives a
  10 Hz `Task.sleep` loop; sets `elapsed: TimeInterval` on MainActor.
- Tear-down on `deinit` / `.task` cancellation — no manual invalidate
  scattered across views.

---

### #A51 — AI HTTP session with explicit timeouts

**Status:** planned. Reliability.
**Touches:** `AIProvider.swift` non-streaming `run` paths,
`AIImageActions.swift` image HTTP, `UsageProbe.swift`,
`ActionTestSamples.swift` Mandrill download.

**Context:** Streaming paths use a tuned URLSession; non-streaming
paths fall through to `URLSession.shared` (60 s default request
timeout, no resource timeout). Test-connection / usage-probe /
image-fetch can therefore hang longer than the user expects.

**Requirements:**

- One `enum AIHTTP { static let session: URLSession = { ... }() }`
  with `timeoutIntervalForRequest = 20 s`,
  `timeoutIntervalForResource = 60 s`, custom UA.
- Every non-streaming AI HTTP call moves to `AIHTTP.session`.

---

### #A52 — ClipboardStore image dedup via content hash

**Status:** planned. Correctness.
**Touches:** `ClipboardModel.swift` `ClipboardStore.sameContent`,
`ClipboardItem` (new `contentHash` field, optional, lazy-computed).

**Context:** Today image dedup compares `previewImageRel` strings,
which are UUID-named per write — so two identical screenshots end
up as two separate history rows. Hash-based dedup catches this.

**Requirements:**

- `ClipboardItem.contentHash: String?` (lazy SHA-256 of the largest
  representation blob).
- `ClipboardStore.sameContent(a, b)`: compare semantic + contentHash
  when both are present.
- Hash computed off-main; back-fill on history load for items written
  before the field existed (Codable default = nil; computed on first
  comparison).
- Bonus: same logic dedups large text (5+ MB Markdown copies, etc.).

---

### #A53 — Orphan blob garbage collection

**Status:** planned. Hygiene.
**Touches:** `ClipboardModel.swift`, `ActionConfig.swift`,
`AppStorage` paths.

**Context:** Between `writeRawBlob` and index `save` a crash can leave
orphan blobs. Deleted history items / replaced descriptors don't
clean up their blobs. Application Support grows monotonically.

**Requirements:**

- On launch (or once per N launches): collect all referenced rels
  from `index.json` + `actions.json` testSamples + active accumulator
  state.
- Walk `blobs/` and `images/`. Anything unreferenced AND older than
  24 hours → delete.
- Skip user-dropped playground images that are referenced from
  Application Support (already covered by the above rule).
- NSLog the cleanup summary.

---

### #A54 — Snapshot pasteboard size caps + Settings preference

**Status:** planned. Reliability + UX preference.
**Touches:** `ClipboardModel.swift` `snapshotPasteboard`,
`SettingsWindow.swift` General tab.

**Context:** Huge PDFs / proprietary payloads can be 100 MB+ and will
land in `index.json` + blobs. On Dropbox-resident Application Support
that's painful.

**Requirements:**

- Per-representation soft limit (default 16 MB). Above limit, store
  metadata + thumbnail only, skip raw blob.
- For `.files` clips, never copy file contents — only the URL.
- Settings → General → "Max clipboard item size (MB)" slider, default
  16, range 1–256.

---

### #A55 — AI image preflight: auto-resize 4 MB cap

**Status:** planned. UX.
**Touches:** `AIImageActions.swift` size-check path.

**Context:** OpenAI gpt-image-1 caps source PNG at ~4 MB. Today the
action fails with "Image too large" and suggests the user manually
chain Resize / Compress. For direct-trigger flows this means the
hotkey just fails.

**Requirements:**

- Action descriptor parameter: `autoResizeForProvider: Bool` (default
  true).
- Preflight: if source PNG > 4 MB, downscale longer side to 2048 px
  + PNG-recompress, retry once. Show "Resized for upload (2048 px)"
  inline notice in the inflight panel.
- Off path: parameter set to false → action fails as today.

---

### #A56 — OpenRouter anchor → Codable per-provider struct

**Status:** planned. Reliability.
**Touches:** `UsageProbe.swift` anchor storage.

**Context:** Per-provider OpenRouter anchor (date / credits /
machine-UUID) currently lives as separate UserDefaults double keys.
Re-key detection works but is fragile (string compare on prefixes).

**Requirements:**

- `struct OpenRouterAnchor: Codable { providerID, date, credits,
  machineUUID, keyFingerprint }` keyed by providerID.
- Re-key detection compares key SHA-256 fingerprint (or last 4 chars
  if hashing keys feels wrong).
- Migration from old key layout: read old keys once, write new
  struct, delete old keys.

---

### #A57 — Playground / Settings test-task cancellation hygiene

**Status:** planned. Bug prevention.
**Touches:** `ActionEditor.swift`, `SettingsWindow.swift` playground.

**Context:** Playground "Run test" spawns a Task. If the user closes
the window or switches to a different action mid-run, the Task keeps
going (and may try to update a now-stale view). For AI test runs
this also burns tokens unnecessarily.

**Requirements:**

- Store the test task as a property on the view model.
- Cancel on: window close, action switch, "Run test" pressed again,
  view's `.onDisappear`.
- Use the same `previewToken` pattern as BigHUD to guard against
  stale results painting into the wrong action's pane.

---

### #A58 — Diagnostics snapshot + Settings → "Copy diagnostics"

**Status:** planned. Support / debugging.
**Touches:** new `Diagnostics.swift`, Settings General tab.

**Context:** When a user reports "Type Slowly didn't work" or "the
HUD froze on a long AI call" there's no quick way to dump runtime
state. NSLog goes to Console.app, which is opaque to most users.

**Requirements:**

- `Diagnostics.snapshot() -> String`:
  - Version + build commit + AppBrand.version
  - Engine kind (EventTap / Carbon / Monitor) + AX trusted
  - Active surface state (#A42's enum)
  - Active tasks (action / streaming / watchdog)
  - Provider readiness + last test results
  - Pasteboard changeCount + last source-app bundleID
  - Store item count + total blob size
  - Last action outcome (action ID + outcome case)
- Settings → General → "Copy diagnostics" button → clipboard.

---

### #A39 — Unified action execution pipeline + PasteCommitter

**Status:** planned. Architectural cleanup with a real bug-prevention
payoff. Surfaced by an external code-review pass; the same review
found a confirmed bug (Type Slowly via per-action hotkey was pasting
as plain ⌘V — fixed in 0.42.x as a one-off patch), which is the
canonical example of *why* the pipeline needs to be unified.
**Depends on #A40 (SelectionCaptureService).** Commit unification
alone is insufficient — direct-hotkey and HUD paths also diverge on
*source capture* (the former is selection-first via simulated ⌘C,
the latter reads stored history). Unified inputs require the unified
`CapturedInput { item, sourceApp, captureGeneration, pasteboardChange }`
structure that #A40 produces.
**Touches:** new `ActionExecutionPipeline.swift` + `PasteCommitter.swift`,
`main.swift` `actionHotkeyDidFire(actionID:)`, `commitOutcome(_:savedApp:)`,
`deferPasteAfterAILoad(savedApp:)`, BigHUD commit path,
Settings playground execute path.
**Context:** Today multiple entry points (BigHUD commit, ⌥⌘⏎ Paste & Keep,
per-action direct-trigger, hold-preview commit, deferred AI paste,
Settings playground) each construct their own switch over `ApplyOutcome`
to decide what to do with it. The patches stay in step *by hand*; the
Type Slowly bug existed for many versions because the direct-trigger
switch collapsed `.alternativeCommit(_, _)` to plain paste. Future
surfaces (Services menu, drag-out) would inherit the same risk.

**Requirements:**

- `ActionExecutionPipeline.execute(action:, on item:, sourceApp:) async
  -> ApplyOutcome` — single async entry point. Handles preview-token
  invalidation, AI streaming wiring, watchdog setup.
- `PasteCommitter.commit(_:into:, mode:)` — single sync entry point for
  side-effect application:
  - `.preview(item)` / `.alternativeCommit(item, .standardPaste)` →
    `performStandardPaste`.
  - `.alternativeCommit(item, .typeSlowly(delay, jitter))` →
    `performTypeSlowly`.
  - `.alternativeCommit(item, .typeFast)` → `performTypeSlowly`
    with fast preset.
  - `.sideEffect(_, perform)` → `perform()` + success sound.
  - `.failed(original, reason, _)` → mode-dependent: HUD/Playground
    commits paste the original (current `commitOutcome` behaviour);
    direct-trigger commits play the failure sound only (no paste —
    current `actionHotkeyDidFire` behaviour). Mode enum drives this.
- `PasteCommitter.Mode` enum: `.standard`, `.keepingHUDOpen`,
  `.deferredAI`, `.directHotkey`, **`.previewOnly`** (added per
  adversarial pass). The `.previewOnly` mode is for the Settings
  playground: it rejects `.sideEffect` and `.alternativeCommit`
  with a visible "test-only" notice so a `Run` button can never
  accidentally write to the system pasteboard, type into the
  frontmost app, or open Finder. The playground renders only
  through `TestOutputPane`; the committer is the single guard
  that prevents test runs from escaping the sandbox.
- **Mode × outcome policy table**, written explicitly to avoid
  the side-effect-in-`.keepingHUDOpen` ambiguity caught by the
  adversarial pass:

  | Mode | `.sideEffect` | `.alternativeCommit` | `.failed` |
  |---|---|---|---|
  | `.standard` | run + success sound, close HUD | dispatch by style | paste original |
  | `.keepingHUDOpen` | **close HUD before perform** (side effects steal focus, leaving HUD open behind a Finder window confuses) | dispatch by style, keep HUD open | paste original, keep HUD open |
  | `.deferredAI` | run + success sound | dispatch by style | failure sound only |
  | `.directHotkey` | run + success sound | dispatch by style | failure sound only |
  | `.previewOnly` | **REJECT** with `"side effect not runnable from playground"` notice | **REJECT** with `"\(commitStyle) not runnable from playground"` notice | render failure inline |

- **Typed terminal state from the pipeline** (per adversarial pass):
  `enum PipelineResult { case completed(ApplyOutcome, generation: Int), case cancelled(generation: Int), case failed(Error, generation: Int) }`. The committer requires a matching active generation token before applying. This closes the race where a user clicks ✕ in MiniHUD at the same moment the provider delivers the final SSE chunk: cancellation clears `pendingDeferredPasteApp` *first*, then awaits the task's cancellation, then any subsequent `.completed` arrival is a no-op because its generation no longer matches.
- Every entry point is rewritten to call the pipeline + committer.
  Direct switches on `ApplyOutcome` in main.swift go away.
- Regression tests from #A45: (i) triggering Type Slowly via a per-
  action hotkey produces character-by-character typing, not a ⌘V
  paste; (ii) `.previewOnly` mode rejects `.sideEffect` even when
  the test action would otherwise have opened a URL; (iii) cancel
  + completion race produces zero paste into the frontmost app.

**Implementation notes:**

- `PasteCommitter` is `@MainActor`; pipeline is async but commits land
  through the committer on MainActor.
- Keep `pendingDeferredPasteApp` as the only "where to paste later"
  storage; both pipeline and committer read it through a helper.
- The 0.42.x Type Slowly patch in `actionHotkeyDidFire` should be
  the second-to-last code change to that function — after this lands,
  the function becomes a thin wrapper around the pipeline.

---

### #A40 — SelectionCaptureService extraction

**Status:** planned. Refactor; no user-visible change beyond fewer
regressions in the selection-first paths.
**Touches:** new `SelectionCaptureService.swift`, `main.swift`
selection-first sites (per-action hotkey, Cut & Replace, hold-preview),
`PasteSimulator.swift` (already has `simulateCopyAndAwaitChange`).
**Context:** The selection-first sequence (write a sentinel to
pasteboard, simulate ⌘C, await pasteboard change, snapshot all
representations losslessly, optionally promote to history) is currently
inlined in multiple places. Each copy carries small variations: how
long to wait, whether to promote, what to do on empty. The behaviour
needs to be identical across surfaces so a new surface (e.g. macOS
Services menu, #A23) inherits the same correctness.

**Requirements:**

- Single typed entry point:

  ```swift
  enum SelectionCaptureError: Error {
      case noSelection           // pasteboard didn't change within timeout
      case timeout(Double)
      case inaccessible          // AX not granted
      case emptyPayload          // pasteboard changed but no usable type
  }

  func captureSelection(sourceApp: NSRunningApplication?,
                        timeout: TimeInterval = 0.5,
                        promoteToHistory: Bool = false)
      async -> Result<ClipboardItem, SelectionCaptureError>
  ```
- Source-app metadata (`sourceBundleID`, `sourceAppName`,
  `sourceWindowTitle`) is captured at entry time, not inferred later.
- `promoteToHistory: true` adds the captured item to ClipboardStore
  through the normal `store.add(_:)` path so dedup / 500-item cap /
  Watcher.ignoreNextChange all behave correctly.
- Test coverage in #A45 against a fake pasteboard.

---

### #A41 — Import / export merge audit + ImportReport

**Status:** planned. Real correctness gap. Currently `Import…` and
`Replace from file…` claim to handle "configuration" wholesale, but
the merge implementation may skip `customTransformations`, `customTitles`,
`actionOrder`, `actionHotkeys`, `testSamples`. Aborting on first
duplicate is silent, which mis-represents the partial result.
**Touches:** `ActionConfig.merge(from:)` (or wherever the merge lives),
new `ImportReport` struct, `SettingsWindow.swift` General tab UI.

**Requirements (phase 1 — audit):**

- Document for each `ActionConfig` field exactly what Import does:
  merge / replace / skip / keep-current. Currently undocumented.
- Identify the gaps (likely candidates: customTransformations
  per-id merge, customTitles per-id merge, actionOrder per-kind
  merge, actionHotkeys conflict policy on import, testSamples merge).
- Decide a unified strategy per field. Capture in
  SKILL.md → "Persistence" section.

**Requirements (phase 2 — implementation):**

- `ImportReport` struct:

  ```swift
  struct ImportReport {
      var addedActions: [String]        // ids
      var skippedDuplicates: [String]
      var replacedActions: [String]
      var hotkeysStolen: [(actionID: String, fromActionID: String, chord: String)]
      var hotkeysSkipped: [(actionID: String, chord: String, reason: String)]
      var preferencesChanged: Bool
      var samplesUpdated: Int
  }
  ```
- Settings → General "Import…" shows a follow-up sheet rendering the
  report: "Imported 12 actions, skipped 2 duplicates, 1 hotkey
  reassigned, preferences kept." Includes a "Show details…" expander.
- Replace mode is unaffected (always replaces wholesale); only the
  merge variant gets the report.

---

### #A42 — State machines (lite) for surfaces + action lifecycle

**Status:** planned. Refactor; reduces a class of "this flag must be
nil before that one is set" defensive code.
**Touches:** `AppDelegate` flag fields, `MiniHUDController.swift`,
`BigHUD.swift`.
**Context:** Today main.swift carries many implicit-state flags
(`actionHotkeyTask`, `bigHUDOpenTask`, `aiStreamingTask`,
`pendingDeferredPasteApp`, `pasteAndKeepDidFire`, `bigHUDShowSession`).
Every new surface (region capture, MiniHUD, deferred AI) adds another
flag that must guard against the others. Two small enums collapse the
combinatorics.

**Requirements:**

- `enum DrPasteSurfaceState`:
  - `.idle`
  - `.bigHUDGesture(session: BigHUDSession)`
  - `.bigHUDSummon(session: BigHUDSession)`
  - `.miniHUDDirectAction(token: MiniHUDToken)`
  - `.miniHUDDeferredPaste(token: MiniHUDToken)`
  - `.regionCaptureArmed`
  - `.regionCaptureSelecting(origin: CGPoint)`
- `enum ActionRunState`:
  - `.idle`
  - `.capturingSelection`
  - `.applyingLocal`
  - `.streamingAI(token: PreviewToken)`
  - `.waitingDeferredPaste`
  - `.committing`
  - `.cancelled`
  - `.failed(Error)`
- Both expose a `transition(to:)` method that asserts legal moves and
  performs side-effects (e.g. `cancelAllPriorTasks()` on transition
  to `.idle`). Illegal moves are NSLog'd and recovered to `.idle`
  rather than crashing.

**Implementation notes:**

- DO NOT introduce a heavyweight Mealy / Moore framework. Two flat
  enums + a switch in `transition(to:)` is enough.
- The watchdog patterns (#245 fix) survive as transition side-effects
  rather than free-floating `Task.detached` blocks.

---

### #A43 — PreferencesKeys enum (single source of truth for UserDefaults)

**Status:** ✅ Shipped. `PreferenceKeys.swift` is the single source of truth for UserDefaults keys (+ Factory Reset list).
"key drift" bugs in Factory Reset and Settings.
**Touches:** new `PreferenceKeys.swift`, every UserDefaults string
literal call site, `SettingsWindow.swift` Factory Reset path.
**Context:** UserDefaults keys are currently spelled as raw strings in
several files. Factory Reset wipes them by iterating a hand-maintained
list. SKILL.md APPENDIX B lists them by hand. These can drift. One enum
catches all three at compile time.

**Requirements:**

- `enum PreferenceKeys { static let hudFontScale = "drpaste.hud.fontScale"
  ; static let cheatSheetDisabled = "drpaste.cheatSheet.disabled" ; … }`
- Every UserDefaults call moves to `PreferenceKeys.<name>`.
- Factory Reset uses `Mirror(reflecting: PreferenceKeys.self)` or a
  hand-listed `static let allKeys: [String]` to iterate.
- SKILL.md APPENDIX B references the enum by symbol, not by string,
  so doc + code drift together.

---

### #A44 — ProviderResolver tighten-up + ResolvedProvider struct

**Status:** planned. Builds on the partial work already shipped in
0.35.x (resolveExecutorProvider helper, cheapestEnabledImageProvider
cache). Promotes a scattered helper into an explicit type so consumers
can't accidentally use the wrong field.
**Touches:** new `ProviderResolver.swift`, `ResolvedProvider.swift`,
call sites in `AIProvider.swift` runtime, `ActionEditor.swift`
provider picker, `BigHUD.swift` / `MiniHUD.swift` chrome,
`SettingsWindow.swift` action row badge.

**Requirements:**

- `struct ResolvedProvider`:
  - `providerID: String`
  - `providerLabel: String`
  - `providerKind: ProviderKind`
  - `modelLabel: String`
  - `isRerouted: Bool`
  - `rerouteReason: String?`
  - `capabilityUsed: AICapability` (`.text` / `.imageEdit` / `.textToImage`)
  - `recoveryHint: String?`
- `enum ProviderResolver { static func resolve(action:, operationKind:,
  config: ProvidersConfig) -> ResolvedProvider }` — pure function.
- Every UI consumer reads from a `ResolvedProvider` instance; no more
  per-surface "look up provider then check if rerouted" recipes.
- Existing `resolveExecutorProvider` collapses into a thin wrapper.

---

### #A45 — Contract tests: registry, migrations, provider resolution, commits

**Status:** partial — initial pass shipped. Test suite currently
passes 101/101.
**Touches:** `Tests/DrPasteTests/*.swift`. Some tests can use a fake
`AIProvider`, fake `NSPasteboard`, fake `URLSession`; others can
run against real ActionRegistry with a temp Application Support dir.

**Already shipped:**

- `SeedIntegrityTests` — descriptor IDs, applicable types, no
  duplicates.
- `MetadataIntegrityTests` — every seeded ID has a description in
  `BuiltinActionMetadata.descriptions` (current + legacy alias
  coverage post-0.50.0).
- `HotkeyPolicyTests` — reserved DrPaste chord rejection, system
  chord rejection with feature-name hint, auto-steal flow.
- `ProviderKindTests` — capability flags, image-edit support per
  kind, cheapest-image-provider cost ranking.
- `ActionConfigCodableTests` — Codable round-trip across schema
  evolution (custom AI / transformation / hotkey arrays).
- `UnicodeStylizerTests` — every style table round-trips ASCII
  (#A32 regression baseline + denormalize-then-restyle).

**Remaining (next maturity bump):**

- `remapLegacyActionIDs` migration tests — enabledFlags /
  customTitles / actionHotkeys / actionOrder / actionTestSamples
  remap from legacy → current; current-wins conflict policy.
- `runFirstLaunchSeeds` idempotence — running twice doesn't
  duplicate descriptors; absence of legacy descriptors in
  `customTransformations` post-seed.
- Import/export merge tests — once #A41 lands.
- `PasteCommitter` mode × outcome — once #A39 lands.
- `SelectionCaptureService` typed errors — once #A40 lands.
- Fake-stream AI cancellation tests (cancel + final-chunk race,
  90 s watchdog).
- `PasteboardWriter` representation-order tests (skip-missing
  blobs, fallback to preview path).
- `AppendAccumulator` — rich-text + image bridge, files-strict
  rejection of non-image non-files.
- `ScreenRegionCapture` — captured item carries source-app
  metadata.
- Curated-defaults icon coverage: for every ID in
  `CuratedDefaults.enabledByDefault`, `BuiltinActionIcons.iconName`
  ≠ `"gearshape"`.

**Test-writing principle (reaffirmed from #A4):**

Tests live in `Tests/DrPasteTests` and run via `swift test`. Pure
functions (transformations, classifiers, hash helpers) get fast
unit tests. Contract tests use a `TempDir.swift` helper to swap
`AppStorage.dataDir` for a temporary URL per test — never touch
the real Application Support directory.
**Touches:** `Tests/DrPasteTests/*.swift`. Some tests can use a fake
`AIProvider`, fake `NSPasteboard`, fake `URLSession`; others can
run against real ActionRegistry with a temp Application Support dir.

**Tests to add (initial set):**

- `ActionRegistry.runFirstLaunchSeeds`: each seed version is idempotent;
  v3 → v4 → v5 → v6 transitions add expected descriptors and don't
  clobber user edits.
- `CuratedDefaults.enabledByDefault`: snapshot of first-launch enabled
  set; failing test catches accidental defaulting of new actions.
- `ActionRegistry.reorder`: identity action always pinned first;
  reorder respects content-kind grouping.
- `ActionRegistry.isEnabled`: returns correct value for built-in,
  customAI, customTransformation across enabledFlags / descriptor.enabled.
- `ActionConfig` import/export: replace replaces, merge merges per
  documented policy (#A41).
- `ProviderResolver`: explicit provider wins; default fills in;
  image-incapable default → cheapest image-capable fallback in
  cost order; isRerouted flag matches reality.
- `HotkeyRecorder.conflicts`: reserved DrPaste chords are rejected;
  system chords (Force Quit etc.) are rejected with the right hint;
  conflicts auto-steal.
- `ActionRegistry.pruneOrphanHotkeys`: hotkeys for deleted actions
  are removed on launch.
- **#A39 regression test:** triggering Type Slowly via a per-action
  hotkey produces character-by-character typing, not a single paste.
- `PasteboardWriter.write`: representations land in correct order;
  `watcher.ignoreNextChange` is set before the write completes.
- `APIKeyStorage` fallback path: round-trip with Keychain off
  goes through JSON file with correct permissions.
- Fake-stream AI: partial chunks accumulate; finish marker breaks
  loop; cancellation aborts mid-stream; idle-timeout hits 90s.
- `AppendAccumulator`: rich + image bridge, files-strict track,
  non-image-file rejection (failure sound path).
- `ScreenRegionCapture`: captured item carries sourceApp metadata.

**Implementation notes:**

- Use `XCTestCase.measure` for the rich-text round-trip path —
  reflow throttle (5–10 Hz) shouldn't be regressed accidentally.
- Tests must NOT touch the real Application Support directory; use
  a `TempDir.swift` helper that swaps `AppStorage.dataDir` for a
  temporary URL per test.

---

### #A38 — Investigate transparent in-place MiniHUD → BigHUD promotion

**Status:** planned. Follow-up to #A12.
**Touches:** `MiniHUD.swift`, `BigHUD.swift`, transition coordinator.
**Context:** Once #A12 is in users' hands with the conservative
"close MiniHUD first, then open BigHUD" transition, evaluate whether
users would prefer a smooth in-place expansion. Decision is held back
because animations across two different NSPanel kinds are non-trivial
and could regress reliability.
**Requirements:**
- Defer until #A12 has 2+ weeks of real-world feedback.
- If proceeding: morph MiniHUD's panel into BigHUD's panel via a single
  frame animation + content cross-fade; suppress close+reopen.

### #A70 — Fun / Internet Slang action group (Leetspeak, LOLspeak, UwU, Hacker Terminal, Zalgo)

**Status:** planned.
**Touches:** new local transform engines under the Transformation handler;
CuratedDefaults action registrations + icons; two AI action definitions
reusing the existing AI pipeline; action category grouping in the picker.
**Context:** A meme-oriented action category. Low priority, high
shareability — the kind of feature people screenshot. Three of the five
transforms are fully deterministic and run with no model call (keeping the
free-and-local-first philosophy intact); two need AI because they are style
rewrites, not substitutions. Grouped so they read as a deliberate set, not
scattered novelties.
**Requirements:**
- New action category "Fun / Internet Slang" in the action list, holding
  the five actions below. Each transforms selected text and clipboard text.
- Where an action is local-capable, expose an optional AI mode toggle.
- (1) Convert to Leetspeak / 1337 — local. Substitutions
  `a→4 e→3 i→1 o→0 s→5 t→7`; optional aggressive level adds `l→1 g→9 b→8`
  plus a slang word map (`hacker→h4x0r`, `owned→pwned`, `elite→1337`).
  Example: `hello hacker world → h3ll0 h4x0r w0rld`.
- (2) Convert to LOLspeak / Cat Language — AI. Rewrite into LOLcat-style
  English ("I can haz cheezburger?"); preserve meaning, rewrite grammar in
  meme-cat style. Example: `Can I have a sandwich? → I can haz sandwich?`.
- (3) Convert to UwU / OwO Speech — local, optional AI mode. Replace r/l→w,
  soften words, optionally append faces (`UwU`, `OwO`, `nya~`).
  Example: `really cool friend → weawwy coow fwiend UwU`.
- (4) Convert to Hacker Terminal Slang — AI. Map intent to CLI metaphors
  (`sudo`, `apt install`, `rm -rf`, `grep`, `cat`, `echo`, `&&`, pipes),
  dry tech humor. Example: `I need coffee and sleep →
  sudo apt install coffee && rm -rf sleep`.
- (5) Corrupt as Zalgo Text — local. Add Unicode combining marks; intensity
  levels Light / Medium / Heavy as a parameter.
  Example: `The void looks back → T̴h̷e̶ v̸o̵i̷d̶ l̵o̸o̴k̶s̷ b̴a̷c̵k̶`.
- Local actions (1, 3, 5) must work fully offline. AI actions (2, 4) gate on
  AI availability and show the standard "needs AI" state when offline.
- Output preserves emoji/whitespace and passes through unsupported chars
  rather than mangling them.
**Implementation notes:**
- Leetspeak — pure table map:
  ```swift
  let leet: [Character: Character] = ["a":"4","e":"3","i":"1","o":"0","s":"5","t":"7"]
  func toLeet(_ s: String, aggressive: Bool) -> String {
      var map = leet
      if aggressive { map["l"]="1"; map["g"]="9"; map["b"]="8" }
      return String(s.map { map[Character($0.lowercased())] ?? $0 })
  }
  ```
- UwU — regex replaces `[rl]→w` (preserve case), `n([aeiou])→ny$1`,
  `\bhas\b→haz`; optional face injection after sentence-final punctuation.
- Zalgo — sample N marks per char from three combining-mark sets:
  up `U+0300…U+036F`, down `U+0316…U+0362`, mid (e.g. `U+0334…U+0338`).
  Intensity = max marks per char: Light `[1,1,0]`, Medium `[3,3,1]`,
  Heavy `[8,8,2]` (up, down, mid). Skip whitespace.
  ```swift
  let up = (0x300...0x36F).compactMap { UnicodeScalar($0).map(Character.init) }
  func zalgo(_ s: String, up u: Int, down d: Int, mid m: Int) -> String { /* sample */ }
  ```
- AI actions (2, 4) are thin: a fixed system prompt + the standard provider
  call. Suggested prompts captured in the feature draft; keep them short and
  "output only the rewritten text".
- Transforms should be re-run-safe (Zalgo/UwU may compound — acceptable).

---

### #A71 — Icon placement: Menu Bar vs Notch tray (multi-phase)

**Status:** planned. Multi-phase feature; phase boundaries deliberately
sharp because phase 2 is what *justifies* phase 1 — without the
hover-reveal value layer, this collapses into "the same icon in a
slightly different spot" and the build cost (new window class,
multi-monitor geometry math, screen-change observer, fullscreen
handling) outpaces the user value.

**Touches:** new `NotchTrayController.swift` + `NotchTrayPanel.swift`
+ `NotchDetector.swift`, `SettingsWindow.swift` Appearance tab,
`main.swift` status-item lifecycle (swap between NSStatusItem and
notch panel), `AppendAccumulator.swift` (halo state plumbing),
`HELP.md` documentation.

**Context (from design discussion):** Apps like NotchNook, Boring
Notch, DynamicNotch don't just *relocate* the menu-bar icon — they
turn the area around the notch into a new UI surface (hover-reveal
panel, drag tray, persistent media controls, AirDrop replacement).
Pure relocation is cosmetic and doesn't pay for itself. DrPaste's
notch mode must *do something menu-bar mode can't* or the toggle is
empty preference noise. Default stays **Menu Bar** so first-launch
users see the familiar surface; notch is opt-in.

**Naming:** the user-facing label is **"Around the notch"** (or
"Notch area"), not "Notch". The notch itself is a camera cutout; we
sit *next to* it. NotchNook / BetterTouchTool use "Nook" / "Notch
Bar" for the same reason — calling the setting "Notch" misleads.

**Settings location:** Settings → **Appearance**, alongside theme.
It's a visual placement decision, not functional, and the
appearance tab is where the user goes when they want to change how
DrPaste looks. NOT Settings → General — that's for behaviour
toggles.

#### Phase 1 — relocation foundation (0.55-ish)

- Notch detection via `NSScreen.main?.safeAreaInsets.top > 0` on
  macOS 12+ — built-in display only; external displays never report
  notch insets even if the built-in has one.
- Settings → Appearance → "Icon placement" Picker:
  - "Menu bar" (default)
  - "Around the notch" (visible on non-notch Macs, disabled with
    explainer "Available only on Macs with a display notch" — keeps
    the option discoverable so the user learns DrPaste has it).
- Live switch with no restart. Old surface tears down, new one
  builds up, accumulator state migrates (the colored dot transfers
  to whichever surface is active).
- Window recipe for the notch surface (reuse MiniHUD's pattern):
  `NSPanel`, styleMask `[.nonactivatingPanel, .borderless]`,
  `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces,
  .stationary, .ignoresCycle, .fullScreenAuxiliary]`,
  `hidesOnDeactivate = false`.
- Screen-change observer:
  `NSWorkspace.shared.notificationCenter.addObserver(self,
  selector: #selector(handleScreenChange),
  name: NSApplication.didChangeScreenParametersNotification, ...)`.
  Reposition the panel on monitor connect/disconnect, resolution
  change, sleep/wake.
- Multi-monitor policy: notch panel **only lives on the built-in
  display**. External monitors fall back to the regular menu-bar
  status item (yes, both surfaces can be live at once on
  multi-display setups — built-in shows notch tray, external shows
  the status icon, but only one is "active" for the colored-dot
  indicator and that one is the built-in display's notch).
- Hit area extends beyond the visible icon (notch corners eat clicks
  that "almost hit"). Pad ~30 pt around the actual visible icon.
- Fullscreen behaviour: the notch panel disappears in fullscreen
  apps because the menu bar does. This matches the menu-bar status
  item's fullscreen behaviour — neither surface wins in fullscreen.
  Documented in HELP.md so users don't expect different.

**Phase 1 success criteria:** user can toggle placement live;
indicator dot stays visible in notch mode where it would have been
hidden behind the notch in menu-bar mode on a wide menu bar;
multi-monitor and screen-resolution changes don't crash or leave
stranded panels.

#### Phase 2 — hover-reveal value layer (0.56-ish)

This is what makes notch mode *worth choosing*. Without it phase 1
is preference theatre.

- **Hover-reveal recent clips strip.** Mouse approaches the notch
  area → thin horizontal strip slides down from behind the notch
  showing the 5 most recent clipboard items as small chips
  (text preview / image thumbnail / file icon). Tap a chip → pastes
  into the previously-focused app, same path as ⌥⌘V → release. Strip
  auto-hides 250 ms after the mouse leaves.
- Hover trigger uses a transparent tracking-area NSPanel ~80 pt
  wide × ~40 pt tall flanking the notch on each side, registering
  `mouseEntered` / `mouseExited` to drive the strip's open/close
  animation. The tracking panel ignores clicks (passthrough to the
  menu bar below) — only the visible strip swallows clicks.
- **Persistent accumulator halo.** Append Copy session active
  (#A65 dot)? In notch mode, the area around the notch gets a
  subtle colored glow — red for rich-text track, cyan for files
  track — visible peripherally without staring at the menu bar.
  Replaces / supplements the 6 pt dot. Animation: 1.2 s breathing
  cycle at 60% → 100% opacity.
- The hover strip and the halo share the same NSPanel — they're
  two states of the same surface (collapsed = halo only, expanded =
  clips strip + halo).

**Phase 2 success criteria:** notch mode users use the hover strip
to paste recent clips without invoking ⌥⌘V at all in the common
"paste the thing I just copied" case; accumulator halo is reported
in user feedback as more visible than the 6 pt dot was.

#### Phase 3 — optional power features (0.57-ish, defer until phase 2 feedback)

- **Drop zone.** Drag any payload (text / image / files) over the
  notch area → DrPaste adds it to history without requiring focus
  switch + ⌘C. Visual landing target appears while a drag is
  active.
- **Region capture launcher.** Small crosshair icon left of the
  notch → click = `⌥⌘+drag` region capture, no hotkey memorisation.
- **Pin-to-notch favourites.** User flags a clip in BigHUD as
  "pinned" → it gets a permanent slot in the notch strip, ahead of
  the recency-ordered chips. Up to 3 pinned items.

#### Technical notes

- Notch insets only become available on macOS 12+. Earlier macOS
  versions don't run notch hardware anyway, so the picker just hides
  the option on `< 12` (or shows it disabled with "Requires
  macOS 12+" — pick discoverability over invisibility).
- The notch tray panel must not steal focus — `nonactivatingPanel`
  style mask + `becomeFirstResponder` returning false on the hosting
  view. Tested via "type into TextEdit → hover near notch → strip
  appears → keyboard focus stays in TextEdit".
- Accessibility: respect "Reduce Motion" — disable the halo
  breathing animation and the hover strip slide animation when
  reduced-motion is enabled (`NSWorkspace.shared
  .accessibilityDisplayShouldReduceMotion`).
- Display scaling: `safeAreaInsets` already accounts for "Larger
  Text" zoom; the panel's `convertFromBacking(_:)` math handles
  Retina vs non-Retina automatically when we use point-based frame
  origins.

#### What this is NOT

- Not a replacement for the menu bar icon. Menu bar stays the
  default and the canonical surface. Notch is *for users who want
  more than an icon, on Macs that have the hardware*.
- Not a separate clipboard manager. Same store, same actions, same
  hotkeys — only the placement of the visual surface changes.

---

### #A73 — Rich-text AI roundtrip preserving formatting

**Status:** planned.
**Touches:** `AIProvider.swift` (AI runtime for `.richText` inputs),
`AIAction.swift` (alternate result decoder), `RichTextHelpers.swift`
(markdown ↔ NSAttributedString bridge), `DefaultAISeed.swift` (new
seeded descriptors marked `appliesToRich = true`).

**Context:** AI actions today flatten rich text to plain text before
the provider call and return plain text. The user loses bold / italic /
links / colour / inline images on every AI transform — a "summarize"
or "translate" on a formatted document mails back a plain paragraph
even though the source had structure. Existing local transforms (case
change, Unicode pseudo-font, transliteration, trim, wrap) already
preserve formatting via the `preservesRichTextFormatting` engine flag;
AI actions should match.

**Requirements:**
- Send the rich-text source as Markdown (round-trippable, model-native)
  with an explicit "preserve formatting" instruction in the system
  prompt: "Output Markdown. Preserve bold (**), italic (*), inline
  code (`), and links ([text](url)) from the input."
- Parse the model response as Markdown back into NSAttributedString
  via the existing `RichTextHelpers.markdownToAttributedString`
  pipeline; emit `.preview(makeRichTextItem(...))` not plain text.
- Inline images (NSTextAttachment) survive the round-trip: extract
  to a per-attachment placeholder token (`[[image_1]]`) before send,
  re-attach by position from the original attachment table after the
  reply parses. Models can't see / generate images in this path, so
  placement is preserved by index, not regenerated.
- New optional descriptor field `richTextStrategy: .preserveMarkdown |
  .flatten` (default `.flatten` for backward compat) so the user can
  opt in per AI action.
- Seed the rich-text-capable variants of Translate, Fix grammar, and
  Make shorter as `ai.rich.translate`, `ai.rich.fix_grammar`,
  `ai.rich.make_shorter`. The existing `ai.text.*` variants stay as
  plain-text fast paths.

**Implementation notes:**
- The MD round-trip through `NSAttributedString(markdown:)` is lossy
  for block-level structure (lists, headings). For 0.56 we accept the
  inline-only fidelity since it covers ~90% of "format-preserving AI"
  user expectations; block-level survival is a separate work item.
- Attachment placeholder regex must be unique enough that models
  don't accidentally invent collisions (`[[image_NN]]` with N from 1
  to attachment count works).
- For Gemini / OpenRouter providers, the same system-prompt approach
  works; no per-provider branching needed.

---

### #A74 — Pre-distribution ID consolidation (0.56.0)

**Status:** completed in 0.56.0.
**Touches:** every descriptor file, every action struct, every
default-on / palette file, the icons table, the descriptions table,
the test-samples table, the migration helper, the seed-version
counters in `DefaultTransformationSeed.swift` and `DefaultAISeed.swift`.

**Context:** Pre-distribution housekeeping. Action IDs had drifted over
60+ batches into a flat namespace where `builtin.json_pretty`,
`builtin.file_to_image`, `builtin.image_ocr`, and `user.translate`
sat side by side with no shared structure. Adding a sixth Files action
or a tenth JSON action made the namespace harder to scan. Worse,
nothing prevented HUD chip filtering or hotkey resolution from getting
sloppy in the long term. Because the user is the sole installed user
and distribution hasn't happened, the cleanup window is open: rename
the world once, no compatibility layer needed.

**Decisions locked-in:**
- Convention v2: `<namespace>.<content_kind>.<verb_noun>` where
  `content_kind` matches the source `SemanticKind` ∈ {text, rich, url,
  json, table, markdown, code, image, files, html}. AI namespace =
  `ai.<content_kind>.<verb_noun>` for seeded AI descriptors;
  `user.<...>` reserved for genuinely user-created descriptors.
  `builtin.identity` is the sole universal-anchor exception (works on
  every content kind).
- HUD chip filtering is driven by `applicableTypes` + `isApplicable`,
  NOT by ID-substring parsing. Convention v2 is for human scanability
  and consistency only; the runtime contract is unchanged.
- One-shot config rewrite via `IDMigration056.apply(to:)` keyed off
  `seedTransformationVersion < 9` — translates legacy `enabledFlags`,
  `customTitles`, `customDescriptions`, `actionHotkeys`,
  `actionTestSamples`, `actionTestImageBlobs`, `actionOrder`,
  `customTransformations[*].id`, `customAI[*].id`. Idempotent.
- `paste_as_text` + `clean_formatting` merged into a single
  `builtin.rich.strip_formatting` (both did the same thing).

**New actions shipped alongside the rename:**
- `builtin.text.remove_line_breaks` — joins single newlines into
  spaces while preserving paragraph breaks (2+ newlines).
- `builtin.text.wrap_quotes` — wraps in typographic double quotes
  (`"…"`).
- `builtin.text.wrap_parens` — wraps in parentheses.
- `builtin.files.copy_shell_safe_paths` — POSIX single-quote-escaped
  paths, space-separated, safe to paste into Terminal.
- `builtin.files.to_rich_icons` — rich-text representation with Finder
  icons inline.
- `builtin.table.to_html` — clean `<table>` / `<thead>` / `<tbody>`
  output.
- `ai.text.make_shorter`, `ai.text.improve_clarity`,
  `ai.text.make_friendly` — three tone/length AI rewrites.
- `ai.code.explain`, `ai.code.find_bugs`, `ai.code.translate` — three
  code AI actions.
- `ai.text.draft_email_reply`, `ai.text.generate_email_subject` — two
  email AI helpers.
- `ai.text.clean_ocr` — flagship OCR-cleanup AI workflow.

**Plumbing:**
- `DefaultTransformationSeed.currentSeedVersion` 8 → 9.
- `DefaultAISeed.currentSeedVersion` 7 → 8.
- `IDMigration056` runs before either seed pass on existing installs.
- `AppBrand.version` 0.55.0 → 0.56.0.

---

### #A75 — Semantic traits model (contextual action visibility)

**Status:** SHIPPED (0.57.0). Built on the existing `ContentContext` /
`ContextDetector` (already recomputed live — so #A76 "store vs recompute" is
moot for content traits). What landed:
- Cheap content traits: containsEmails / containsURLs / containsCyrillic /
  containsLatin / uppercaseHeavy / messySpacing / wrappedLines (+ existing
  email / layoutWrong). Provenance trait `fromOCR` stored on the clip's
  `tags` and stamped by the OCR action (kill-feature chain).
- `requiredTraits` / `forbiddenTraits` on `CustomTransformationDescriptor` and
  `CustomAIDescriptor` (Codable-defaulted); honoured in both action paths'
  `isApplicable`. Rule in `ActionTraits.swift` (`ActionTrait.passes`):
  required is OR, forbidden blocks, unknown keys ignored.
- Built-in gates: extract emails→containsEmails, extract links→containsURLs,
  normalize spaces→messySpacing, remove line breaks→wrappedLines,
  Cyrillic→Latin→containsCyrillic, Latin→Cyrillic→containsLatin & NOT
  containsCyrillic; AI clean-OCR→fromOCR, draft-reply / subject→emailLike.
- Editor: "Show this action when…" toggle block + live "would appear for this
  sample ✓/✗" preview; hidden for image-only actions. Master Enabled/Disabled
  unchanged; no "always" override (clear the condition to always-show).
- One-shot migration stamps built-in gates onto an existing config.
DEFERRED to follow-ups: AI-path email-trait richness, locale-aware
Latin→Cyrillic default (#A77), AI auto-config (#A82).

**Status (original):** planned. Deferred — NOT part of the 0.56.0 pass.
**Touches:** `ClipboardModel` (ClipboardItem), capture pipeline (provenance
stamping), `ClipboardAction` protocol (requiredTraits / forbiddenTraits),
HUD action filtering, `ContextDetector`.
**Context:** A traits layer turns DrPaste from kind-only filtering into
content-aware surfacing — the core promise "show what makes sense for what
the user copied". This is a NEW architecture, not cosmetic: it touches the
clip model, capture pipeline, action protocol, and HUD filter. Stacking it
into the same pre-release blob as the ID rename is the main destabilization
risk; phase it separately.

Matching model:
`Action.matches = kind ∈ supportedKinds && requiredTraits satisfied && forbiddenTraits absent`

**Trait taxonomy (three lifecycles — do not conflate):**
- Cheap content traits (containsEmails, containsURLs, containsCyrillic,
  containsLatin, uppercaseHeavy, wrappedLines, repeatedSpaces,
  containsMarkdownSyntax, containsHTMLTags, looksMinified) — used for HUD
  gating. Lifecycle decided in #A76.
- Provenance traits (fromOCR, fromScreenshot, fromPDF, fromCamera, fromAI)
  — MUST be stamped at clip creation; cannot be recomputed later.
- Expensive traits (containsQRCode, containsBarcode, looksWrongKeyboardLayout,
  ocrConfidence, layoutRepairScore) — MUST NOT gate HUD visibility. Show the
  action when the primary kind fits; execute on click; fail softly.

**Kill-feature requirement (HIGH priority within this phase):** OCR → text →
downstream actions is a primary daily workflow (owner uses it constantly).
The OCR action must stamp `fromOCR` on its output clip, and the trait must
propagate through subsequent transforms so trait-gated cleanup
(`ai.text.clean_ocr` requiring `fromOCR`) surfaces automatically. Chained
trait propagation is first-class here, not an afterthought.

**Requirements:**
- ClipboardItem carries persisted provenance traits.
- Cheap content traits computed per the #A76 decision.
- requiredTraits / forbiddenTraits on ClipboardAction; HUD filter honours them.
- Expensive detection never gates visibility (show + soft-fail).
- Provenance propagates across transform chains (OCR kill-feature).

**Trait assignment UX (built-in + user-created actions):** Users must never
see the word "trait" — they answer one plain question, "When should this
action appear?". The action editor gains an optional "Show this action
when…" block next to the existing "Applies to:" content-type checkboxes, with
plain-language conditions (contains emails / contains links / is ALL CAPS /
looks like an email / came from screenshot-OCR / contains Cyrillic / contains
Latin / messy spacing / looks like code-JSON-markdown). Each maps 1:1 to a
cheap trait under the hood. Default: nothing checked = "always, for the
selected content types" (today's behaviour — backward compatible).

**Two-tier vocabulary (key distinction):** the small curated list is a
*human-UI* constraint, not a system one — a person is overwhelmed by 50
checkboxes, so the editor surfaces only the short, plain-language cheap-trait
set. The AI auto-config pass (#A82) has no such limit: it draws from the FULL
set of real, implemented, fine-grained traits so it can match very precisely.
Both tiers are bounded to traits the engine can actually compute (AI never
invents conditions) — only the *size shown to each consumer* differs. An
AI-selected fine-grained trait that isn't in the human checkbox list is still
displayed back in the editor (e.g. as a removable "AI-detected: …" chip) so
the user can see and undo it. Provenance / expensive traits appear in the
human list only where meaningful. `requiredTraits` = "Show when…"
(primary); `forbiddenTraits` = "Never show when…" lives under Advanced.
Built-ins ship with sensible gates pre-set and stay editable like any
descriptor. The existing Test panel shows live "would this appear for this
sample? ✓/✗" feedback so conditions are tuned against a real example.
Rule-based suggestions pre-fill likely conditions from the prompt/engine
(keyword heuristic); the AI upgrade of that step is #A82.

**Implementation notes:** Source — marketing-agent "Canonical Semantic Model"
doc + code-side review + owner discussion on editor UX.

---

### #A76 — Content-trait lifecycle: store vs recompute (owner decision before release)

**Status:** planned. Requires owner write-up + decision before first release.
**Touches:** `ClipboardModel`, `ContextDetector`, HUD filter.
**Context:** Provenance traits (#A75) are clearly stored at creation. Content
traits (containsEmails, uppercaseHeavy, …) are ambiguous: storing them on the
clip risks staleness when detection logic changes (persisted history carries
old verdicts); recomputing live on HUD-open avoids staleness at a small
per-open CPU cost. The model is therefore hybrid, not uniform.

**Owner action required before release:** write up the tradeoff in detail and
decide. Points to weigh:
- Recompute-on-HUD-open: always fresh, no migration on logic change, no schema
  growth; cost = O(visible clips × cheap detectors) per HUD open (likely
  negligible for cheap regex traits).
- Store-on-clip: O(1) at HUD open, but needs a detector-version field +
  re-detection migration when logic changes, and grows index.json.
- Hybrid is likely correct: provenance stored, content recomputed.

**Requirements:** decision recorded; ClipboardItem schema reflects it; if
recompute, define the detector entry point and its per-open budget.

---

### #A77 — Transliteration default visibility (locale-aware Latin→Cyrillic)

**Status:** SHIPPED (0.57.0). Content gate (containsLatin AND NOT
containsCyrillic) set on the built-in; `likelyTransliterable` not introduced.
Default-on is now locale-aware: `CuratedDefaults.localePrefersCyrillic` checks
`Locale.preferredLanguages` (explicit `-Latn` script subtags excluded), and
`isEnabledByDefault("builtin.text.latin_to_cyrillic")` returns it — curated-on
for Cyrillic-script users, palette-only otherwise. Cyrillic→Latin stays on
everywhere.

Plus a related detection refinement (same spirit): `detectCyrillicLanguage`
now breaks ties by the user's **locale** before speaker-count prevalence —
`localeCyrillicLanguageID` from `Locale.preferredLanguages`. When text fits
several languages equally (e.g. Serbian/Macedonian share most letters), a
Serbia locale picks Serbian. (For the Serbian/Macedonian pair the romanized
output is identical anyway — they romanize every shared letter the same — but
for pairs that differ on shared letters, e.g. Russian и→i vs Ukrainian и→y,
the locale now decides.) `localeCyrillicLanguageID` is test-pinnable.

Latin→Cyrillic auto target (`autoDetectLatinTarget`, default `"auto"`): a
Latin string carries almost no language evidence, so it resolves per clip —
(1) characteristic national-Latin letters (ž/č/š/ć/đ→Serbian, gj/kj→Macedonian,
q/ğ/ñ→Kazakh, ı/ç→Tatar, ź/ś→Bashkir, ă/ĕ→Chuvash, ī→Tajik; unique markers
weigh 10×, ties break by locale then prevalence), then (2) the user's locale,
then (3) `"interslavic"` as a LAST RESORT only. A specific Slavic language is
always preferred; Interslavic is rare in practice. `"interslavic"` is the
established pan-Slavic orthography (Medžuslovjansky): /j/→ј, iotation
decomposed (ja→ја, ju→ју, jo→јо, je→је, ji→ји), y→и (no ы/й), shch→шч — every
output letter decomposable and readable across Slavic, with no single language
privileged as the default. All 14 specific languages stay as explicit targets,
each with its own scheme (e.g. Russian y→ы/j→й/'→ь/''→ъ, Ukrainian г→h/и→y).
Editor picker: Auto · Interslavic · 14 langs.

**Status (original):** planned. Depends on cheap-trait gating from #A75.
**Touches:** `CuratedDefaults`, `DefaultTransformationSeed`, transliteration
actions, `ContextDetector` (containsCyrillic / containsLatin).
**Context:** Cyrillic→Latin has an honest content trigger (containsCyrillic).
Latin→Cyrillic does NOT — Latin text is ubiquitous, and a content-based
"likelyTransliterable" cannot reliably separate romanized Slavic ("Privet")
from English ("Private"). The real signal is the user's locale / preferred
languages, not clip content. For Cyrillic-first users (a large segment)
Latin→Cyrillic is valuable on their occasional Latin clips; for English-first
users it is noise. A blanket palette-only default was English-centric and is
rejected.

**Requirements:**
- Drop `likelyTransliterable` (unreliable content signal).
- Cyrillic→Latin: default-on, gated `containsCyrillic`.
- Latin→Cyrillic: gated `containsLatin AND NOT containsCyrillic`; default-on
  state follows locale — on when `Locale.preferredLanguages` contains a
  Cyrillic-script language, palette-only otherwise. User-overridable like any
  curated default.

---

### #A78 — Curate down the default text-clip action set

**Status:** planned. Discussion required (do not change defaults yet).
**Touches:** `CuratedDefaults`.
**Context:** Even with trait gating, a plain text clip with no special traits
surfaces ~17 ungated chips (Type Slowly, Normalize spaces, Remove line breaks,
lowercase, UPPERCASE, Sentence case, Wrap quotes, Wrap brackets, Bold,
Monospace, Plain ASCII, Markdown→Unicode, + AI Fix grammar / Translate /
Summarize / Improve clarity / Make shorter). "Show all the value" and "flat,
scannable strip" are in tension; the marketing doc does not name it. Keep
current defaults for now; revisit.

**Requirements (to discuss):** candidates to move to palette or down-rank —
text wrappers, Improve clarity, Make shorter; keep a tight always-on AI core
(Fix grammar / Translate / Summarize). Decide a target max ungated-chip count
for a no-trait text clip.

---

### #A79 — AI action onboarding affordance when no provider configured

**Status:** SHIPPED (0.57.0). The no-provider / missing-key paths already
returned `.failed(… recovery: .openProvidersConfig)` (recovery button →
Settings → AI); the copy is now onboarding-framed: "Connect an AI provider to
get a result — open Settings → AI." across all four AI execution sites
(run + stream × no-provider + missing-key). Deferred nicety: suppress the
failure chime specifically for this onboarding case (needs a distinct outcome
flag) — minor, not done.

**Status (original):** planned (near-term; small).
**Touches:** AI action execution path, MiniHUD / BigHUD preview, ActionEditor
preview.
**Context:** AI actions stay visible by default even with no provider
connected — hiding them means users never discover they can connect AI. But
running one with no provider currently fails. Instead of an error, the
preview / result should present a problem-framed onboarding affordance:
"Connect an AI provider — get the result" (RU: «Подключи ИИ-провайдера —
получишь результат»), with a one-click path to Settings → AI.

**Requirements:**
- Detect "no enabled provider" before executing an AI action.
- Render the onboarding message (localised) in place of the result, not a
  failure chime.
- Provide a recovery action ("Open Settings → AI") reusing the existing
  MiniHUD `.failure` recovery-button surface (#A69).

---

### #A80 — Frequency-based action ranking

**Status:** planned (low confidence — value unproven).
**Touches:** local usage store, action ordering.
**Context:** Ranking surfaced actions partly by how often the user actually
runs each would personalise the strip, but requires a local per-action usage
counter (new subsystem) and tuning to avoid feedback loops (frequently-shown
≠ frequently-wanted). Deferred; revisit after traits land.

**Requirements:** local usage counters; blend with contextual relevance +
curated priority; never the sole ranking signal.

---

### #A81 — Swift 6 language-mode readiness (NSFont/AttributedString warnings)

**Status:** planned (deferred — tie to an eventual Swift 6 language-mode
migration).
**Touches:** `UserGuideWindowController` (markdown → AttributedString
renderer), any other `NSFont`/`NSColor`-in-`AttributedString` sites.
**Context:** Under the current Swift 5.9 toolchain the project compiles with
~32 warnings of the form "conformance of 'NSFont' to 'Sendable' is
unavailable in macOS; this is an error in the Swift 6 language mode". They
all originate from assigning `NSFont` to Swift `AttributedString` attributes
in `UserGuideWindowController`'s help-window renderer (AttributedString
requires Sendable attribute values; NSFont's Sendable conformance is
unavailable). They are **non-blocking** today — only Swift 6 language mode
turns them into errors. Fixing them properly means re-expressing the renderer
with `NSMutableAttributedString` (whose `.font` attribute carries no Sendable
constraint), which is a deliberate rewrite, not a quick patch.

**Requirements:**
- When adopting Swift 6 language mode (or sooner if desired), convert the
  `UserGuideWindowController` styling helpers from Swift `AttributedString`
  + presentation-intent walks to `NSMutableAttributedString` enumeration, or
  otherwise eliminate the non-Sendable-attribute assignments.
- Audit the codebase for the same pattern at the same time.

---

### #A82 — AI auto-configuration of action traits

**Status:** planned (future enhancement of the #A75 trait-assignment UX).
**Touches:** ActionEditor (trait-assignment block), AIProvider, the cheap-trait
vocabulary.
**Context:** The #A75 editor pre-fills "Show this action when…" conditions
with a keyword heuristic over the action's prompt / engine / parameters. That
heuristic misses cases where intent isn't lexical — e.g. a custom AI prompt
"Rewrite this as a friendly reply to a colleague" implies emailLike / chatLike
without containing the word "email". An optional AI pass closes that gap: it
reads the action's prompt / engine / params and proposes the matching
conditions from the curated vocabulary. This is the strongest version of "the
user doesn't have to think about traits at all".

**Design constraints (keep it trustworthy and cheap):**
- Two complementary layers, not a replacement: rule-based heuristic is the
  free/offline baseline; the AI pass is an opt-in "✨ Auto-detect conditions
  with AI" button. No provider → heuristic still works.
- Suggest, never silently apply: AI output is shown for confirmation
  ("AI suggests: show only for emails — [Apply] [Edit]"), preserving user
  control and the "why did this chip appear" mental model.
- Runs once at action save/edit time, cached on the descriptor — NEVER per
  clip. Intelligence at configuration time; cheap pre-computed traits at
  trigger time.
- Constrained output, but a RICH vocabulary: AI picks from the full set of
  real, implemented traits — which can be large and fine-grained, because the
  "small list" is a human-UI concern, not an AI one (no risk of overwhelming a
  model). The only hard bound is that every chosen trait must be one the engine
  can actually compute — AI never invents conditions. A bigger vocabulary lets
  it match more precisely.

**Requirements:** button + confirmation UI in the trait-assignment block;
provider-gated (reuse the no-provider onboarding affordance from #A79);
constrained-vocabulary prompt; cache result on the descriptor.

---

### #A83 — Unit conversion: remaining edge cases

**Status:** planned (deferred from the 0.57.x converter hardening pass).
**Touches:** `UnitConversion.swift` (regex, `parseChunk`, `parseUnit`,
`convertMeasurement`), `UnitConversionFixesTests`.
**Context:** The inline measurement converter was substantially hardened —
fractions (ASCII / Unicode / hyphen-mixed), thousands/decimal separators
(comma, dot, space, EU `1.200,5`), spelled-out + hyphenated units, stone and
pound+ounce compounds, °C-vs-cup disambiguation, square/cubic units, hectare,
tonne, kph, m/s, and the `9 in 10` preposition false-positive. The cases below
were consciously left out as lower-value or genuinely ambiguous, and are
captured here so they are not rediscovered from scratch.

**Requirements (each independent; pick by value):**
- Numeric ranges: `25–30°C` / `25-30°C` → convert BOTH endpoints
  (`77.0–86.0°F`); currently only one endpoint is converted. Needs a
  range-aware match (`A[–-]B unit` → `convA–convB unit`).
- Feet+inches without an inch marker: `5 ft 11` / `5'11` → treat the trailing
  bare number as inches (→ `1.80 m`). Risky (`5 ft 11 people`), so gate on the
  trailing number being ≤ 11 and end-of-token.
- Fractional inch inside a compound: `6 ft 4½ in` / `5' 7½"` → single combined
  value instead of splitting into two conversions.
- Context-sensitive `oz`: `8 oz water` / `12 oz beer` → fluid ounces (volume)
  when the following noun implies liquid (water/soda/beer/milk/juice/…);
  default stays weight.
- `in` preposition before a noun: `5 in stock`, `9 in total` still convert as
  inches. Needs a small stop-word list (stock/total/fact/front/charge/order/…);
  the number-followed case (`9 in 10`) is already handled.
- Bare metric-ton `t` (`3,2 t`) — currently skipped to avoid false positives
  (`Section 5 t`); revisit with a tighter guard.
- `mg` (milligrams): produces a near-useless `0.0 oz`; needs grain output or a
  "too small to convert" skip rule.
- `cm²` / `cm³` / `2500 sq cm` square-and-cubic centimetres.
- Contextual temperature with no unit: `low 60s`, `mid-80s`, `thermostat set
  to 74`, `275-degree smoker`, `triple-digit`, `below zero`. Requires
  weather/oven context inference — high false-positive risk.
- Nominal sizes that must NOT convert: `2x4 lumber` (already skipped), but
  `9x13 pan`, `40x60 barn`, `20x30 ft` partial — distinguish real dimensions
  from nominal part numbers.
- Spelled-out numbers: `six-foot-two`, `five eleven`, `5 foot eleven`.
- Glued metric compound: `2m15cm` → currently splits into two conversions.

**Deferred adversarial cases (Codex review, ranges/feet/two-mode pass):**
- Signed ranges: `−5–10°C` / `minus 5–10°C` — first endpoint sign is dropped
  (converts only the unsigned part). Add an optional sign to each range endpoint.
- Phone/range collision: `call 1-800 m` → `1-800 m (3.3 ft–0.5 mi)`. Suppress
  ranges that look like phone/area-code patterns (leading `1-800`, `1-`).
- Coordinate/angle/time prime collision: `40° 5'11" N` converts as height; bare
  `wait 5'` converts as feet. Gate prime forms on a non-coordinate context.
- Compound range: `5–10 lb 3 oz` splits oddly; needs a purpose-built parse.
- `m/h` (meters per hour) → currently `5 m (16.4 ft)/h`; either support or block.
- Range endpoints beyond plain decimal: `1/2–1 cup` (fraction endpoint) only
  converts one side.
- Mixed-unit range output near thresholds: `0.39–0.4 in` → `10 mm–1.0 cm`
  (mathematically right but reads oddly) — decide and lock desired behavior.

**Implementation notes:** ranges and the feet+inches-no-marker case are the
highest value. Keep the regex's leftmost-longest ordering invariant (speed and
area units before the length units whose prefixes they share) when adding
anything new. A leading boundary lookbehind `(?<![\w.,$£€#])` blocks
`v3.5.2 m`, `10E3 m`, `$5 lb`; do not weaken it. Every change must keep the
false-positive suite green (`1st` / `2x4` / `1 c` / `a ton` / `9 in 10` /
`v3.5.2 m` / `$5 lb`).

---

### #A84 — Reconsider trait-gated actions that ship disabled by default

**Status:** planned (owner review — decide per action; do NOT blanket-flip).
**Touches:** `CuratedDefaults.enabledByDefault`, `DefaultTransformationSeed` /
`DefaultAISeed` `requiredTraits`, an optional one-shot migration.
**Context:** A Settings row toggle renders YELLOW when
`registry.hasActiveTraits(id)` is true — the action is gated by a trait and
only surfaces in the HUD when the focused clip matches that condition. Several
such actions ALSO ship disabled by default. The two together are partly
redundant for the "don't clutter the HUD" goal the disable was meant to serve:
the trait already hides the action for non-matching clips, so enabling it would
not pollute the everyday HUD — it would appear exactly when relevant. Worth
reconsidering each one. Observed by the owner directly in the Settings list.

Concrete candidates — trait-gated AND disabled today:
- `builtin.text.title_case` — traits `[uppercaseHeavy, lowercaseHeavy]`
- `builtin.text.sentence_case` — `[uppercaseHeavy, lowercaseHeavy]`
- `builtin.text.sort_lines` — `[multiline]`
- `builtin.text.unique_lines` — `[multiline]`
- `builtin.text.remove_line_breaks` — `[wrappedLines]`
- `builtin.text.latin_to_cyrillic` — `[containsLatin]`
- `ai.text.clean_ocr` — `[fromOCR]` (AI — needs a provider)
- `ai.text.generate_email_subject` — `[containsEmails, fromMailApp]` (AI)
- `builtin.text.zalgo` — `[fromChat]` (novelty)

**Notable inconsistency to resolve:** `builtin.text.uppercase` and
`builtin.text.lowercase` ship ENABLED with the SAME traits
(`[uppercaseHeavy, lowercaseHeavy]`), while `title_case` / `sentence_case` ship
DISABLED — there is no principled reason for the split.

**Requirements:**
- Decide per action: enable (trait gating is sufficient to avoid clutter) vs
  keep disabled (genuinely niche / novelty / destructive, or AI-cost-bearing).
- Resolve the case-action split (uppercase/lowercase vs title/sentence) one way.
- AI actions (`clean_ocr`, `generate_email_subject`) remain gated on a
  configured provider regardless; flipping the curated flag does not change the
  no-provider behavior.
- `zalgo` is a deliberate novelty — likely stays off even when `fromChat` holds.
- If flipping any default, add a one-shot migration guarded by a UserDefaults
  key, and do NOT stomp users who already customized those flags
  (#A41 / #A76 invariant).

**Implementation notes:** audit query — cross `registry.actions` with
`hasActiveTraits(id)` and `CuratedDefaults.isEnabledByDefault(id)`; the trait
lists live in `DefaultTransformationSeed` / `DefaultAISeed` `requiredTraits`.
The yellow toggle style is `EnabledCheckboxToggleStyle`, driven by
`registry.hasActiveTraits`.

**Partial progress:** the "wow / first-open" marketing set —
`builtin.url.preview_card`, `builtin.text.generate_qr`, `builtin.image.ocr`,
`builtin.files.to_rich_icons`, `ai.text.image_whiteboard` — was force-enabled
on existing configs (one-shot `applyWowSetEnableIfNeeded`, all already in
`enabledByDefault`). The remaining trait-gated-but-disabled candidates above
(title/sentence case, sort/unique lines, etc.) still need a per-action call.

---

### #A85 — Curated default action order (per content kind)

**Status:** ✅ Shipped. `CuratedActionOrder` defines a per-kind ordered ID list
(Hero/WOW → Everyday → Useful → Niche, identity pinned first), applied by
`ActionRegistry.reorder` as a live fallback when the user has not hand-ordered
a kind. A re-forceable one-shot reset (`applyCuratedOrderResetIfNeeded`,
version-keyed) discards any saved order so the curated order applies to every
user; bump the version when re-tuning. Ordering synthesised from a Codex review
+ owner intent. Covered by `CuratedActionOrderTests`.

---

### #A86 — Wrong-layout repair: Latin↔Latin layouts (AZERTY, QWERTZ, …)

**Status:** planned. Cyrillic layouts (Russian, Ukrainian) shipped; Latin ones
deferred.
**Touches:** `KeyboardLayoutRepair` (per-layout maps + detector), tests.
**Context:** `Fix layout` now handles English ↔ Russian / Ukrainian in both
directions (local text typed on QWERTY → local script; English typed on the
local layout → English), choosing the best-scoring swap via NSSpellChecker.
The owner noted that NON-Cyrillic layouts cause the same class of error — e.g.
a French AZERTY typist (a↔q, z↔w, m at the `;` key) or a German QWERTZ typist
(y↔z) touch-typing on a US layout produces wrong Latin letters. NSSpellChecker
has `fr` / `de` / `es` dictionaries available, so detection is feasible.

**Why deferred (the hard parts):**
- Latin↔Latin detection is weaker and false-positive-prone: both the original
  and the swapped text are Latin, so the decision rests entirely on
  English-vs-French/German spellcheck rather than a clean script flip. A
  stricter margin (and maybe a minimum word count) is needed.
- The repair is incomplete: AZERTY accents (é è à ç …) and German umlauts /
  ß live on the number row / AltGr, which a US layout renders as digits or
  drops — so swapping only the letter positions leaves accented words broken.
- QWERTZ differs from QWERTY in only y↔z, so many German words are unaffected
  and detection signal is thin.

**Requirements:**
- Extend the `Layout` model with Latin-script layouts (mark `isLatin`), each
  with its `enToLocal` position map and spellcheck language.
- Tighten `looksWrongLayout` / `repair` for Latin↔Latin (higher margin, min
  words) so genuine English/French/German prose is never repaired.
- Decide accent handling: either best-effort letters-only (document the gap) or
  a richer map that recovers dead-key accents.
- Tests: both directions per layout + a strong false-positive suite (genuine
  en / fr / de prose left untouched).

**Implementation notes:** the architecture already supports N layouts and a
script-aware swap language (`swapLanguage(of:layout:)`); adding a Latin layout
mainly needs the map + a Latin-specific detection threshold.

---

### #A87 — Wrong-layout repair: more non-Latin scripts (Greek, Hebrew, Arabic, Korean, Hindi)

**Status:** partial. **Bulgarian (Phonetic Traditional) and Serbian Cyrillic
SHIPPED** — Bulgarian via NSSpellChecker `bg`; Serbian via a bundled
frequency wordlist (`serbian-words.txt`, freq list ∩ Hunspell to drop subtitle
loanword pollution) since macOS has no `sr` dictionary. Greek / Hebrew / Arabic
have verified maps below but are deferred (Greek final-sigma scoring; Hebrew /
Arabic RTL). Korean / Hindi need a composition pass.
Detector is script-agnostic (`isLatinDominant` + `originalScore` over all layout
languages); adding a non-Latin layout needs only an accurate key map + a scorer
(installed spellchecker, or a bundled wordlist like Serbian's).

**Verified maps gathered (qwerty_key → letter), for when these are picked up:**
- **Greek (standard)**: w→ς e→ε r→ρ t→τ y→υ u→θ i→ι o→ο p→π a→α s→σ d→δ f→φ
  g→γ h→η j→ξ k→κ l→λ z→ζ x→χ c→ψ v→ω b→β n→ν m→μ (q = ; , not a letter).
  Caveat: word-final σ should be normalised to ς before scoring `el`.
- **Hebrew (SI-1452)**: e→ק r→ר t→א y→ט u→ו i→ן o→ם p→פ a→ש s→ד d→ג f→כ g→ע
  h→י j→ח k→ל l→ך ;→ף z→ז x→ס c→ב v→ה b→נ n→מ m→צ .→ץ (RTL).
- **Arabic 101**: q→ض w→ص e→ث r→ق t→ف y→غ u→ع i→ه o→خ p→ح [→ج ]→د a→ش s→س
  d→ي f→ب g→ل h→ا j→ت k→ن l→م ;→ك '→ط z→ئ x→ء c→ؤ v→ر b→لا n→ى m→ة ,→و .→ز /→ظ
  (RTL; `b`→لا is a 2-char ligature).
**Touches:** `KeyboardLayoutRepair.layouts` (+ maps), tests.
**Context:** Non-Latin layouts detect cleanly (no Latin↔Latin ambiguity) — the
only two blockers per language are (a) an installed `NSSpellChecker` dictionary
and (b) keyboard-map complexity.

**Dictionary availability (checked via `NSSpellChecker.availableLanguages`):**
- Cyrillic: ru ✓, uk ✓ (shipped); **bg ✓** (Bulgarian). sr / kk / be / mk ✗
  (Serbian, Kazakh, Belarusian, Macedonian — no dictionary → can't score → can't
  detect; map alone is useless).
- Other scripts: **el ✓** (Greek), **he ✓** (Hebrew), **ar ✓** (Arabic),
  **ko ✓** (Korean), **hi ✓** (Hindi). ka / hy / th / ja / zh ✗.

**Per-language feasibility:**
- **Bulgarian (bg)** — feasible, but TWO common layouts (БДС positional vs
  Phonetic); pick one (Phonetic is common among bilingual typists) or support
  both. Char-for-char.
- **Greek (el)** — feasible, single standard layout, char-for-char.
- **Hebrew (he) / Arabic (ar)** — char-for-char maps exist, but RTL handling
  (and Arabic contextual letter forms) need care.
- **Korean (ko)** — HARD: a US-layout swap yields uncomposed jamo; real Hangul
  needs jamo→syllable-block composition (Unicode Hangul algorithm).
- **Hindi (hi)** — HARD: Devanagari needs matra / conjunct composition.
- **Japanese / Chinese** — out of scope: not a layout swap at all (kana→kanji /
  pinyin→hanzi IME conversion), no dictionary either.

**Critical caveat:** the key maps must match the REAL physical layouts. A
round-trip test is involutive and therefore CANNOT validate a guessed map
against the actual keyboard — source maps from macOS `.keylayout` files / CLDR
(or confirm with a native typist) before shipping each language.

**Requirements:** add accurate `enToLocal` maps for bg + el first (cleanest
wins); decide Bulgarian layout variant; tests with real phrases in both
directions; keep the false-positive suite (genuine en / ru / uk / bg / el
prose untouched). Korean/Hindi tracked separately (need a composition pass).

---

## Changelog

Shipped versions. Each bullet is one observable change. Implementation-level
notes that informed each item live in this file's git history — every
revision of `BACKLOG.md` going back to the project's first commit can be
recovered via `git log --follow BACKLOG.md` and inspected with
`git show <commit>:BACKLOG.md`. The early revisions are bilingual and
include verbose technical reasoning per "Правка"; this current revision is
the curated, English-only working document.

### 0.57.0 — Architecture hardening, part 2

Continuation of the pre-distribution cleanup that started with #A74.
No new user-visible actions this round — the budget went to the
plumbing that makes adding the next batch of actions safer.

**Architecture wins:**

- **#A39 PasteCommitter.** Every commit surface (BigHUD release,
  per-action hotkey direct trigger) now routes through a single
  mode × outcome policy table in `PasteCommitter.commit`. The
  0.42.x Type Slowly direct-hotkey patch becomes a single row
  (`.directHotkey × .alternativeCommit(.typeSlowly) → typeSlowly`)
  instead of a special-case inline branch — the bug shape that
  fired in 0.42.x can no longer drift back in because the dispatch
  table is the single source of truth. The committer also gains a
  `.previewOnly` mode used by the Settings playground guard so
  test runs can never accidentally write to the system pasteboard
  or fire side effects.
- **#A40 SelectionCaptureService.** The "write sentinel → simulate
  ⌘C → await pasteboard change → snapshot all representations
  losslessly → optionally promote to history" sequence used by
  every direct-trigger surface (per-action hotkey, BigHUD hold-
  preview, ⌥⌘X Cut & Replace, ⌥⌘C Quick Copy, ⌥⌘S Append Copy
  seed, macOS Services menu) lives in one typed-error API.
  Sites still inline the old `simulateCopyAndAwaitChange` +
  `snapshotPasteboardAsItem` pair; the migration lands incrementally
  alongside the next batch.
- **#A41 ImportReport.** `Actions.swift importJSON(.merge)` used
  to handle exactly 2 of the 13 user-tunable `ActionConfig`
  fields — title renames, custom transformations, hotkeys, test
  samples, playground state, and preferences were all silently
  dropped on import. The new `ActionConfig.merging(_:)` walks
  every field, applies a policy table documented in
  `ImportReport.swift`'s header (incoming wins on `enabledFlags`,
  current wins everywhere else, hotkey auto-steal when an
  incoming chord lands on a different recipient), and returns a
  structured `ImportReport` ready to feed the Settings sheet's
  "what changed" summary.
- **#A44 ProviderResolver + ResolvedAIProvider.** A top-level pure
  function that takes a nominal `providerID`, an `AIOperationKind`,
  and the live `ProvidersConfig` and returns a strongly-typed
  `ResolvedAIProvider` struct with `providerLabel`, `providerKind`,
  `modelLabel`, `isRerouted`, `rerouteReason`, and `recoveryHint`
  fields. The four UI surfaces (Edit Action provider picker,
  BigHUD action chip, MiniHUD inflight label, Settings AI row
  badge) can read from one struct instead of reproducing the
  scattered "look up provider, check default, check cheapest"
  recipes. The existing `AIImageAction.ResolvedProvider` nested
  struct stays as the runtime-internal HTTP-dispatch payload —
  carries the API key, which UI must never see.
- **#A46 Persistence I/O.** `actions.json` and `index.json` writes
  now coalesce within a 200 ms window via a shared
  `PersistenceDebouncer`. Rapid bursts (multi-clip Append Copy
  session, batch import, Settings checkbox thrash) collapse into
  one write; the actual `Data.write(to:options:.atomic)` runs off
  the main thread. `applicationWillTerminate` flushes both
  saver instances so a 50 ms-before-quit edit never strands.
  Targets the perceivable 200–500 ms hitches users reported on
  Dropbox-resident Application Support.

**Bug fixes:**

- **#A33 Unicode Stylize re-applies cleanly.** Applying Italic to
  already-Bold text now denormalizes back to ASCII first, then
  applies the new table. Previous behaviour stacked silently:
  the Italic table is keyed on a-z / A-Z and the Bold glyphs
  aren't in those ranges, so the per-character lookup fell
  through to "pass it as-is" and the output came back identical
  to the input. The `upsideDown` style picks up the same
  denormalize-first fix.

**Test coverage:**

- New: `UnicodeStylizerTests` adds four denormalize-then-restyle
  invariants (`testStylingAlreadyStyledTextDenormalizesFirst`,
  `testStyleChainsAreIndependentOfPriorStyle`,
  `testStylingPlainInputUnchangedByDenormalizeFastPath`,
  `testUpsideDownDenormalizesBeforeFlip`).
- New: `SelectionCaptureServiceTests` covers the four typed
  `CaptureError` cases. Live `.success` / `.timeout` paths
  remain manual smoke until the pasteboard-fake harness lands.
- New: `ImportMergeTests` exercises every documented field in
  the merge policy table — `enabledFlags`, `customAI`,
  `customTitles`, `customTransformations`, `actionOrder`,
  `actionHotkeys` (current-wins + auto-steal), `actionTestSamples`,
  seed counters (must NOT migrate), and `preferences`
  (non-default incoming wins over default local).
- New: `PasteCommitterTests` pins the full mode × outcome
  dispatch table via a fake `PasteCommitterPerformer` recorder —
  Type Slowly via direct hotkey types, `.failed × .directHotkey`
  plays the failure chime only, `.previewOnly` rejects every
  escape attempt.
- New: `ProviderResolverTests` covers nominal-wins, capability
  mismatch reroute, cost-rank fallback, missing-API-key reroute,
  disabled-provider reroute, and empty-config returns nil.
- New: `PersistenceDebouncerTests` exercises the 200 ms coalesce
  contract and `flushSync` semantics.

**Plumbing:**

- `AppBrand.version` 0.56.0 → 0.57.0.
- New `SelectionCaptureService.swift`, `ImportReport.swift`,
  `PasteCommitter.swift`, `ProviderResolver.swift`,
  `PersistenceDebouncer.swift`.
- No seed bumps — no descriptor changes this release.

### 0.56.0 — Pre-distribution ID consolidation + 14 new actions

The headline of this release isn't a single new feature — it's the
namespace cleanup the project has been deferring for a year. Every
action ID was renamed to convention v2
(`<namespace>.<content_kind>.<verb_noun>`) so the registry, palette,
and Settings list now read as a coherent taxonomy instead of a flat
bag of historical accretions. The rename is one-shot — old configs
auto-migrate via `IDMigration056` and no compatibility shims survive
in the source. See **#A74** for the full decision log.

**Convention v2:** built-in actions are
`builtin.<content_kind>.<verb_noun>` where `content_kind` matches the
source `SemanticKind` (`text`, `rich`, `url`, `json`, `table`, `md`,
`code`, `html`, `image`, `files`). Seeded AI actions move to
`ai.<content_kind>.<verb_noun>`; `user.*` is reserved for actually
user-created descriptors. `builtin.identity` is the sole anchor
exception (works on every kind).

**Merge:** `builtin.paste_as_text` + `builtin.clean_formatting` →
`builtin.rich.strip_formatting`. They did the same thing.

**New local actions (6):**

- **#A74-1 Remove line breaks** (`builtin.text.remove_line_breaks`,
  engine `removeLineBreaks`). Joins single newlines into spaces and
  preserves 2+ consecutive newlines as paragraph breaks. Fixes
  hard-wrapped PDF / email-quote paste-back.
- **#A74-2 Wrap in quotes** (`builtin.text.wrap_quotes`). Typographic
  double quotes via the existing `wrap` engine.
- **#A74-3 Wrap in parens** (`builtin.text.wrap_parens`).
- **#A74-4 Shell-safe paths** (`builtin.files.copy_shell_safe_paths`).
  POSIX single-quote escaping (`'\''` idiom), space-separated.
- **#A74-5 Rich icons representation** (`builtin.files.to_rich_icons`).
  `NSAttributedString` with Finder icons inlined next to filenames.
- **#A74-6 CSV → HTML table** (`builtin.table.to_html`). Clean
  `<table>` / `<thead>` / `<tbody>` — for Notion / Confluence /
  Google Docs.

**New AI actions (9, seed-version bump 7 → 8):**

- `ai.text.make_shorter`, `ai.text.improve_clarity`,
  `ai.text.make_friendly` — three tone / length AI rewrites covering
  the "this paragraph is too long / too dense / too cold" pattern.
- `ai.code.explain`, `ai.code.find_bugs`, `ai.code.translate` — three
  code AI helpers.
- `ai.text.draft_email_reply`, `ai.text.generate_email_subject` — two
  email AI shortcuts.
- `ai.text.clean_ocr` — flagship OCR cleanup workflow (joins broken
  words, repairs common OCR mistakes, normalises whitespace).

**Plumbing:**

- `IDMigration056.swift` — one-shot config rewrite gated on
  `seedTransformationVersion < 9`. Rewrites every legacy ID across
  enabledFlags / customTitles / customDescriptions / actionHotkeys /
  actionTestSamples / actionTestImageBlobs / actionOrder /
  customTransformations / customAI. Idempotent.
- `DefaultTransformationSeed.currentSeedVersion` 8 → 9 (new
  descriptors + rename).
- `DefaultAISeed.currentSeedVersion` 7 → 8 (rename + 9 new seeds).
- `AppBrand.version` 0.55.0 → 0.56.0.

### 0.53.0 — Batch: 6 new actions + 4 HUD polish + diagnostics + cancellation hygiene

A wide batch covering content-output variety, in-HUD UX polish, and a
debugging backstop. No correctness fixes this round — the codebase is
in a stable spot post-0.52, so the budget went to user-visible surface
area instead.

**New local actions (6):**

- **#A15 CSV → Wiki / CSV → Rich table** (`CSVTableActions.swift`).
  Two parallel actions sharing a small RFC-4180-ish parser (handles
  quoted fields with embedded commas / newlines / `""`-escapes plus
  CRLF/LF). Wiki action emits MediaWiki table markup as text (broad
  paste compatibility); RTFD action builds an `NSTextTable` for
  rendered paste into Mail / Notes / Pages / Word. Slack / Notion fall
  back to plain text by design.
- **#A18 Latin → Cyrillic (local)** (`CustomTransformation.swift`,
  engine `latinToCyrillic`). Reverse transliteration with target-
  language parameter (Russian default; Ukrainian / Bulgarian / Serbian
  overrides). Greedy digraph match (`shch` > `sh` > `s`, etc.). Case
  preserved per source run. The AI counterpart ships in 0.54.0.
- **#A19 Pretty Code (local)** (engine `prettyCodeLocal`).
  Deterministic offline reformatter — JSON via JSONSerialization
  (.prettyPrinted + .sortedKeys), XML via XMLDocument .nodePrettyPrint,
  HTML reflow (newline-after-tag + tag-depth indent), CSS (newline
  after `;`, 2-space rule indent), generic whitespace cleanup
  otherwise. Auto-detect by leading characters; sub-50 ms typical.
  The AI counterpart for arbitrary languages ships in 0.54.0.
- **#A70 Fun / Internet Slang trio** (engines `leetspeak`,
  `uwuSpeak`, `zalgo`). Leetspeak: pure table map (`a→4 e→3 i→1 o→0
  s→5 t→7`); Aggressive flag adds `l→1 g→9 b→8`. UwU: r/l → w
  case-preserving + `n + vowel → ny + vowel`; optional `UwU / OwO /
  nya~` injection after sentence-ending punctuation. Zalgo: combining
  marks from `U+0300…U+036F` (up), `U+0316…U+0362` (down), `U+0334…
  U+0338` (mid), intensity Light / Medium / Heavy. All three are
  palette-enabled rather than curated-on — the default chip strip
  stays serious. The two AI actions (LOLspeak, Hacker Terminal) ship
  in 0.54.0.

**HUD UX polish (4):**

- **#A63 Action chip outline style** (`BigHUD.swift`). The selected
  action chip switches from a solid accent fill to a thin accent
  border + faint tint so it reads as a "command" rather than another
  contained object. Clip selection in the history strip keeps the
  solid-fill style — clips ARE objects, that style fits them.
- **#A61 Empty-history onboarding panel** (`BigHUD.swift`). The
  generic "History is empty" placeholder is replaced with an inline
  explainer: clipboard icon, "Your clipboard history is empty", a
  one-line instruction, and three keyboard chips (`⌘C` / `⌥⌘V` /
  `esc`). Shown on first launch, after Factory Reset, and after
  manual clears.
- **#A69 MiniHUD explicit `.failure` state** (`MiniHUD.swift`,
  `main.swift`). Direct-trigger action failures no longer vanish
  silently after the `pasteFailure` chime — the MiniHUD now switches
  to a red ✕ + action title + one-line reason and auto-dismisses
  after 4 seconds. Optional recovery button (title + closure) for
  cases like missing-key → "Open Settings". Same surface is used by
  the BigHUD's `commitOutcome` failed path eventually (pair with
  #A39's PasteCommitter work).
- **#A60 Append Copy tooltip + Settings explanation finish**
  (`SettingsWindow.swift`). Tooltip wiring already landed in 0.51.0;
  this round adds a dedicated "Append Copy" section to Settings →
  General with a labeled red / cyan dot row and a 120 s timeout
  explainer so a user who hasn't read HELP.md can self-onboard from
  the Settings pane.

**Diagnostics + bug-prevention (2):**

- **#A58 Diagnostics snapshot + Copy button** (`Diagnostics.swift`,
  `SettingsWindow.swift`). A Markdown report of runtime state
  (version, AX trust, HUD mode, store stats, registered action count
  broken down by builtin / user / AI, configured providers with
  API keys redacted to last-4, pasteboard changeCount + top types,
  interesting UserDefaults keys). Settings → Configuration → "Copy
  diagnostics" pastes it to the clipboard — drops cleanly into a
  bug report.
- **#A57 Playground test-task cancellation hygiene**
  (`ActionEditor.swift`). The Run-test path now stores its Task
  handle on the view model, cancels the previous run before starting
  a new one, gates all MainActor result writes on `!Task.isCancelled`,
  and tears the task down on `.onDisappear`. Stops the
  "fast double-click on Run" race where the loser stomped the live
  outcome; also stops a closed-window AI call from burning provider
  tokens for a result that has nowhere to land.

**Plumbing:**

- `DefaultTransformationSeed.currentSeedVersion` bumped 6 → 7 so
  existing installs pick up the five new descriptors on next launch
  via the standard new-entry seed pass.
- `BuiltinActionIcons` / `BuiltinActionEditor` descriptions /
  `CuratedDefaults.enabledByDefault` /
  `ActionTestSamples.sample(for:)` all updated for the five new IDs.
- `MiniHUD.swift` gains `MiniHUDFailure` view-model + `showFailure`
  controller method + a `failure` published state property on
  `MiniHUDState`.
- Auto-dismiss task on the MiniHUD failure surface (`autoDismissTask:
  Task<Void, Never>?`) is cancelled in `hide()` and on the next
  `show()` / `showFailure()` so a fast sequence of fires never
  schedules overlapping dismiss timers.

**Deferred to 0.54.0:**

- AI counterparts to #A18 (Latin → Cyrillic AI) and #A19 (Pretty Code
  AI).
- AI half of #A70 (LOLspeak, Hacker Terminal).
- #A17 Paste-as-is file icons + text sample.
- #A22 URL preview cards (local HTML parse).
- #A47 NSImage.lockFocus → CGContext / CIImage.
- #A50 Central ElapsedClock.
- #A53 Orphan blob GC.
- #A59 release-to-paste discoverability hint (HintState schema is
  spec'd in BACKLOG already; deferred only because the in-HUD chrome
  is crowded post-#A61 and needs a layout pass first).

### 0.52.0 — Batch: 3 new actions + correctness + AI image preflight + cleanups

Pairs with 0.51.0 as a tested release pair. Adds three brand-new local
actions (Resize Images universal, File → Image extraction, Unit
conversion), a real-correctness fix for image transformations, an AI
image preflight, and the post-0.50 calibration items the colleague
flagged in his review.

**New local actions (3):**

- **#A14 Resize Images universal** (`ImageResizeAction.swift`).
  Single action handles three input kinds: image clips, files clips
  containing image files, and rich-text clips with embedded image
  attachments. Default `maxLongSide = 1920` (parameterisable through
  the descriptor once #A16's parameter editor lands). Never enlarges
  — images already at or below target pass through untouched. Output
  format preservation: PNG → PNG, JPEG → JPEG q=0.92,
  HEIC → JPEG (HEIC encode is not universally supported via
  NSBitmapImageRep), TIFF → PNG. Curated-on by default.
- **#A21 File → Image extraction** (`FileToImageAction.swift`).
  PDF page 1 rendered at 2× scale via PDFKit → PNG. HEIC / HEIF /
  TIFF / BMP / GIF → re-encode as PNG. Single-file clips only;
  multi-file rejected on purpose. Curated-on by default.
- **#A20 Unit conversion** (`UnitConversion.swift`). Local action,
  no AI. Auto-detects metric vs. imperial measurements in text and
  inserts the converted equivalent in parentheses ("75 °F (23.9 °C)").
  Six categories: length (m/cm/mm/km ↔ in/ft/yd/mi), weight
  (g/kg ↔ oz/lb), temperature (°C ↔ °F — no Kelvin per user spec),
  volume (L/mL ↔ fl oz/gal/qt/pt), speed (km/h ↔ mph), area
  (m² ↔ ft²). Parser handles compound forms (`6 feet 7 in`,
  `5'11"`), decimal vs. comma (`5.5` / `5,5`), and °/non-° variants.
  Curated-on by default.

**Correctness (1):**

- **#A48 Image actions load original, not preview thumbnail**
  (`ImageActions.swift`). `loadImage` priority order inverted:
  raw `public.png` / `public.tiff` / `public.jpeg` / `public.heic`
  representations are tried first, and `previewImageRel` (a 600 pt
  thumbnail) becomes the last-resort fallback. Previously every
  image transformation (OCR, Grayscale, Rotate, AI Watercolor)
  silently degraded to thumbnail resolution when both were stored
  — a Grayscale on a 5K screenshot output a 600 pt grayscale,
  losing ~95% of the data. Now operates on the source bytes.
  `loadPreviewImage(_:)` is exposed for HUD chrome / Settings list
  use where the thumbnail is what's wanted.

**AI image preflight (1):**

- **#A55 AI image preflight auto-resize**
  (`AIImageActions.swift`). The 4 MB hard cap remains as the
  final safety net, but now the preflight first tries to downscale
  the longer side to 2048 px and re-encode PNG. If that brings the
  upload under 4 MB, the action proceeds (with a "resized for
  upload" NSLog for diagnostics). If even the 2048-px version is
  too dense (extremely rare), it still fails with a clear message.
  Closes the dead-end where a direct-trigger AI image hotkey on a
  large screenshot would fail with no recovery path.

**Calibration items from the colleague's post-0.50 review:**

- **#A45 marked partial** (was `planned`) with explicit
  shipped-vs-remaining breakdown. Six test files already exist
  (SeedIntegrity, MetadataIntegrity, HotkeyPolicy, ProviderKind,
  ActionConfigCodable, UnicodeStylizer); the remaining contract
  tests (migration / commit / capture / accumulator) are listed
  explicitly so the next test-writing pass knows what to add.
- **#A64 BACKLOG cleanup.** The old `BuiltinTitleOverride or
  expand customTitles into customTitles + customDescriptions`
  ambiguity is gone — the spec now states a single schema:
  `description: String?` on descriptors,
  `customDescriptions: [String: DescriptionOverride]` on
  `ActionConfig`. Duplicate `Touches:` block removed.
- **SKILL.md Appendix C ID rename.** `md_extract_headings` →
  `md_headings`, `json_extract_keys` → `json_keys`. Legacy alias
  note added so docs match production code.
- **SKILL.md CuratedDefaults summary refreshed.** The old
  "Unicode fancy: bold, italic, fullwidth (small selection out of
  20+)" was a year out of date. New summary lists every style in
  the curated set (21 entries) and explains the philosophy.

### 0.51.0 — Batch: foundation + UX wins + content-hash dedup

Eleven backlog items in one release. The work splits cleanly into
three groups: shared foundation (#A43, #A49, #A51, plus toast surface
used by two later items), user-visible UX (#A30, #A60 finish, #A65,
#A66, #A67 finish), and correctness (#A52, #A57 partial). Each item
is small and independently testable.

**Foundation:**

- **#A43 PreferenceKeys enum** (`PreferenceKeys.swift`). Every
  UserDefaults key in the project moves to a static constant. Factory
  Reset will iterate `PreferenceKeys.allDirectKeys` rather than a
  hand-maintained list (next release will rewire Factory Reset to
  consume it). New keys must be added here first — string literals
  spread across SettingsWindow / BigHUD / WelcomeWindow are the
  drift source.
- **#A49 `withWatchdog(seconds:cancelling:)`** (`ConcurrencyUtil.swift`).
  Extracts the detached watchdog pattern (#245 lesson) into a
  reusable helper. Both BigHUD streaming and direct-trigger AI will
  consume it as #A39's pipeline rewrite catches up; for now the
  helper exists and is documented.
- **#A51 AIHTTP shared session** (`AIHTTP.swift`). 20 s request
  timeout, 60 s resource timeout, custom UA. `UsageProbe` switched
  off `URLSession.shared`. Non-streaming AI calls will migrate in
  follow-ups as their files get touched; AI streaming paths keep
  their own session (different timeout profile).
- **ToastController** (`ToastController.swift`). Non-activating
  panel anchored near the menu-bar icon. Single-instance: a second
  toast within auto-dismiss replaces the first. Category system so
  the user can mute Append Copy specifically without losing
  essential (permission-denied) toasts. Powers #A65, #A66, and
  later #A60-style explanations.

**User-visible UX:**

- **#A30 HUD Pin button**. New pin icon in the BigHUD header next
  to ✕. Click → toggle pinned state. Pinned HUD survives commit
  (release ⌥⌘ or ⏎ pastes but doesn't close). Per-session: every
  fresh ⌥⌘V open starts unpinned. Visual: `pin.fill` accent when
  pinned, slightly-rotated `pin` secondary when unpinned. Tooltip
  + accessibility label switch with state.
- **#A65 Append Copy toasts**. ⌥⌘S now surfaces a short
  inline message: "Append started" (first press of a session),
  "Clip appended" / "Files appended" (subsequent), "Append ended"
  (timeout / cancellation). Anchored near menu bar so it doesn't
  compete with the user's current app. Settings → General will
  surface the mute toggle (#A60 finishes the explanation row
  separately).
- **#A66 Region Capture confirmation toast**. After ⌥⌘+drag
  produces a successful capture, a 1.2 s toast shows
  "Captured WxH" with a camera-viewfinder glyph. Permission-denied
  path will get its own toast in a follow-up (depends on AX
  bridge changes).
- **#A67 Cheat sheet per-action hint** (finish). Per-action chord
  rows in the region-capture cheat sheet now read
  `⌥⌘T  Translate to Spanish — tap run, hold preview`. Pairs with
  the existing HotkeyRecorder footer hint added in 0.42.3. The
  semantics are now visible in both surfaces.

**Correctness:**

- **#A52 Content-hash image dedup**. `ClipboardItem` gains a
  `contentHash: String?` field (Codable, default nil for old saved
  items). `ClipboardStore.add` auto-computes a SHA-256 of the
  largest representation blob (or previewText for text-only items)
  on inbound items. `sameContent` prefers hash comparison when
  available, falling back to the previous `previewImageRel ==
  previewImageRel` path for items without a hash. Two identical
  screenshots now dedupe correctly.

**Post-0.50.0 calibration items (from external review):**

- Comment in `remapLegacyActionIDs` corrected from "0.42.5 hot-patch"
  to "shipped in 0.50.0" (the project skipped 0.42.5; the migration
  shipped as part of the 0.50.0 release).
- Conflict policy in `remapLegacyActionIDs` rewritten to honestly
  describe **current-wins-uniformly** (the previous text claimed
  legacy-wins for user-intent fields but the code never matched
  that claim — current always wins). Rationale added: if a current
  key exists, the user has already interacted with the new seeded
  action, and that intent must not be silently displaced.
- Explicit note added that `customTransformations.id` is
  intentionally not remapped because legacy IDs were never seeded
  as descriptors, only as side-table keys.

### 0.50.0 — Adversarial review integration (hot-patch + 8 spec deepens)

Second adversarial review pass on the project. Unlike previous rounds
which echoed back consensus, this one — explicitly framed as
"attack mode" — surfaced one real production bug and eight concrete
spec refinements that hadn't been caught by our own thinking. Version
jumped 0.42.4 → 0.50.0 to mark the inflection: from here the project
plan reflects the adversarial-pass corrections.

**Hot-patch (the bug):**

- **CuratedDefaults legacy IDs lose user state on upgrade.** In 0.42.4
  the seed switched to current IDs (`builtin.json_keys`,
  `builtin.md_headings`, `builtin.md_links`) and we kept the legacy
  `_extract_` IDs as metadata/icon aliases on the assumption that
  saved configs would gracefully degrade. They wouldn't: an upgrading
  user with hotkey ⌥⌘K bound to `builtin.json_extract_keys` would
  see the freshly-seeded `builtin.json_keys` action appear next to
  their orphaned customisation. The hotkey looks like it stopped
  working; the renamed action looks like it disappeared.
  `remapLegacyActionIDs(into:)` now runs **before** seedTransformations
  in `runFirstLaunchSeeds`, walking enabledFlags / customTitles /
  actionHotkeys / actionOrder / actionTestSamples and re-keying
  legacy → current. Legacy aliases in metadata/icons retire in a
  later release once no live install can still be running pre-0.50.

**Backlog spec refinements (the eight points that landed):**

- **#A64** — built-in description overrides now carry a
  `baseDefaultHash` so a future better-default-description doesn't
  silently hide behind a stale user override. Empty `description`
  no longer renders as a dead empty second line — fallback chain
  ends with a generated descriptor summary ("Regex replace · Applies
  to Text, Code"). No backfill of bundle defaults into config (i18n
  trap). Explicit dependency on #A41 for import/export merge policy.
- **#A39** — adds `.previewOnly` PasteCommitter mode that rejects
  side effects + alternativeCommit for Settings playground (closes
  the "Run test ran an action that opened Finder" failure mode).
  Adds explicit mode × outcome policy table including side-effect
  handling in `.keepingHUDOpen`. Adds typed terminal state
  `.completed / .cancelled / .failed(_, generation:)` so a cancel
  + stream-completion race produces a no-op, not a stray paste.
  Explicit dependency on #A40 for unified CapturedInput.
- **#A59** — release-to-paste hint state is now
  `{ successfulCommits, lastShownVersion, lastCommitDate,
  resetGeneration }`. Factory Reset bumps generation; staleness
  window of 90 days re-shows once. Closes the "year-old user
  reopens, has counter past threshold" gap.
- **#A1** — release-day checklist gains a `try!` → boot-phase
  fatal UI replacement. Three-button panel ("Open folder", "Reset
  storage", "Quit") for the sandboxed-build case where Application
  Support is recoverably unavailable. `try!` stays defensible
  *only* if this recovery path exists.

**SKILL.md refinement:**

- Trap-comments principle clarified: comments follow the *invariant
  owner*, not the call site. When extracting code, migrate trap
  comments into the new owner's API doc or into a regression-test
  name. Stale local comments at the old call site become misleading
  rather than informative. The original principle ("trap memory
  stays in code, not external docs") remains.

**Process note:**

The adversarial-pass technique — explicit prompt-level requirement
for failure modes with `(gesture → code path → user observation →
fix)` shape, minimum 2 findings per target, ban on consensus
phrasing and conclusion sections — produced 11 of 12 actionable
findings (only one was already-handled, and that was correctly
identified as such). This is the calibration baseline for future
rounds: ask for attack mode explicitly, constrain the output shape,
and the reviewer's AI on the other side will produce real value
instead of consensus mirroring.

### 0.42.4 — Hot-patch: built-in action ID sync (CuratedDefaults + metadata + icons)

A test run on a second machine surfaced a class of ID rename drift:
`DefaultTransformationSeed` was bumped to current IDs
(`builtin.json_keys`, `builtin.md_headings`, `builtin.md_links`)
but three companion side tables still referenced the legacy
`_extract_` IDs that no longer exist as seeds.

**Symptom:** `Extract Keys` and `Extract Headings` did not appear in
the default-enabled set on fresh installs (CuratedDefaults pointed at
non-existent action IDs); Settings rows rendered without descriptions
for the current actions and with `gearshape` fallback icons.

**Fix:**

- `CuratedDefaults.enabledByDefault` switched
  `builtin.json_extract_keys` → `builtin.json_keys` and
  `builtin.md_extract_headings` → `builtin.md_headings`. Fresh installs
  now enable both as intended.
- `BuiltinActionEditor.descriptions` gained entries for the current
  seed IDs (`builtin.json_keys`, `builtin.md_headings`,
  `builtin.md_links`). Legacy `_extract_` descriptions kept as
  aliases so users whose saved configs still carry the old IDs (or
  whose ActionTestSamples lookup paths use the alias) continue to
  see proper descriptions.
- `BuiltinActionIcons.symbolName` gained matching cases for the
  three current IDs; legacy cases kept.

Legacy aliases will be removed in a dedicated migration task at a
later date (the ID drift exists in real saved configs in the wild,
not just test fixtures).

### 0.42.3 — UX micro-fixes from the final UX/UI review

Three small UX touch-ups + one user-requested polish, all
applied immediately. The bigger UX recommendations from the same
review (#A63–#A69, plus Welcome refocus in #241) live in backlog.

- **HUD footer wording: `C save` and `esc cancel`** (`BigHUD.swift`).
  Was `C copy` and `esc close`. "Copy" read as system ⌘C and confused
  what the key does inside the HUD; "save" honestly describes the
  promote-preview-to-history-plus-pasteboard semantic. "Close"
  understated the cancel intent; "cancel" matches what esc actually
  does. Both modes (Gesture / Limited) get the new wording.
- **Settings action row — original title inline in grey when
  renamed** (`SettingsWindow.swift`). Was a second-line
  "default: <title>" subtitle that doubled the row's vertical
  footprint. Now an inline secondary-coloured title next to the
  user's custom title in the same row. The dim colour already reads
  as "the original", no `default:` prefix needed. User-requested
  polish on top of the colleague's title/description recommendation
  (the bigger split work lives in #A64).
- **HotkeyRecorder footer hint** (`HotkeyRecorder.swift`). Under the
  recorder field, when a hotkey is bound, a one-line caption now
  spells out the dual semantics: "Tap to run · hold ⌥⌘ to preview
  in HUD". Closes the in-product discovery gap for the per-action
  hotkey hold-preview feature — previously documented only in
  HELP.md and Welcome window. Part of #A67; the cheat-sheet half
  (per-action chord legend " — tap run, hold preview" suffix) is
  still queued.
- **Menu-bar tooltip reflects accumulator state** (`main.swift`
  status item). Was the static "DrPaste — clipboard history" at
  all times. Now updates dynamically: idle = unchanged; rich-text
  session active = "Append Copy: rich-text accumulator active
  (red). Press ⌥⌘S to add more, ⌥⌘V to paste."; files session
  active = "Append Copy: files accumulator active (cyan). Select
  more files and press ⌥⌘S to add." Hovering the menu-bar icon
  for a beat now answers "what does the coloured dot mean" without
  the user opening HELP.md. Part of #A60; the Settings → General
  "Append Copy" explanation row is still queued.

### 0.42.2 — Quick-wins from the code-review pass

Second pass over the same code-review session. Eight point patches —
each small, all correctness or performance wins:

- **Pasteboard polling timeout 0.25 s → 0.40 s + bundleID logging**
  (`PasteSimulator.simulateCopyAndAwaitChange`). Electron / Java /
  Office / Remote Desktop apps sometimes take 250–350 ms to fulfil a
  synthetic ⌘C; the earlier budget produced false "selection capture
  failed" outcomes on per-action hotkeys and Append Copy. Fast-path
  latency is unchanged (loop exits on the first `changeCount` tick).
  On timeout, the frontmost app's bundleID is now logged so problem
  apps are diagnosable.
- **Shared CIContext** (`ImageActions.swift`). Two filter sites built
  a fresh `CIContext` per call; CIContext init allocates GPU/Metal
  resources and loads shader caches. Switched to one static
  `sharedCIContext`. Faster image actions, especially when the user
  arrow-keys across several image actions in the HUD.
- **Safer AX bridge cast** (`ClipboardModel.swift` `SourceResolver.
  windowTitle`). Was `focusedWindow as! AXUIElement`. Replaced with a
  `CFGetTypeID(focused) == AXUIElementGetTypeID()` check + the bridge
  cast — if the platform ever returns a different CF type
  (private-frameworks, third-party AX shims, future macOS) the
  function returns nil instead of crashing.
- **Doc fix: clipboard index path.** Code uses `index.json`, docs said
  `clipboard.json`. Docs corrected; the path constant lives at
  `ClipboardStore.indexURL`, line 188 of ClipboardModel.swift.
- **Doc fix: fallback-only UserDefaults key.** Code uses
  `"drpaste.api_keys.use_fallback_only"`, docs said
  `"drpaste.fallbackOnly"`. Docs corrected; release-day Keychain
  migration (#A1) and any future Factory Reset key registry need the
  real string.
- **UsageProbe `Today` is local-day, not UTC** (`UsageProbe.swift`).
  Earlier comment claimed "midnight UTC"; the code uses
  `Calendar(identifier: .gregorian).startOfDay(for: Date())` which is
  the user's local-time midnight. Local-day is the more intuitive
  default ("today" matches the user's wall clock, not their region
  offset). Comment + code-level note brought into alignment; no
  behaviour change.
- **MiniHUD "Done · X.Xs" pill now also fires for image-AI**
  (`main.swift` `actionHotkeyDidFire`). The gate was `action is
  AIAction` only, which silently dropped the completion UX for image
  AI (`AIImageAction`) and text-to-image (`AITextToImageAction`) —
  exactly the actions with the longest perceived wait. Widened the
  gate to include both.
- **PasteboardWriter only declares readable types.** Earlier code
  declared every type in `typesOrdered` and silently skipped the
  `setData` call when the on-disk blob couldn't be read. Result:
  receiving apps that preferred the missing type over plain text got
  an empty paste. Now a two-pass write loads all blobs first,
  declares only the readable subset, and falls back to
  previewText/previewImage if every blob is missing. Missing blob
  count is NSLog'd for diagnostics.

### 0.42.1 — Hot-patch: Type Slowly via per-action hotkey

External code-review pass on the codebase surfaced a confirmed bug:
a per-action hotkey bound to Type Slowly committed the result as a
plain ⌘V paste instead of typing character-by-character. The action's
output (`ApplyOutcome.alternativeCommit(item, .typeSlowly(delay,
jitter))`) was being collapsed into `performStandardPaste(item, …)` by
the direct-trigger branch in `actionHotkeyDidFire(actionID:)` — line
997 of main.swift carried a wildcard pattern
`case .preview(let result), .alternativeCommit(let result, _)`. The
BigHUD commit path (`commitOutcome`) handled all three styles
correctly; the direct-trigger path did not.

Patched with explicit per-style branches mirroring `commitOutcome`. A
regression test is queued under #A45.

The same review surfaced six structural recommendations now in the
active backlog (#A39 unified pipeline, #A40 SelectionCaptureService,
#A41 import audit, #A42 surface state machines, #A43 PreferenceKeys
enum, #A44 ProviderResolver tighten-up, #A45 contract tests). #A39 is
the prevention layer for this class of bug — Type Slowly was caught
only because someone reviewed the direct-trigger code by hand; a
unified `PasteCommitter` would have made the bug structurally
impossible.

### 0.42.0 — Small-bug sweep + medium UX polish

Flight-test session ended with a 27-item idea / bug list. After a
follow-up discussion settling the design questions for each item,
27 new entries (#A12–#A38) landed in the active backlog. This release
ships the first eight: four small-bug fixes, four medium UX upgrades.
The larger user-visible features land in the next release.

**Small bugs (#A32, #A34, #A35, #A36):**

- **Unicode reverse table denormalize bug.** Applying `Plain (strip
  styling)` to a `𝐭𝐡𝐞 𝐪𝐮𝐢𝐜𝐤` Math Bold input returned `the bnick`
  instead of `the quick` — every `q` collapsed to `b`, every `u` to `n`,
  and so on. Root cause: `customReverse` was built from `upsideDownMap`,
  which contains self-swapping ASCII pairs (`b: q` plus `q: b`,
  `d: p` plus `p: d`, `n: u` plus `u: n`). The reverse map ended up
  with `reverse[q] = b`, `reverse[n] = u`, etc. — so any plain ASCII
  letter that fell through NFKC then got corrupted in the second pass.
  Filter added: skip entries whose `fancy` form is itself a plain ASCII
  glyph, keeping the reverse map to genuine non-ASCII keys only.
- **Save button in "+ New Built-in".** Picking a built-in handler in
  the "+ New" dialog and clicking Save sometimes felt like a no-op
  even though the descriptor was being touched: if the picked handler
  was disabled by curated defaults, the title-and-hotkey writes ran but
  the action stayed hidden, looking identical to "Save did nothing".
  `save()` now calls `registry.setEnabled(true, …)` on the
  `.createNew + .builtin` branch only — explicit user gesture
  ("I want this handler in my list") overrides the curated default
  for that one action.
- **Extract links / headings on Rich text.** Both engines walked
  `previewText`, which for a `.richText` clip is the rendered string
  with markup stripped — so headings and link URLs the user could
  clearly see in the formatting were invisible to the engine.
  `CustomTransformationAction.apply` now special-cases the two engines:
  when input is rich text, recover the markdown source via
  `RichTextHelpers.attributedStringToMarkdown(_:)` on the RTF/RTFD
  representation and feed that to the engine. `applicableTypes`
  widened from `[.markdown]` to `[.markdown, .text, .richText]`, with a
  one-shot migration (`expandMarkdownExtractTypesIfNeeded`) bumping
  existing installs that still have the legacy single-type set.
- **Built-in handler picker visibility audit.** Descriptor-backed
  bundled handlers (`builtin.md_to_plain`, `builtin.md_headings`,
  `builtin.md_links`, `builtin.cyrillic_translit`, the Unicode pseudo-
  font family) were filtered out of the "+ New Built-in" picker because
  they already had Settings rows. That produced an inconsistency: a
  user couldn't pick "Markdown → plain" or "Extract links" as a New
  Built-in even though they're in the Settings list. Filter removed —
  every `builtin.*` action is pickable, except the identity anchor.

**Medium UX upgrades (#A24, #A25, #A26, #A27):**

- **Markdown → Rich text action.** New `builtin.md_to_rich` action
  parses plain Markdown source (bold, italic, inline code, links) into
  an NSAttributedString and writes RTFD/RTF/HTML/plain reps to the
  pasteboard. Pastes into Mail / Pages / Notes / Word with formatting
  intact. Curated-on by default; appears in the Markdown category.
- **Unicode Fancy on markdown markup.** New
  `builtin.font_markdown` action interprets inline markdown markup as
  per-span style hints: `**bold**` → 𝐛𝐨𝐥𝐝 (Math Bold), `*italic*` →
  𝑖𝑡𝑎𝑙𝑖𝑐 (Math Italic), `***x***` → bold-italic, `` `code` `` →
  𝚌𝚘𝚍𝚎 (Math Monospace), `~~strike~~` → S̶t̶r̶i̶k̶e̶ (combining
  longstroke per char). Markup characters dropped from output. Plain
  text outside markup stays unstyled. Backed by a new
  `markdownAware` case in `UnicodeFontStyle` so the existing
  `unicodeStyle` engine drives it without a new engine type.
- **ASCII art: rich text + monospaced + tighter default width.** Output
  is now an NSAttributedString with `NSFont.monospacedSystemFont(11pt)`
  so the result pastes into Mail / Notes / Pages / Word with column
  alignment preserved. Plain-text targets still receive the bare
  string via `.string`. Default column count dropped from 100 → 40 —
  fits comfortably in chat messages, code comments, Twitter/X posts.
  The `render(image:outWidth:)` API now accepts a width parameter so
  #A16 (Built-in editor redesign) can surface a slider later.
- **Type Slowly: 1.5× faster + animated playground preview.**
  `defaultBaseDelay` dropped from 0.2 → 0.133 s/char (still slow
  enough to defeat input-field throttling, but 13 s for a 100-char
  paragraph instead of 20 s). TestOutputPane gets a new
  `TypeSlowlyPreview` view that animates the output character-by-
  character at the exact production delay, so the playground is
  bit-for-bit honest about real-world speed — no "2× faster for
  illustration" — and the user can dial the delay against perceived
  cadence before triggering against real input.

### 0.32.9 — Edit-button label + small-system fallback + Playground persistence

**Edit-button icon.** Pencil-only SF Symbol was opaque ("what is this
stick?"). Replaced with `Label("Edit", systemImage: "square.and.pencil")`
— same icon family Mail / Notes / Reminders use for their compose
buttons. Tooltip via `.help(...)` spells out what the editor exposes.

**Small system fallback image.** The previous fallback chain ended
at "user's desktop wallpaper" — typically a 5K-6K HEIC, slow to load
even after downscale. Replaced with a probe of `/Library/User Pictures/`
(Apple's stock account-avatar set, 80-512 px TIFFs / PNGs across
Photos / Animals / Nature / Flowers subfolders). First image found
wins. If User Pictures is absent (sandboxed install), the absolute
floor is now an SF Symbol (`photo.on.rectangle.angled`) rendered onto
a soft-blue 256×256 PNG. Always works, always small.

**Playground sample persistence.** Per-tab Sample input edits
(text for text tabs, dropped image for the Image tab) now persist
across app restarts via two new ActionConfig fields:

  - `playgroundSamples: [String: String]` — keyed by
    SemanticKind.rawValue, stores the user's edited text
  - `playgroundImageBlobs: [String: String]` — keyed by kind,
    stores the filename of a dropped image

Same diff-against-default normalisation as the per-action
`actionTestSamples` map (typing the curated text back in clears the
override, so future updates to the curated default propagate).
`ContentTypeTab.onAppear` loads the override before falling back to
`SettingsSamples.sample(for:)`; `.onChange(of: sampleText)` persists
text edits on every keystroke; image drops call
`registry.setPlaygroundImageRel`. Reset button clears the persisted
override AND the in-memory state.

Files:
  - `SettingsWindow.swift` — Edit button Label, onAppear /
    onChange persistence hooks, Reset behaviour, drop handler
  - `ActionConfig.swift` — `playgroundSamples` +
    `playgroundImageBlobs` fields + decoder + CodingKeys
  - `Actions.swift` — `playgroundSample(forKind:)` /
    `setPlaygroundSample` / `playgroundImageRel(forKind:)` /
    `setPlaygroundImageRel` registry helpers
  - `ActionTestSamples.swift` — `makeSystemWallpaperSampleItem`
    rewritten to scan `/Library/User Pictures/`; new
    `makeSFSymbolSampleItem` as absolute floor

### 0.32.8 — Edit button: `square.and.pencil` icon + "Edit" label

Cosmetic follow-up to 0.32.7. The bare text "Edit" button worked but
adding the canonical macOS edit glyph in front gives the row stronger
recognition without making the button wider — Label compose its icon
and text on one line.

Files: `SettingsWindow.swift`.

### 0.32.7 — Playground Sample input image-aware + Result HUD-style + Mandrill auto-download

Three things in one release.

**Playground Sample input for the Image tab now renders an actual
image** instead of placeholder text "(use Settings sample image when
ready)". Pulls the same `ActionTestSamples.makeSampleImageItem()`
chain the Edit Action sheet uses — bundled Mandrill → cached
Mandrill → User Pictures → SF Symbol. Drag-drop a different image
to replace, with the dropped picture copied into images dir under a
per-tab stable filename.

**Playground Result pane uses TestOutputPane** — the same
HUD-style component the Edit Action sheet renders. Identical
spinner / "Provider · Model · 4.2s" / failure-notice / image-preview /
rich-text-preview chrome everywhere. The legacy `ResultPane` struct
was deleted; one renderer for all preview surfaces.

**Mandrill auto-download.** First launch with no bundled or cached
Mandrill kicks off a background `Task.detached` that fetches
`https://sipi.usc.edu/database/preview/misc/4.2.03.png` (public
domain, 1973 USC-SIPI test image) and caches it at
`AppStorage.imagesDir/Mandrill-cached.png`. 10s timeout, atomic
write, NSImage validation before commit. Subsequent calls read from
the cache instantly. NSLock-guarded so concurrent dialog opens
don't fire twenty parallel downloads. Silent failure if SIPI is
unreachable — fallback chain takes over.

Files:
  - `SettingsWindow.swift` — image-aware leftColumn, TestOutputPane
    in Result, dead `ResultPane` removed, inflight chrome wiring
  - `ActionConfig.swift` — `SettingsSamples.sample(for: .image)`
    routes to `ActionTestSamples.makeSampleImageItem()`
  - `ActionTestSamples.swift` — `prefetchMandrillIfNeeded` +
    `makeCachedMandrillSampleItem` + USC-SIPI URL constant

### 0.32.6 — Bundled Mandrill resource lookup

Make `makeSampleImageItem()` look for `Mandrill.png` (or .jpg) in
`Bundle.module` before the procedural fallback. Lets a user drop the
classic USC-SIPI Mandrill test image into `Sources/DrPaste/Resources/`
once and have it shipped with future signed builds — no per-launch
download required. PNG fast-path (header sniff) skips needless re-
encode; everything else converts to PNG so downstream paths can
assume `public.png` representation uniformly.

Files: `ActionTestSamples.swift`.

### 0.32.5 — "Applies to" grid matches Playground tabs + procedural portrait

User: "Image / PDF / Files barely visible — disabled greying is
confusing; the checkboxes should match the Playground tabs exactly
and just mean 'enabled for this tab'."

**Centralised content-type list** — new `SemanticKind.userVisibleKinds`
returns the canonical Playground / Edit-Action tab order
(`text, richText, url, json, table, markdown, code, image, files`).
Both `SettingsWindow.visibleContentTypes` and
`ActionEditor.allTypes` now read from this single source so the two
surfaces can't drift.

**Dropped paternalistic greying.** Old `isTypeApplicable(_:)` probed
the action against synthetic items of each kind and disabled the
checkbox when the action couldn't handle that type. Removed — every
checkbox is freely toggleable now, and the user's deliberate choice
becomes the persisted state. Email and PDF are gone from the grid
(they have no Playground tab; classification still works internally).

**Procedural portrait sample image** (transitional, replaced in
0.32.7+ by Mandrill). 512×512 NSBezierPath drawing of a stylised
figure in a wide-brimmed hat — recognisable subject, rich colour,
embedded "DrPaste sample" text. Deliberately *not* Lenna (model
disavowed in 2019, banned from IEEE / Nature).

Files: `ClipboardModel.swift`, `SettingsWindow.swift`,
`ActionEditor.swift`, `ActionTestSamples.swift`.

### 0.32.4 — Preserve rich-text formatting for simple transformations

User: "Никакие простые преобразования текста не должны убивать
разметку текста."

`CustomTransformationAction.apply` flattened any rich-text input to
plain text (`item.previewText`) and ran the engine against that —
losing the user's bold / italic / colour / hyperlink markup. Fixed:

  - New `TransformationEngine.preservesRichTextFormatting: Bool`
    flag. True for character-local engines (`caseChange`,
    `unicodeStyle`, `cyrillicToLatin`) plus the special-handled
    `trim` and the boundary-adding `wrap` / `prepend` / `append`.
    False for engines that restructure text (sortLines, jsonFormat,
    slugify, camelCase / snake / kebab, base64, urlEncode, markdown
    extract, regex / findReplace — the last two could span runs).
  - New `TransformationRuntime.applyToAttributed(...)` dispatches
    per kind:
    * character-local → `applyPerRun` (enumerate attributes, run
      transformation on each substring, append with run's original
      attributes)
    * `trim` → NSString-based outer-whitespace strip preserving
      inner runs
    * `wrap` / `prepend` / `append` → plain prefix/suffix flanking
      the attributed original
  - `CustomTransformationAction.apply` checks
    `item.semantic == .richText && engine.preservesRichTextFormatting`,
    loads the RTF blob, calls `applyToAttributed`, returns through
    `makeRichTextItem` so the output stays a `.richText` clip.

Result: in the Playground Rich-text tab, "UPPERCASE" applied to a
sample with bold / italic / hyperlink turns letters uppercase while
keeping every formatting attribute intact.

Files: `CustomTransformation.swift`.

### 0.32.3 — Rich-text Input handling: markdown source + RTF round-trip

Rich-text built-in actions (`rich_to_wiki`, `rich_to_md`,
`rich_to_html`, `rich_to_unicode_style`, `paste_as_text`,
`clean_formatting`) all read `representations["public.rtf"]` to
extract the NSAttributedString. Plain-text input from a TextEditor
left them with nothing to convert.

Fixed: when the action being tested is rich-text-only (probed via
new `registry.actionRequiresRichText(_:)`), `runTest` parses the
testInput markdown via `NSAttributedString(markdown:)`, writes an
RTF blob to `AppStorage.blobsDir`, and builds the inputItem with
`semantic: .richText` and `representations["public.rtf"]`. The
action's `.apply` now has real rich content to convert.

Per-action illustrative samples updated: each rich-text action
ships with a sample showing exactly the inline elements its target
format renders (`**bold**` → `'''bold'''` for wiki, → `<strong>`
for HTML, etc.).

Files: `ActionTestSamples.swift`, `Actions.swift`, `ActionEditor.swift`.

### 0.32.2 — Image-aware Edit Action Input field + drag-drop persistence

Image-applicable actions (OCR / Grayscale / Rotate / AI image
styles / …) now render an actual image preview in the Input panel
instead of placeholder text. New file-drop target replaces the
sample with the user's picture; drops persist via new
`ActionConfig.actionTestImageBlobs: [String: String]` (keyed by
action ID, value is a rel filename inside `AppStorage.imagesDir`).

`registry.actionAcceptsImage(_:)` probes each action's
`isApplicable` against a synthetic `.image` clip so any new image
action (third-party plug-in, future built-in) automatically gets
the image input UI without us updating a whitelist.

Reset button next to the Input label appears when an override
exists; clears the persisted blob and regenerates the procedural
sample.

Files: `ActionConfig.swift`, `Actions.swift`, `ActionEditor.swift`,
`ActionTestSamples.swift`.

### 0.32.1 — Test sample persistence + full action coverage + HUD-style Output

**Persistence.** New `actionTestSamples: [String: String]` field in
ActionConfig stores per-action testInput overrides. Edit Action
dialog loads override → curated default → empty. Save persists when
modified this session, normalises against curated default so typing
the curated text back in clears the override. Empty string IS
persisted as "user explicitly cleared this".

**Full action coverage.** `ActionTestSamples.textSample(for:)`
extended from 30 to 50+ entries — covers every bundled built-in
plus seeded user.* actions. Each sample is curated to illustrate
its specific action's effect: translate gets an English greeting,
JSON minify gets pretty-printed JSON to compress, layout repair
gets Russian phrase typed with English keyboard, etc.

**HUD-style Output pane.** New `TestOutputPane` View (file
`TestOutputPane.swift`) renders `ApplyOutcome` with the same chrome
as BigHUD: spinner with "Provider · Model · 4.2s" capsule for AI
actions, failure notice with orange ⚠ + reason, side-effect notice,
image preview via `ImagePreview`, rich-text preview via
`RichTextPreviewView`. Replaces the legacy plain-text TextEditor
mirror — no more flat text strings flattening image results.

Files: `ActionConfig.swift`, `Actions.swift`, `ActionEditor.swift`,
`ActionTestSamples.swift`, `TestOutputPane.swift` (new).

### 0.32.0 polish — Edit dialog routes image actions correctly + test sample pre-population

Two follow-ups after first 0.32.0 user test:

**Bug 1 — image actions opened as "Built-in" instead of "AI".**

`SettingsWindow.openEditor` used `if action is AIAction` to route the
pencil button to `.editAI(desc)`. Because `AIImageAction` is its own
struct (not a subclass of `AIAction`), the check missed it and the
action fell through to the `.editBuiltin` arm. Result: the dialog
displayed "Edit Built-in Action" with a locked handler field instead
of the editable prompt + provider picker. Fix: route any action whose
ID is in `registry.config.customAI` to `.editAI(desc)` regardless of
the concrete action type. Now AIAction (text) and AIImageAction
(image) both surface in the same editor — same prompt textarea, same
provider picker, same hotkey field, same save flow (which already
preserves `desc.kind` from the 0.32.0 rework).

**Feature — per-action test samples in the Edit dialog.**

User request from before the regression chase: every action should
ship with an illustrative sample pre-populated in the Test panel so
clicking "Run test" immediately demonstrates what the action does.
New file `ActionTestSamples.swift` carries a curated map of
action-id → sample text covering all bundled actions:

  - Translate → English sentence
  - Fix grammar → typo-riddled snippet
  - Formal tone → casual chat message
  - Summarize → multi-sentence paragraph
  - Case actions → "The quick brown fox jumps over the lazy dog."
  - camelCase / snake_case / kebab-case → "user account email address"
  - Trim → string with leading/trailing whitespace
  - Sort / unique lines → multi-line fruit list with duplicates
  - Base64 encode/decode → matching round-trip pair
  - URL encode/decode → realistic search URL
  - JSON actions → minified JSON with nested object + array
  - Code wrap / tabs↔spaces → tiny Swift function
  - Markdown actions → headings + bold + italic + links
  - URL strip-tracking → URL with utm_*, fbclid, etc.
  - Layout repair → Russian phrase typed with English layout
  - Cyrillic transliterate → Russian sentence
  - Unicode pseudo-fonts → mixed-case alphabet + digits
  - Plain ASCII (font_plain) → stylized text to flatten
  - Tables → CSV with header + 3 rows
  - Rich-text actions → demonstrative sentence
  - AI image styles → placeholder note ("Run test will use a
    generated sample image"), with the actual sample being a 512×512
    procedural PNG (gradient sky + mountain silhouette + DrPaste
    wordmark) generated at runtime in `ActionEditor.runTest`

`ActionEditor.loadInitialState` pre-fills `testInput` from
`ActionTestSamples.textSample(for: id)` whenever the action being
edited has a registered sample. Unknown IDs (third-party user-added
descriptors) keep the empty default.

`ActionEditor.runTest` detects image descriptors (`context` is
`.editAI(desc)` with `desc.kind == .image`), generates the sample
image via `ActionTestSamples.makeSampleImageItem()`, runs the
descriptor's prompt through `AIImageAction.apply`, and surfaces the
result through a new `describeImageOutcome` helper that reports the
generated PNG's dimensions + file size and points the user at the
BigHUD preview for the actual visual result. Test panel itself stays
text-only for now — inline NSImage preview is a follow-up if users
ask for it.

Files:
  - `ActionTestSamples.swift` — new (~250 lines): textSample table +
    procedural makeSampleImageItem
  - `ActionEditor.swift` — `loadInitialState` pre-fills testInput;
    `runTest` branches on descriptor.kind for image path;
    `describeImageOutcome` helper
  - `SettingsWindow.swift` — `openEditor` routes by customAI
    membership instead of concrete type, fixes image-action dialog
    opening as Built-in

### 0.32.0 — AI image transformations (Sketch / Watercolor / Cartoon)

User request: at least 2-3 AI image transformations like "pencil sketch
in the style of Sketch". User picked: 3 styles to ship initially, route
through the *default* AI provider (transparent to the user), surface in
HUD preview pane as regular AI actions.

**Unified architecture — text + image AI share one descriptor**

First-cut implementation (a discarded draft) hardcoded the 3 styles as
`builtin.ai_image_*` actions in a dedicated `AIImageActionsPack`. User
flagged the inconsistency: text AI actions (Translate, Fix grammar, …)
are seeded as editable `CustomAIDescriptor` entries with `user.*` IDs,
visible in Settings → Actions → AI with a prompt textarea and a
per-action provider picker. Image styles should follow the same
philosophy so the user can:

  - Edit the prompt to taste ("make the sketch darker", "add a sepia
    tint to the watercolor", …)
  - Switch the per-action provider (default vs explicit)
  - Rename the action
  - Clone any seeded style into their own ("Stained glass", "Oil paint",
    "1990s anime") by editing prompt + giving the descriptor a new id

**What ships**

`CustomAIDescriptor` grows a `kind: Kind` enum field with cases `.text`
and `.image`. Decodes default to `.text` so pre-0.32.0 `actions.json`
files load unchanged. Three new descriptors land via
`DefaultAISeed.defaults()` (currentSeedVersion bumped 2 → 3):

  - `user.ai_image_sketch` — "AI: Pencil sketch"
  - `user.ai_image_watercolor` — "AI: Watercolor"
  - `user.ai_image_cartoon` — "AI: Cartoon"

All three appear in Settings → Actions → AI alongside Translate /
Summarize / Fix grammar, fully editable through the existing AI editor.
Existing users on 0.31.x get them appended on next launch via the
standard seed-version migration; brand-new installs get them at first
launch.

**Materialisation**

`ActionRegistry.rebuildCustomAI` switches on `desc.kind`:
  - `.text` → instantiates an `AIAction` (existing path, unchanged)
  - `.image` → instantiates an `AIImageAction`

Both action types share the same `(id, title, promptTemplate,
providerID)` shape so the Settings editor doesn't need a kind-specific
form — image entries reuse the same prompt textarea and provider
picker the user already knows from Translate.

**AIImageAction shape**

`isLocal == false` puts it on the same code path as text `AIAction` in
`main.swift / refreshPreview`: HUD shows the in-flight panel
(provider · model · elapsed), `aiStreamingTask` drives cancellation,
deferred-paste handoff on ⌥⌘ release works the same way. The image
API doesn't stream tokens, so `applyStreaming` falls back to `apply`;
the only "stream" is the elapsed counter ticking up.

`isApplicable` is hardcoded to image clips (`context.contains(.image)`
or rich-text with embedded image) regardless of what the descriptor's
`applicableTypes` lists. Storing `applicableTypes = ["image"]` in the
descriptor keeps the Codable shape uniform; the value is informational
for `.image` entries.

**Provider routing — v1 scope**

`AIImageAction.resolveProvider`:
  1. If `providerID` is set → that explicit provider.
  2. Else → registry's `defaultProvider`.
  3. Validate the resolved provider's `.kind == .openai` (currently
     the only kind whose endpoint exposes `/v1/images/edits`).
  4. Validate API key present in Keychain/fallback.

Failure at any step returns a clear `ApplyOutcome.failed` recommending
the user add an OpenAI key. Future expansion (per-kind routing for
Gemini 2.5 Flash Image, Replicate's Flux/SDXL via OpenRouter
multimodal, etc.) is a one-place switch on `cp.kind`.

**HTTP**

`AIImageHTTP.runEdit` performs the actual multipart POST to
`https://api.openai.com/v1/images/edits` with `model=gpt-image-1`,
`size=1024x1024`, `n=1`, the source PNG as the `image` field, and the
descriptor's `promptTemplate` as the `prompt` field. Handles both
`b64_json` and `url` response shapes. 90 s timeout, 4 MB source cap.

**Cost**

gpt-image-1 at 1024×1024 standard quality is ~$0.04/image. Pinned at
n=1 and 1024×1024 (cheapest tier) so the per-call cost is predictable.
Source images over 4 MB fail with a "chain Compress JPEG or Resize
1920" message rather than handing the user an HTTP 413.

**Runway of additional styles**

The user can now add any of these themselves via the Settings AI
editor (clone an existing image descriptor, edit the prompt, give it
a new id). For the seed table we'd add similar `user.*` entries in
`DefaultAISeed.defaults()` and bump `currentSeedVersion` again:

  - Oil painting — visible brush texture, rich color depth
  - Pixel art — 16-bit / 8-bit retro grid look
  - Pop art (Warhol) — high-contrast duotone color blocks
  - Line drawing / coloring book — clean outlines, blank fills
  - Blueprint — white-on-blue technical drawing aesthetic
  - Anime / manga — flat shading, distinctive eye treatment
  - Charcoal — heavy smudge, dramatic high contrast
  - Stained glass — black leading + jewel-tone panels
  - Sticker — die-cut white border around isolated subject
  - Vintage photo — sepia tone + period grain
  - Caricature — exaggerated proportions
  - Background removal — transparent PNG (mask workflow, separate
    endpoint variant)

Files:
  - `ActionConfig.swift` — `CustomAIDescriptor.Kind` enum + decode default
  - `Actions.swift` — `rebuildCustomAI` switches on `desc.kind`
  - `AIProvider.swift` — `DefaultAISeed.defaults()` adds 3 image entries,
    `currentSeedVersion` 2 → 3
  - `AIImageActions.swift` — new (`AIImageAction` + `AIImageHTTP`)
  - `main.swift` — removed `registry.register(AIImageActionsPack.all)`;
    image actions now flow through `rebuildCustomAI`
  - `CuratedDefaults.swift` — removed 3 `builtin.ai_image_*` entries
    (they're customAI descriptors now, governed by their own `enabled` field)
  - `AppBrand.swift` — version bump 0.31.1 → 0.32.0

### 0.31.1 — HUD overlap regression: spinner-forever + two surfaces (region-capture stacking)

User reported the 0.31.0 fix was incomplete. Symptoms with fast tap-
and-release of a per-action hotkey: sometimes 2 HUDs visible at once,
MiniHUD spinner keeps spinning indefinitely while the request
"continues in the background".

Root cause that 0.31.0 missed: the region-capture arm guard in
`armRegionCapture()` checked `bigHUDPanel?.isVisible`,
`pendingDeferredPasteApp`, and `aiStreamingTask` — but not
`actionHotkeyTask`. The direct-trigger MiniHUD lives off
`actionHotkeyTask`, not `aiStreamingTask`. So a fast ⌥⌘+letter tap
(MiniHUD up, AI streaming on `actionHotkeyTask`) followed by bare ⌥⌘
held alone for 400 ms would arm region capture, putting the cursor
overlay + cheat sheet on screen *next to* the still-spinning MiniHUD.
Two unrelated surfaces, AI continuing in the background, exactly what
the user described.

Defensive sweep, single commit:

1. **Region-capture arm guard expanded.** `actionHotkeyTask`,
   `bigHUDOpenTask`, and `MiniHUDController.shared.isVisible` are
   now also checked. Any in-flight DrPaste state blocks region-
   capture arm. Mutually exclusive surfaces by construction.
2. **`bigHUDOpenTask` tracked.** The inner `Task { @MainActor in }`
   inside `openBigHUDFocusedOnAction` was previously fire-and-forget
   — rapid hold-preview fires could stack two parallel `simulateCopy`
   polls racing to set `bigHUDState.actionIndex`. Now tracked,
   cancelled before starting a new one, cleared on every exit path
   plus an extra `Task.isCancelled` check after the await.
3. **`openHUD`, `openBigHUDFocusedOnAction`, and
   `openBigHUDFocusedOnCapturedImage` all do the same teardown
   prologue.** Cancel `actionHotkeyTask`, `bigHUDOpenTask`,
   `aiStreamingTask`, clear `pendingDeferredPasteApp`, hide MiniHUD.
   Previously each path did a slightly different subset — region
   capture's "open BigHUD on captured image" did none of it.
4. **`closeBigHUD` clears `pendingDeferredPasteApp` + hides
   MiniHUD.** Belt-and-braces: when BigHUD closes, no MiniHUD should
   be left on screen. A late-arriving deferred-paste completion
   handler used to be able to fire a paste behind the user's back
   after they'd cancelled the BigHUD.
5. **`MiniHUDController` gets generation tokens.** New
   `ShowToken`-returning `show()` plus `hideIfOwner(_:)`. The
   direct-trigger task captures the token at show time and uses it
   on every cancellation branch so a cancelled task doesn't
   accidentally hide a *successor's* MiniHUD (rapid same-hotkey
   tap-tap: task N's MiniHUD replaced by task N+1's before task N
   reaches its cancellation point).
6. **`actionHotkeyDidFire` always hides MiniHUD on cancel
   branches.** Previously the two `if Task.isCancelled { return }`
   bailouts left MiniHUD on screen, trusting the caller to hide it.
   With the token in hand, the task can do this safely without
   nuking a replacement.

Files:
  - `main.swift` — guards, task tracking, prologue refactor in 3
    BigHUD open paths, `closeBigHUD` hardening
  - `MiniHUD.swift` — `ShowToken` + `hideIfOwner(_:)` + `isVisible`
  - `AppBrand.swift` — version bump 0.31.0 → 0.31.1

### 0.31.0 — HUD overlap + stranded BigHUD + in-flight action cancellation

User report: in heavy AI flows ("⌥⌘ hold → hotkey → ⌥⌘ release"
sequence), sometimes BOTH the MiniHUD and the BigHUD were visible
at the same time, on top of each other.

Three distinct bugs piled on top of each other.

**Bug 1 — MiniHUD + BigHUD visible simultaneously**

Direct-trigger AI flow: user fires ⌥⌘T (per-action hotkey). MiniHUD
shows action title + provider · model · elapsed. AI takes ~5 s.
User, impatient, hits ⌥⌘V meanwhile to browse history. BigHUD
opens — but the MiniHUD is still showing because no one taught
`openHUD` / `openBigHUDFocusedOnAction` to hide it.

Fix — both BigHUD-opening paths now call
`MiniHUDController.shared.hide()` at the start.

**Bug 2 — in-flight direct-trigger action keeps running after user moved on**

Same scenario as bug 1: AI is mid-stream when user opens BigHUD.
We hide the MiniHUD (fix 1), but the underlying `Task` running
`action.apply` keeps going. Eventually completes and fires
`performStandardPaste(result, savedApp: frontmost)` against the
app that was frontmost when the user originally pressed ⌥⌘T —
which is probably no longer where the user is. Surprise paste,
possibly into the wrong context.

Fix — track the direct-trigger task as a new
`actionHotkeyTask: Task<Void, Never>?` field on AppDelegate.
Cancelled by every BigHUD-opening path (`openHUD`,
`openBigHUDFocusedOnAction`), by `closeBigHUD`, and by re-entry
into `actionHotkeyDidFire` itself. `Task.isCancelled` checked
twice inside the task — after `simulateCopyAndAwaitChange`
returns, and after `action.apply` returns — so we don't paste
results from a cancelled run.

**Bug 3 — stranded BigHUD when ⌥⌘ released mid-poll**

`openBigHUDFocusedOnAction` does a selection-first ⌘C dance via
`PasteSimulator.simulateCopyAndAwaitChange` (up to 250 ms). If the
user releases ⌥⌘ during that window, the engine's
`flagsChanged → hotkeyEngineDidRelease → commitBigHUD` chain ran
on a still-empty `bigHUDState`, found nothing to commit, called
`closeBigHUD` (no-op since the panel wasn't shown yet), and reset
`bigHUDIsActive = false`. Meanwhile our `Task` continued
unaware, eventually calling `showBigHUD()` — the panel appeared
"after the train left", with no user gesture holding it. User
had to dismiss with Esc.

Fix — after the `await` in the open task, check
`(engine as? EventTapEngine)?.isHudActive`. If the engine no
longer thinks the HUD should be active (because the user
released), bail out before showing.

**Why these compound**

Heavy actions (AI streaming, large image filters) widen every
async window in the gesture pipeline. The faster the AI, the
narrower the race; the slower the AI, the more reliably users
hit these bugs. That's why the report came in as "глючит на
тяжёлых вещах" — light actions complete before the race
windows open.

### 0.30.2 — Compile fix for 0.30.1 (`Result<String, String>` → local enum)

0.30.1 didn't compile. The `OCR` and `Decode QR` actions used
`Result<String, String>` as the off-main return type, but Swift's
`Result<Success, Failure>` requires `Failure: Error` and `String`
doesn't conform. Replaced both sites with a small local `Sendable`
enum (`OCROutcome` / `QROutcome`) — same pattern already used by
`ImageResize1920Action.ResizeResult` in 0.30.1. Other 8 image
actions weren't affected (they returned `Optional<ClipboardItem>`
or plain `String`).

Pure compile fix — no functional change vs the intent of 0.30.1.

### 0.30.1 — Image actions no longer freeze the HUD (main-actor unblock + spinner)

User report: image actions (Grayscale, Rotate right, Rotate left, …)
behaved unreliably in the HUD preview pane — sometimes the rotated
image showed, more often it didn't, and the panel felt frozen
("жутко глючит"). Two distinct bugs compounding each other.

**Bug 1 — image actions blocked main thread**

Every image action's `apply(item:context:)` is declared `async` but
the body had no `await` calls inside. `CIFilter` render,
`VNRecognizeTextRequest.perform`, `NSBitmapImageRep.representation`
— all of those run synchronously. With Swift Concurrency, an
`async` function with no internal `await` runs synchronously on
the calling actor. The caller in `refreshPreview` is
`Task { @MainActor in let outcome = await action.apply(...) }` —
so `apply` runs on the main actor, freezing the UI for the
100–500 ms a transformation needs on a typical full-resolution
clip. Hence "frozen / glitchy".

Fixed by routing every image action's heavy work through a new
`runOffMain` helper in `ImageActions.swift`:

```swift
private func runOffMain<T: Sendable>(
    _ work: @Sendable @escaping () -> T
) async -> T {
    await Task.detached(priority: .userInitiated, operation: work).value
}
```

`NSImage` / `CIFilter` / `VNImageRequestHandler` references stay
inside the closure (never escape the detached task), only
`Sendable` results (`ClipboardItem`, `String`, custom enums) come
back across the actor boundary. All 10 image actions refactored:
OCR, Decode QR, Grayscale, Invert, Rotate Right, Rotate Left,
Resize 1920px, Compress JPEG 80%, Strip metadata, ASCII art.

**Bug 2 — no loading state for local actions in HUD preview**

`refreshPreview` set `isPreviewLoading = true` for AI (remote)
actions but skipped it for `action.isLocal == true` — local
actions were assumed to be instant. When they're not (image
filters), the user stared at the PREVIOUS action's preview
output for the full 100–500 ms the new transformation took,
then it snapped to the new result. Looked like "the rotation
flickered briefly".

Fixed: local actions now set `isPreviewLoading = true`
immediately before kicking off the work task; the existing
spinner panel ("processing…") shows while we compute, then
clears the moment the result lands. Consistent visual model
with the AI path.

**Local task cancellation on navigation**

While inspecting the code I also noticed local previews were
fire-and-forget — `Task { @MainActor in … }` with no handle to
cancel. Fast navigation between image actions queued multiple
background renders (Grayscale, then Rotate before Grayscale
finished, then Rotate-Left before Rotate finished — three
concurrent CIFilter renders on a 4K image). Token guarding
prevented stale results from overwriting the latest outcome,
but the wasted CPU still slowed everything down. Now tracked
via `localPreviewTask: Task<Void, Never>?` and cancelled on
every `refreshPreview` call and inside `closeBigHUD`.

**Files changed**

  - `ImageActions.swift` — `runOffMain` helper + 10 action sites
    refactored
  - `main.swift` — `localPreviewTask` field, set
    `isPreviewLoading = true` for local actions, cancel on
    navigation / close
  - `AppBrand.swift` — version bump 0.30.0 → 0.30.1
  - `BACKLOG.md` — this entry

### 0.30.0 — Audit pass + alpha milestone (DRY refactor + cleanups)

Milestone alpha bump (jumping past 0.29 because the work doesn't
need its own version). End-of-arc cleanup after the 0.24–0.28 sprint
of features and bug-hunts, before resuming forward work on the
hosted-AI backend and MAS submission prep.

**DRY refactor — `PasteSimulator.simulateCopyAndAwaitChange`**

The "simulate ⌘C + poll pasteboard for change" pattern was inlined
in four places after the selection-first hotkey work landed in
0.22.0:

  - `actionHotkeyDidFire` (per-action direct trigger)
  - `openBigHUDFocusedOnAction` (per-action hold-preview)
  - `hotkeyEngineDidAppendCopy` (⌥⌘S Append Copy)
  - `hotkeyEngineDidQuickCopy` (⌥⌘C Quick Copy — used the older
    DispatchQueue.main.asyncAfter pattern, slightly different)

Each site had its own `Task.sleep` loop, its own 250 ms / 150 ms
constant, and its own change-detection guard. Four near-identical
copies of timing-critical code = four places to update when the
timing model changes, four chances for one to drift.

Extracted into a single static helper on `PasteSimulator`:

```swift
@MainActor
static func simulateCopyAndAwaitChange(timeout: TimeInterval = 0.25)
    async -> Bool
```

Returns `true` if the pasteboard refreshed within the timeout,
`false` on timeout. All four call sites refactored to use it.
Quick Copy is now consistent with the others (was 150 ms, now
250 ms uniformly — slightly more compatible with slow apps).

**Cleanups**

  - Removed `AppTheme.hudBackgroundTint` — deprecated stub left
    over from the 0.27.0 gradient migration, returned `.clear` for
    every theme and was never called from anywhere. Searched the
    full source tree to confirm zero references before deleting.
  - Tightened doc comments throughout the modified files to
    reflect the final architecture (cursor overlay note no longer
    says "three iterations of trying" — that history lives in the
    changelog, not in the source).
  - Inline `pb` variable hoisting consolidated to the smallest
    scope it's used in each call site.

**Forced-unwrap / `try!` / `as!` audit**

Inventoried every `try!`, `as!`, and `fatalError` in the source
tree:

  - `main.swift:20` — `var registry: ActionRegistry!` — implicitly
    unwrapped optional initialised in `applicationDidFinishLaunching`
    before first use. Standard AppDelegate pattern, safe.
  - `ClipboardModel.swift:119` — `try! fm.url(for: .applicationSupportDirectory)`
    — could theoretically fail if the user has a corrupted home
    directory, but if that's the case DrPaste can't function
    anyway. Acceptable.
  - `ClipboardModel.swift:349` — `as! AXUIElement` — required by
    the AX C API which returns `CFTypeRef`. Standard pattern.
  - `ScreenRegionCapture.swift:421, 704` /
    `AboutWindow.swift:34` — `fatalError` inside `required init?(coder:)`
    on programmatically-created views that never come from a NIB.
    Standard SwiftUI / AppKit pattern.

All five are documented, justified, and unchanged. No new ones
introduced in this audit pass.

**TODO / FIXME / HACK audit**

`grep -E "TODO|FIXME|XXX|HACK"` across `Sources/DrPaste/` returns
zero matches. We're clean.

**Files changed in this version**

  - `PasteSimulator.swift` — added `simulateCopyAndAwaitChange`
  - `main.swift` — four call sites refactored to use the helper
  - `AppTheme.swift` — removed deprecated `hudBackgroundTint` stub
  - `AppBrand.swift` — version bump 0.28.1 → 0.30.0
  - `BACKLOG.md` — this entry

### 0.28.1 — Per-provider icons in Add provider sheet

Polish. The Add provider sheet was rendering every cloud kind with
the same generic `cloud` SF Symbol and every local kind with
`desktopcomputer` — a column of identical glyphs that gave no
visual identity cues. Each `ProviderKind` already exposes
`iconName` (per-kind SF Symbol) and `brandColor` (signature hue),
both of which the HUD action chips have been using since 0.9.0;
the picker just wasn't reading them.

Fix: `kindRow` now renders each provider's actual icon glyph
inside a 26 pt circle filled with the brand colour at 16 % opacity,
foreground colour set to the brand hue at full saturation. The
picker now reads as a row of distinct brands instead of a column
of identical clouds — same visual language as the HUD, easier to
scan when there are 14 providers across 5 sections.

### 0.28.0 — Four new AI providers + Ocean theme + thumbnail polish + suggested-models layout fix

Big-ish release combining four loosely related changes that all
landed together.

**Four new AI providers — Together AI, Cloudflare Workers AI, Groq, Cerebras**

  - **Together AI** (https://together.ai) — second major aggregator
    after OpenRouter, especially strong for open-source models
    (Llama, Mistral, Qwen, DeepSeek). OpenAI-compatible base URL
    `https://api.together.xyz/v1`. Default model
    `meta-llama/Llama-3.3-70B-Instruct-Turbo`. Brand color: deep
    navy (`#1F40C7`). Icon: `network` glyph.
  - **Cloudflare Workers AI** (https://developers.cloudflare.com/workers-ai)
    — Cloudflare's own inference hosted on their edge network.
    Cheap, OpenAI-compatible, free tier. Catch: the base URL bakes
    the account ID in (`https://api.cloudflare.com/client/v4/accounts/<ID>/ai/v1`),
    so we mark `requiresBaseURL` and seed the placeholder
    `YOUR_ACCOUNT_ID` for the user to replace. Default model
    `@cf/meta/llama-3.1-8b-instruct`. Brand color: Cloudflare
    orange (`#F58020`). Icon: `cloud.bolt.fill` (cloud platform +
    fast inference).
  - **Groq** (https://groq.com) — custom LPU hardware, ultra-fast
    Llama / Mixtral / Gemma inference, generous free tier.
    OpenAI-compatible base URL `https://api.groq.com/openai/v1`.
    Default model `llama-3.3-70b-versatile`. Brand color: red.
    Icon: `bolt.fill`.
  - **Cerebras** (https://inference.cerebras.ai) — wafer-scale
    chips, even faster than Groq on Llama 3.3 70B (1000+ tokens/sec).
    OpenAI-compatible base URL `https://api.cerebras.ai/v1`. Default
    model `llama3.3-70b`. Brand color: magenta-purple. Icon:
    `gauge.with.dots.needle.67percent` (speedometer).

**UI: merged Gateway + new "Fast inference" section**

`ProviderAddSheet` reorganised to reflect the new categorisation:

```
Cloud
  Anthropic, OpenAI, Gemini, Grok, Mistral, DeepSeek
Gateway              ← OpenRouter + Together + Cloudflare Workers AI
                       (one account, many models — same UX shape)
Fast inference        ← Groq + Cerebras (specialised hardware)
Local
  Ollama, LM Studio, llama.cpp
Other
  Custom
```

Previously I had Cloudflare Workers AI as its own "Cloud platform"
section. User correctly pointed out that Cloud platform and Gateway
are conceptually the same — one auth, many models. Merged.

**Ocean — sixth theme, bright tropical palette**

Vivid (warm, dark base) and Soft (warm, pastel) are both warm-spectrum.
The new Ocean theme fills the cool-spectrum chromatic gap with a
deliberately distinct identity:

  - Background gradient — bright cyan top (`#11A6C7`) → deep teal
    bottom (`#085277`), ~86 % opacity over the system blur.
    Reads as "tropical lagoon" / "Mediterranean afternoon".
  - Accent — hot coral (`#FF6B5C`) for selection rings, chips,
    hover. Warm color on cool base = high chromatic contrast,
    high attention pull.
  - Accumulator highlight — golden yellow (`#FFD933`) for the
    ⌥⌘S carrier stripe. Third hue rotates around the colour
    wheel so the palette feels playful, not monotone.
  - Border — turquoise (`#00C7CC`) at 65 % opacity, 1.5 pt
    matching the Vivid / Soft thicker border style.

**Suggested-models layout fix in ProviderEditor**

User report: OpenRouter / Together model slugs like
`anthropic/claude-sonnet-4.5` and
`meta-llama/Llama-3.3-70B-Instruct-Turbo` rendered as hideous
mid-word-wrapped columns in the suggested-models list because the
old layout was a fixed-grid HStack with each chip squashed into
~70 pt fixed width. SwiftUI's text wrapping mangled the slugs into
"an-/thropic/-/claude-/-sonnet-/-4.5" — readable as hieroglyphs only.

Switched to a horizontally-scrolling row of capsule chips. Each chip
stays on one line at its natural width (`.fixedSize()`), the row
scrolls right if total exceeds the dialog. User sees the full slug
they're clicking, picks by skim instead of decoding word wraps.

**Thumbnail picker shrunk to fit six themes**

Six themes (Auto / Light / Dark / Vivid / Soft / Ocean) at the
previous 110 × 70 thumbnail size + 14 pt spacing = 730 pt, well
over the Settings tab content width (~580 pt). Shrunk to 78 × 52
with 8 pt spacing — fits at ~508 pt with breathing room. Inner
mini-HUD content (header dots, row capsules, action chips) also
scaled to ~0.6× so the mini-HUD still reads correctly at the
smaller frame. Picker wrapped in horizontal `ScrollView` so
future theme additions don't re-fight the layout.

### 0.27.1 — OpenRouter actually appears in "Add provider" sheet

Embarrassing follow-up to 0.26.0. I added OpenRouter to the
`ProviderKind` enum and wired it through every metadata switch +
the runtime factory — but the Settings → AI Providers → "Add
provider…" sheet hardcodes its menu from a manually-maintained
literal array. New providers must be added to that array OR they
literally cannot be picked from the UI no matter how complete the
backing code is.

`ProviderAddSheet.body` had the Cloud list as
`[.anthropic, .openai, .gemini, .grok, .mistral, .deepseek]` —
no `.openrouter` anywhere. So even though `defaultBaseURL`,
`apiKeyDocsURL`, `makeConcrete`, and the rest of the metadata
were live, users couldn't reach the configuration sheet.

**Fix**

Added a new "Gateway" section header between Cloud and Local
with `.openrouter` as its only entry. Separating it out (rather
than tucking it under Cloud) makes the value prop visible — users
understand "this isn't a direct vendor account, it's an
aggregator". Future aggregators (Together AI, Replicate, Fireworks,
…) slot under the same header without re-cluttering Cloud.

### 0.27.0 — Vivid / Soft themes now actually look distinct from Dark / Light

User feedback after 0.25.1: Vivid and Soft barely differed from Dark
and Light. Root cause was that my tint layer ran at 30–35 % opacity
on top of the system VisualEffect blur, which kept the system blur
dominant. Net result: Vivid = "Dark with a faint orange wash";
Soft = "Light with a faint pastel wash". Not the strong identity
those tiers were supposed to deliver.

**Three changes that together make the themes pop**

  1. **Replace single-color tints with vertical LinearGradients**
     at much higher opacity. `ThemeBackgroundFill` (new SwiftUI
     view) returns:
     - Vivid — deep indigo (#150340) → plum (#392033) gradient at
       85–92 % opacity. System blur is barely visible underneath
       — the theme owns the surface.
     - Soft  — warm cream (#FFF5F0) → pale lavender (#F0EAFD)
       gradient at 78–82 % opacity. Same domination, much lighter
       palette.
  2. **Theme-aware borders.** New `hudBorderColor` and
     `hudBorderWidth` properties on `AppTheme`. Auto/Light/Dark
     get the existing hairline `Color.primary.opacity(0.08)` at
     0.5 pt — invisible-by-design. Vivid gets a 1.5 pt accent-
     orange frame at 60 % opacity (`#FF8019`); Soft gets a 1.5 pt
     dusty-rose frame at 45 % (`#D16AA6`). The edge framing alone
     makes the theme readable from across the room.
  3. **Beefier accent palette.** Vivid orange went from `#FF6B36`
     to `#FF8019` (more saturated, more "electric"). Vivid
     accumulator green went from `#00D4AA` to `#27F2C7` (proper
     fluorescent teal). Soft swapped its old "soft lavender" for
     `#D16AA6` (dusty rose-purple) and replaced the mint
     accumulator with `#73C79E` (sage). Both pairs read as
     deliberate "signature palette" choices rather than slight
     tints of system colors.

**Thumbnails updated to match**

`AppearancePicker`'s thumbnails now render the same gradients (mini-
LinearGradient inside the 110×70 thumbnail rect) so the Settings
preview accurately predicts what the HUD will look like. Previously
the thumbnails used the old solid-tint colors and the HUD looked
different from the preview — that's fixed.

**Migration**

`hudBackgroundTint` (the old single-color property) kept as a
deprecated `.clear` stub so any unmigrated caller compiles and
draws nothing. New code uses `ThemeBackgroundFill(theme:)`.
`BigHUDView` and `MiniHUDView` switched over. Cheat sheet
panel still uses just the system blur — the cheat sheet is
informational chrome that should match the chrome palette of
the underlying app surfaces, and its rounded-rect background is
small enough that gradient overkill would feel decorative rather
than functional. Reconsider if user feedback says otherwise.

### 0.26.2 — Crosshair pulses + inline hint pill ("Click and drag to capture a region")

Polish pass on 0.26.1's drawn crosshair. System cursor stays visible
(no `CGDisplayHideCursor` — too risky), but two additions make it
unmistakable that the user is in capture mode:

  - **Pulse animation** — when capture arms, the drawn crosshair
    runs a 3-cycle opacity pulse (1.0 → 0.35 → 1.0, autoreverses,
    ~0.4 s per cycle, ease-in-ease-out). Attracts the eye to the
    cursor area for the moment they enter the gesture, then settles
    to a steady visible state.
  - **Hint pill** — a small rounded-rect label appears 14 pt right
    + 16 pt below the crosshair: "Click and drag to capture a
    region". Same anti-glare styling as the crosshair (white text
    on semi-opaque black with a thin white edge). Fades out after
    1.8 s — long enough to read on first use, doesn't linger on
    subsequent captures. Also dismissed immediately when the user
    begins a drag (they clearly understood; no need to keep
    blocking what they're capturing).

The hint follows the cursor through any mouse motion before the
fade starts, so the user can move the mouse before clicking and the
hint stays anchored to the cursor. Multi-display safe: hint is
tied to the same per-screen overlay as the crosshair, so it only
shows on the active screen.

System cursor (whatever arrow / I-beam the underlying app had)
stays visible too — accepted as a small visual quirk. The pulsing
crosshair + hint is the unambiguous "capture mode" signal even
when the system cursor doesn't change shape.

### 0.26.1 — Crosshair cursor, attempt #4 — draw our own, stop fighting AppKit

Third attempt (0.25.0 brute-force `NSCursor.crosshair.push()` + 30 Hz
Timer hammering `set()`) also failed in user testing. Time to admit
the approach is fundamentally wrong and switch to what macOS's own
⌘⇧4 region-capture actually does internally.

**Why NSCursor.* doesn't work for our case (fundamental, not a bug)**

`NSCursor.set()` is APP-SCOPED. When the cursor is over another
app's window, THAT app's cursor rect wins — set in response to
mouse-enter / cursor-update events. Our background-app `.set()`
calls from a Timer or NSEvent monitor don't take effect because we
don't "own" the cursor area when the pointer is over Safari /
Finder / Xcode etc. Same root cause that defeated all three
previous attempts:

  - `addCursorRect(_:cursor:)` — silently skipped on non-key
    panels (0.22.0).
  - `NSTrackingArea + .cursorUpdate + .activeAlways` — events
    delivered unreliably to non-activating panels (0.23.0).
  - `NSCursor.push() + 30 Hz set() hammer` — app-scope ceiling,
    other apps re-assert their own cursor faster than we can
    re-set ours (0.25.0).

The right approach is to stop relying on system cursor APIs and
draw our own crosshair on top.

**The actual fix — draw our own crosshair, track mouse manually**

`CursorOverlayContentView` rewritten to host a CALayer-based
crosshair (two crossing white lines with a 4-pt gap and a center
dot, all with a black shadow for visibility against any
background). Position updated via two NSEvent monitors:

  - `addGlobalMonitorForEvents(.mouseMoved + .leftMouseDragged)`
    — catches mouse moves OVER OTHER APPS' windows (the typical
    case during capture). Fires on background; we push the global
    mouse coord down to each overlay panel.
  - `addLocalMonitorForEvents` for the same mask — catches mouse
    moves over our own overlay panels (they're transparent but
    they're still our windows). Returns the event unmodified so
    selection-overlay drag events still flow.

Each `CursorOverlayPanel` decides whether it owns the current
mouse coord (its screen contains the point) and shows /
hides the crosshair accordingly — multi-display setups stay
sane.

**Selection-overlay z-order — keep the crosshair on top**

Previously `beginSelection()` tore down the cursor overlays when
transitioning to the selection drag. Now they stay alive through
both armed and selecting states (the crosshair must follow the
mouse during the drag too). The selection overlay panels are
built first, then we re-front the cursor overlays so their
crosshair layer sits on top of the selection's dim + rectangle.

**Defensive fallback retained**

`NSCursor.crosshair.push()` / `pop()` still called on
arm / teardown. On macOS versions where it happens to work the
user gets a real system crosshair-shaped cursor IN ADDITION to
our drawn one. On versions where it doesn't, the drawn crosshair
carries the signal alone. Either way the user always sees a
crosshair when capture is armed.

**Slight visual quirk (acknowledged)**

When system cursor doesn't change (most macOS versions for our
case), the user sees BOTH the system arrow AND our crosshair near
the mouse position. The arrow is just outside the crosshair's
center — close enough that the crosshair is unambiguously the
focal indicator. The alternative (hiding system cursor via
`CGDisplayHideCursor`) is too risky: if our process crashes
mid-capture the cursor stays hidden until reboot. Drawn-crosshair-
on-top is the right trade.

### 0.26.0 — OpenRouter provider — one key, 100+ models

Adds OpenRouter (https://openrouter.ai) to the provider lineup. One
API key, dozens of vendors reachable through a single OpenAI-
compatible endpoint — Claude / GPT / Gemini / Llama / Mistral /
DeepSeek / Qwen / Grok / dozens more. For users who don't want to
juggle six separate API keys (and six separate billing
relationships), OpenRouter is the right answer; this just makes it
visible alongside the direct vendors.

Honest disclosure: this should have been in 0.13.0 when we added
the OpenAI-compatible base class. Pure oversight on my part — the
gateway endpoint is exactly the same wire format we already
implement for OpenAI / Grok / Mistral / DeepSeek. Adding it now
takes seven case-inserts on `ProviderKind` plus one line in
`AIProviderRegistry.makeConcrete`.

  - `ProviderKind.openrouter` slotted between `.deepseek` and
    `.ollama` so all cloud providers stay grouped above the
    local ones.
  - `displayName` / `badgeLabel` = "OpenRouter".
  - `iconName` = `arrow.triangle.merge` — many lines merging into
    one reads as "router / multiplexer" at a glance.
  - `brandColor` = `.pink` — outside the existing cloud-vendor
    palette (orange/green/blue/primary/purple/indigo) so a router-
    routed action stands out as "gateway-routed" in the action list.
  - `defaultBaseURL` = `https://openrouter.ai/api/v1`.
  - `defaultModel` = `anthropic/claude-sonnet-4.5` — Claude
    through the gateway matches our anthropic flagship default.
  - `suggestedModels` is a curated cross-vendor sampling:
    `anthropic/claude-sonnet-4.5`, `anthropic/claude-3.5-haiku`,
    `openai/gpt-5`, `openai/gpt-4o-mini`, `google/gemini-2.5-pro`,
    `meta-llama/llama-3.1-70b-instruct`, `mistralai/mistral-large`,
    `deepseek/deepseek-chat`, `qwen/qwen-2.5-72b-instruct`,
    `x-ai/grok-4`. Showcases the gateway's value; users can type
    any slug from openrouter.ai/models.
  - `apiKeyDocsURL` = `https://openrouter.ai/settings/keys` so the
    "Get an API key" link in ProviderEditor points to the right
    page.
  - `AIProviderRegistry.makeConcrete` returns an
    `OpenAICompatibleProvider` with the OpenRouter base URL — same
    code path as OpenAI / Grok / Mistral / DeepSeek, no new
    networking code needed.

Streaming, model selection, status-dot connection-test, the
hold-preview / region-capture flows — all already work because
OpenRouter speaks the same wire protocol the OpenAI-compatible
base provider implements.

### 0.25.1 — Appearance picker actually reaches MiniHUD + cheat sheet, Vivid/Soft tint visible

Follow-up to 0.25.0. After looking at the cut, two gaps:

  1. MiniHUDController's panel wasn't calling `subscribeToAppTheme()`,
     so MiniHUD ignored theme changes entirely.
  2. Even with NSAppearance applied, Vivid and Soft looked identical
     to Dark and Light respectively because the SwiftUI views never
     read `theme.current.hudBackgroundTint` or
     `theme.current.accentColor` — they kept using the system accent
     and clear background.

Both fixed in this bump:

  - `MiniHUDController.buildPanel()` now calls
    `p.subscribeToAppTheme()`.
  - `RegionCaptureCheatSheetController.buildPanel()` same.
  - `BigHUDView` and `MiniHUDView` gained
    `@ObservedObject private var theme = ThemeManager.shared` and
    overlay a `RoundedRectangle.fill(theme.current.hudBackgroundTint)`
    on top of their `VisualEffect` blur. For Auto/Light/Dark the tint
    is `.clear` so the system blur shows through unchanged; Vivid
    adds a warm dark overlay (~35% opacity), Soft a cool pastel one
    (~30%).
  - `BigHUDView.accent` computed property now reads
    `theme.current.accentColor ?? Color(nsColor: .controlAccentColor)`.
    All chip backgrounds, selection rings, hover highlights, and
    Settings-recovery link colors that already referenced `accent`
    now automatically pick up the Vivid orange / Soft lavender.

Net effect: cycling through Auto → Light → Dark → Vivid → Soft in
Settings now visibly changes both BigHUD and MiniHUD chrome — same
shape and layout, distinctly different palette. Auto vs Light look
identical when the system is in Light Mode (by design — Auto
follows the system); switch the system to Dark Mode and Auto
follows, Light stays light. Vivid sits on dark with bright orange
selection rings; Soft sits on light with lavender selection rings.

### 0.25.0 — Appearance picker + crosshair cursor that actually appears

Two unrelated features in one bump because they shipped together.

**Appearance picker — Fantastical-style theme thumbnails**

New "Appearance" section in Settings → General. Five preset themes,
each rendered as a small thumbnail preview of the BigHUD in that
theme's palette (mimics the picker in Fantastical / Notes app):

  - **Auto** — follows system day/night. DrPaste's default since 0.2.0;
    the thumbnail renders split light/dark to signal "this one switches".
  - **Light** — forced light, ignores system Dark Mode.
  - **Dark** — forced dark, ignores system Light Mode.
  - **Vivid** — high-contrast saturated palette on a dark base.
    Bright orange accent (#FF6B36), vivid teal highlights (#00D4AA).
  - **Soft** — bright pastel palette on a light base. Soft lavender
    accent (#B19CD9), mint highlights (#95E1D3).

New files: `AppTheme.swift` (the model + ThemeManager singleton +
SwiftUI ThemeThumbnail view). `SettingsWindow.swift` gains an
`AppearancePicker` view rendered inside a new `Section("Appearance")`
above the existing HUD section.

Wiring: `ThemeManager` persists the choice to UserDefaults, broadcasts
`appThemeDidChange` notification on change. New `NSWindow` extension
`subscribeToAppTheme()` registers a selector-based observer that
re-applies the appearance on every change — call once in any panel's
init. BigHUDPanel wired; MiniHUDController / overlay panels can be
extended in a follow-up if visual gaps are noticed.

Caveats — this initial cut applies the appearance override via
`NSWindow.appearance = ...`. Vivid/Soft are functionally close to
Dark/Light respectively until the BigHUD/MiniHUD content views also
read `ThemeManager.shared.current.accentColor` and friends in their
SwiftUI bodies. Iteration #2 will wire the custom accent + highlight
colors into the chrome.

**Cursor crosshair — fix #3 (hopefully final)**

The crosshair cursor for region-capture armed state STILL didn't
appear despite the 0.23.0 NSTrackingArea fix. Root cause this time:
macOS doesn't reliably deliver cursor events to non-key
non-activating panels regardless of which API you use
(`addCursorRect`, `NSTrackingArea` with `.cursorUpdate`, `NSCursor.set`
inside `mouseMoved`). And even when our app does call `NSCursor.set()`,
other apps' cursor rects re-assert their own cursor the moment the
pointer enters their window region — which over our screen-spanning
overlay happens constantly because the overlay is invisible to the
cursor manager (transparent fill, no key status).

The actually-working approach is brute force:

  1. `NSCursor.crosshair.push()` once on arm — sets the crosshair
     as the default fallback on the cursor stack.
  2. A 30 Hz Timer that calls `NSCursor.crosshair.set()` every
     frame. When another app's cursor briefly wins as the pointer
     transits their window, our hammered `set()` re-asserts within
     ~33 ms — imperceptible flicker, rock-solid visual signal.
  3. `NSCursor.pop()` on teardown to restore the previous cursor
     stack state.

`startCursorEnforcement()` fires from `arm()` and runs through
both armed + selecting states (selection overlay also wants the
crosshair throughout the drag). `stopCursorEnforcement()` fires
from `tearDown()` — the single termination point for both the
success path (capture committed) and all cancel paths (⌥⌘ release,
Esc, mid-drag bail).

### 0.24.3 — Hotkey recorder can capture ⌥⌘<letter> chords

Sibling bug to 0.24.2 — same root family, different symptom.
Per-action hotkey RECORDING in the Settings → Add Action dialog
failed for every ⌥⌘ combination ("Click to record", press ⌥⌘V,
nothing happens; system BigHUD opens instead). Other modifier
combos (⌃⇧X, fn+letter, ⇧⌘P, etc.) recorded fine.

**Root cause**

`HotkeyRecorderField` listens via `NSEvent.addLocalMonitorForEvents`
which only fires for events delivered to OUR app's responder chain.
Two interception layers run BEFORE our app sees the event:

  1. EventTap (`.cgSessionEventTap`) — intercepts ⌥⌘V/C/X/S as
     system hotkeys and any ⌥⌘<letter> registered in the
     hold-preview map.
  2. Carbon `RegisterEventHotKey` — system-wide registration of
     ALL per-action hotkeys, irrespective of focus.

Both consume the keyDown before it reaches our app. The recorder's
local monitor never fires. From the user's perspective, ⌥⌘ chords
"can't be recorded" — only combos that NEITHER layer intercepts
(non-⌥⌘) get through.

**Fix — silence both layers during recording**

  - New `HotkeyEngine.setRecordingMode(_:)` protocol method (default
    no-op). `EventTapEngine` stores a `recordingPassthrough` flag and
    returns every event unmodified when set. `CarbonHotKeyEngine`
    unregisters its system hotkeys (⌥⌘V/C/X/S) and re-registers them
    on resume. `GlobalMonitorEngine` uses the default no-op.
  - New `ActionHotkeyManager.pauseForRecording()` /
    `resumeFromRecording()` — unregisters every per-action Carbon
    hotkey and reloads from current config on resume (so a hotkey
    the user just recorded and saved is picked up).
  - New `AppDelegate.beginHotkeyRecording()` /
    `endHotkeyRecording()` orchestrators — call both the engine's
    `setRecordingMode(true)` and the manager's `pauseForRecording()`.
    End also re-pushes the hold-preview map to the EventTap so the
    newly-recorded hotkey is recognised immediately.
  - `HotkeyRecorderField.startRecording()` / `stopRecording()` call
    the AppDelegate methods (via `NSApp.delegate as? AppDelegate`).
    `stopRecording` guards on `isRecording` so the `.onDisappear`
    safety net doesn't fire a spurious resume.

**Net effect**

Open Add Action, click the recorder, press ⌥⌘V → recorder captures
⌥⌘V (and immediately shows the reserved-combo warning because it
still IS reserved for the system paste hotkey). Press ⌥⌘T (or any
other letter) → recorder captures, shows the green "HUD ready"
hint from 0.24.0, ready to Save. After Save, hotkeys re-register
with the new binding included.

### 0.24.2 — Real fix for user hotkeys not firing (load-order bug + defensive passthrough)

0.24.1's grace-period bump turned out to be a partial fix at best.
Re-reading user reports — per-action hotkeys were "mostly not
working", not just flashing. Root cause was much more concrete than
the timing-race hypothesis from 0.24.1.

**Bug 1 — `reloadHoldPreviewMap()` called before `startEngine()`**

In `applicationDidFinishLaunching` the call order was:

```
ActionHotkeyManager.shared.install()
ActionHotkeyManager.shared.reload()
reloadHoldPreviewMap()   // ← engine is still nil here
...
startEngine()            // ← engine created
```

`reloadHoldPreviewMap` guards on `guard let eventTap = engine as?
EventTapEngine else { return }` and bails silently when `engine`
is nil. Result: the EventTap's `holdPreviewActionHotkeys` map was
NEVER populated. Stayed empty for the entire app lifetime (unless
the user later opened Settings and changed something, which would
fire `config.didSet` and re-call `reloadHoldPreviewMap` AFTER the
engine existed).

**Bug 2 — armed-state swallowed unknown ⌥⌘ chords**

Compounding the first bug: my `.armed`-case keyDown handler had:

```swift
if isSystemHotkey || isActionHotkey {
    // cancel arm + fall through
} else {
    return nil  // swallow
}
```

With the map empty (bug 1), `isActionHotkey` was always false for
user-defined hotkeys. So when a tap took long enough for the arm
grace to fire (state = .armed) and the user pressed their ⌥⌘<letter>,
the chord got swallowed — not by the EventTap's pass-through path,
not by Carbon either. Net effect: hotkey appeared dead.

Short taps (< 400 ms) escaped because state stayed `.armPending`
and that case falls through to the normal modsPresent block (which
either matches in the EventTap or passes through to Carbon).

This is exactly what the user reported: "mostly not working" —
because most natural taps occasionally cross 400 ms and hit the
swallow path.

**Fix 1 — call order**

Moved `reloadHoldPreviewMap()` to AFTER `startEngine()` in
`applicationDidFinishLaunching`. The map now populates correctly
at launch, and the armed-state lookup recognises user hotkeys.

**Fix 2 — defensive passthrough**

Even with the map populated, edge cases remain — a brand-new
hotkey added in Settings might not have been pushed yet, or a
load-order shift could re-introduce a similar gap. So the armed-
state handler now ALWAYS cancels arm + falls through on ⌥⌘
chords, regardless of whether the map knows the letter. If the
chord matches the per-action map, the natural `modsPresent` branch
schedules pending fire. If not, the chord passes through to Carbon
(authoritative source for per-action registrations). If even
Carbon doesn't know it, the chord goes to the underlying app —
which is the worst case but still better than silent eating.

Non-⌥⌘ keys while armed are still swallowed (user is in capture
mode; stray typing into background apps shouldn't leak).

### 0.24.1 — Region-capture arm grace bumped to 400 ms (per-action hotkey reliability fix)

Hot-fix for a regression user-reported after 0.20/0.21: per-action
⌥⌘<letter> hotkeys became "unreliable" in some sense. System
hotkeys (⌥⌘V/C/X/S) stayed fine — they fire instantly on keyDown
and never touched the new region-capture state machine.

**Root cause hypothesis**

The #A11 region-capture arm grace timer was sharing the 250 ms
constant with #A10's per-action hold-preview grace. 250 ms is
plenty for the per-action case (where the grace counts from
letter-press to letter-release, and the user has already
committed to a hotkey by pressing the letter) but too tight for
the arm case (where the grace counts from ⌥⌘-press to letter-
press OR mouse-click, and "I'm about to type a letter" taps can
easily take 280–350 ms in natural rhythm).

When a tap landed in the 250–350 ms range, the arm grace fired
just before the letter keyDown was processed:

  1. T=0: ⌥⌘ pressed → state=armPending, arm timer at T+250.
  2. T=250: arm timer fires on main → state=armed, dispatches
     `hotkeyEngineDidArmRegionCapture`. Cursor overlay + cheat
     sheet rendered.
  3. T=260: letter keyDown arrives on EventTap thread → handles
     `.armed` case → cancels arm → schedules pendingFire →
     dispatches `hotkeyEngineDidCancelRegionCapture`.
  4. Main queue runs the arm-dispatch first (queued at T=250),
     then the cancel-dispatch (queued at T=260). User sees the
     cursor flip + cheat sheet flash for ~50–100 ms before
     disappearing.

The hotkey would still FIRE correctly (pendingFire fires
direct-paste on modifier release as expected), but the visual
flash + the timing weirdness made the overall gesture feel
"unreliable". Some users would also pull their finger off the
modifier in surprise mid-flash and never trigger the pending
fire at all.

**Fix**

Split the constant: `regionCaptureArmGracePeriod = 0.40`
(separate from `holdPreviewGracePeriod = 0.25`). 400 ms is well
above any natural tap rhythm — every per-action hotkey tap
completes before the arm timer ever schedules state=armed.

The two intent signals are genuinely different anyway:

  - Per-action hold-preview is a continuation: the user pressed
    the letter and decided to preview before committing. Short
    grace makes the preview feel responsive when it's wanted.
  - Region-capture arm is a fresh intent: the user is going to
    deliberately hold modifiers ALONE to enter capture mode.
    Users who actually want capture hold for 500+ ms anyway,
    so a 400 ms threshold doesn't cost them anything but kills
    the flash for everyone else.

### 0.24.0 — Hotkey field tells the user whether HUD hold-preview will work

The Action editor's Hotkey field gained a three-state hint that
makes the modifier-matching invariant from 0.18.0 visible at
config time instead of letting users discover it through
"why didn't holding work?" frustration.

  - **No hotkey picked** — tertiary instructional caption: pick
    ⌥⌘ + letter to unlock hold-preview; other combos run as
    pure direct-trigger.
  - **⌥⌘ + letter picked** — green check + "HUD ready — tap to
    paste immediately, or keep ⌥⌘ held after pressing X to
    preview the result in BigHUD before committing." The letter
    is dynamic — pulled from `hotkey.keyDisplayName` (new helper
    on `ActionHotkey`).
  - **Any other combo** — orange warning triangle + explanation
    that the BigHUD hold-preview requires ⌥⌘ for gesture
    composition. Non-blocking — user can still Save.

A second always-visible chip in the section header
("Tip: ⌥⌘ + letter enables HUD hold-preview") nudges the
recommendation BEFORE the user picks anything, so the
recommendation is discoverable from the moment they open the
dialog.

Backed by a new `ActionHotkey.isOptCmdOnly` computed property
(same `modifiers == optionKey | cmdKey` check used by
`reloadHoldPreviewMap` and `collectRegionCaptureCheatSheetHotkeys`,
extracted into the model so callers don't reach for Carbon
constants from view code). `conflictsWithMainHotkeys` now uses
it too for symmetry.

### 0.23.0 — Cursor-overlay fix + sound rebalancing

Two-part tuning pass on the gesture audio + visual feedback.

**Cursor overlay fix (#A11 C2)**

The crosshair cursor wasn't appearing when ⌥⌘ was held — only the
corner cheat sheet would materialise. Root cause: `addCursorRect`
on a `.borderless` `.nonactivatingPanel` is unreliable. AppKit
treats non-key panels as "inactive" and silently skips the cursor
rect registration in `resetCursorRects`. Fix: replace the cursor
rect with a proper `NSTrackingArea` using
`[.activeAlways, .cursorUpdate, .inVisibleRect]` and override
`cursorUpdate(with:)` to explicitly call `NSCursor.crosshair.set()`.
`.activeAlways` bypasses the active-key-window check;
`NSCursor.crosshair.set()` is the same call macOS's own ⌘⇧4
region-capture uses. Also set `acceptsMouseMovedEvents = true` on
the panel so the tracking area's events flow at all — without
this AppKit drops mouse-moved events on non-key panels and the
cursor update never fires. Safety belt: `mouseMoved` override
also calls `.set()` for the case where the first `cursorUpdate`
gets skipped on `orderFrontRegardless`.

**⌥⌘S gets its own sound — Submarine**

Append Copy was sharing `copySuccess` (now Purr) with Quick Copy
and per-action capture. But ⌥⌘S is conceptually "fold another
piece into the accumulator", which deserves a distinct cue from
"plain capture". New `SoundCue.appendCopy` mapped to system
"Submarine" — sonar-style bloop that reads as "ping into the
stack". Used in all four success paths inside
`hotkeyEngineDidAppendCopy` (new session capture + three merge
variants for text / files / fallback).

**Per-action hotkey now plays "captured" sound at the right time**

Following from 0.22.0's selection-first semantics — the hotkey
issues ⌘C, captures the selection, runs the action, pastes.
Previously only the final paste played a sound (Glass). Now the
capture step also plays `copySuccess` (Purr), giving the user a
clean two-stage audio rhythm: *Purr* (your selection landed in the
pasteboard) → *Glass* (the transformed result was pasted). Applies
to both direct-trigger (`actionHotkeyDidFire`) and hold-preview
(`openBigHUDFocusedOnAction`) paths.

**Settings UI exhaustiveness**

The sound-cue toggle row in Settings now lists `.appendCopy`
between the paste cues and the typeTick. Same `cueLabel` switch
pattern, label "Play sound on ⌥⌘S append copy" so users with the
gesture flow in muscle memory recognise what it controls.

### 0.22.0 — Per-action hotkey operates on current selection, not stale clipboard

Behaviour change for every per-action hotkey (built-in and
user-defined). Previously: hotkey → read whatever's in the clipboard
right now → run action → paste. Result was confusing whenever the
user's intent was "do X to what I just highlighted" but the
clipboard still held something from 20 minutes ago. Now: hotkey →
simulate ⌘C to capture what's currently selected → wait for the
pasteboard to refresh → run action against the fresh selection →
paste. If nothing was selected (the simulated ⌘C produced no
pasteboard change within 250 ms), fail audibly via
`SoundFeedback.pasteFailure` and dismiss the spinner — better than
silently transforming whatever stale content was sitting there.

**Why this matters**

A per-action hotkey is "operate on what I'm looking at" by intuition.
The old clipboard-based behaviour was the reverse of intuition:
operating on clipboard contents (which the user rarely remembers)
and only happening to match the selection when the user had just
pressed ⌘C explicitly. Every user feedback loop confirmed the same
mental model: "I press ⌥⌘T expecting it to translate THIS [the
highlighted text], not whatever I had on the clipboard". The fix
brings DrPaste's behaviour in line with that mental model.

**Both code paths converge**

The change applies symmetrically:

  - **Direct-trigger (quick tap)** — `actionHotkeyDidFire` snaps a
    ⌘C, polls the pasteboard up to 250 ms, builds a transient
    ClipboardItem from the captured representations, runs the
    action, pastes the result. The selection ALSO lands in history
    via `watcher.forceTick()` immediately after capture, so the
    user can find it again in BigHUD without waiting for the
    watcher's 0.5 s poll.
  - **Hold-preview (⌥⌘<letter> held past 250 ms)** —
    `openBigHUDFocusedOnAction` does the same ⌘C + poll + forceTick
    dance, then opens BigHUD with the freshly-captured clip at
    index 0 (focused) and the action pre-selected. The preview pane
    now renders the action's output against what the user actually
    highlighted, which is the only useful preview to show. Release
    ⌥⌘ → standard commit path pastes.

**Failure handling**

If `simulateCopy()` produces no pasteboard change within the 250 ms
window — typically because nothing was selected, or the frontmost
app ignored the ⌘C — both paths play the paste-failure sound and
abort cleanly. The hold-preview path additionally calls
`EventTapEngine.resetHudActive()` so the engine doesn't keep its
`bigHUDIsActive` flag stuck true (it had been set to true by the
grace-expiry callback in anticipation of the open). Otherwise the
inevitable ⌥⌘ release would fire `hotkeyEngineDidRelease` which
would try to commit a HUD that never opened.

**Coexistence with other paths**

  - **⌥⌘V (BigHUD open)** unaffected. BigHUD's whole point is
    browsing history, so opening on whatever clipboard already
    contains is correct.
  - **⌥⌘C (Quick Copy)** already did ⌘C + poll natively. No
    change.
  - **⌥⌘S (Append Copy)** already did ⌘C + poll natively. No
    change.
  - **⌥⌘X (Cut & Replace)** does its own ⌘X simulation through the
    Cut-and-Replace state machine — separate code path.
  - **⌥⌘+drag (Region capture)** already produces a fresh image
    from screen pixels, so the selection-first semantics are
    inherent to that gesture.

**New helper — `snapshotPasteboardAsItem(pb:sourceApp:)`**

Extracted from the inline ClipboardItem construction in
`actionHotkeyDidFire`. Builds a transient item with all
representations copied to the store's blob directory so
Paste-as-is can restore them losslessly downstream. Used only for
the in-flight action target — not added to the store's main
`items` array (that's what `watcher.forceTick` does separately).

### 0.21.0 — Region-capture corner cheat sheet + armed-state hotkey passthrough

Once the C2 crosshair cursor appears (⌥⌘ held alone past 250 ms), a
compact keyboard + mouse + legend panel materialises in the
bottom-right corner of the active screen. The keyboard mirrors the
B&W contour style the user signed off on in chat (and which is now
recorded in `preferences.md` as the canonical style for any technical
schematic). The mouse pictogram above the arrow cluster carries a
thicker outline on the left button — visual confirmation that the
"drag to capture" gesture is the one currently armed. The legend
below lists every ⌥⌘ hotkey the user can fire from this state:
system hotkeys ⌥⌘V/C/X/S plus whatever per-action ⌥⌘<letter>
shortcuts they've configured in Settings.

**Modifier filter — only ⌥⌘ entries appear**

User-defined hotkeys with different modifiers (⌃⇧X, fn+letter,
⇧⌘P, etc.) don't appear in the cheat sheet. They couldn't fire
from this state anyway — the EventTap engine only enters the
region-capture machine when bare ⌥⌘ is held, and any keyDown with
non-matching modifiers either falls through to Carbon's
direct-trigger path (different modifiers) or is part of an action
that wouldn't combine sensibly with "I'm about to drag a
rectangle". Filtering them out keeps the panel focused on what's
actually relevant in this moment.

**Proximity fade — never blocks the capture**

A 30 Hz polling timer compares `NSEvent.mouseLocation` against
the cheat-sheet panel frame expanded by an 80 pt margin. Inside
the margin → panel animates to 15 % opacity over ~120 ms; back
outside → returns to full opacity. The user can always start a
drag in the corner area without the panel obscuring what they're
trying to capture. The panel's `ignoresMouseEvents` flag is true
throughout so clicks pass through to the C1 selection overlay
underneath.

**Armed-state passthrough — cheat sheet hotkeys are actually callable**

Previously the EventTap engine swallowed ALL keys (except Esc)
while in `.armed` state — defensive against stray input. With the
cheat sheet advertising callable hotkeys, that defensiveness
became a lie. Updated: ⌥⌘ system hotkeys (V/C/X/S) and per-action
⌥⌘<letter> hotkeys now cancel the arm and fall through to their
normal handler. So if the user holds ⌥⌘ → sees the cheat sheet →
realises they want Translate to Spanish (their ⌥⌘T hotkey) →
presses T → the cheat sheet + cursor overlay vanish and the
translate action fires exactly as if they had pressed ⌥⌘T from
idle. Non-⌥⌘ keys are still swallowed (no leakage). In
`.selecting` (mouse is down, drag in progress) all keys except
Esc remain swallowed — too late to switch action mid-drag.

**Implementation — new file RegionCaptureCheatSheet.swift**

  - `RegionCaptureCheatSheetController` — owns the corner NSPanel,
    pulls fresh hotkeys via injected `hotkeysProvider` closure on
    every show, manages the 30 Hz proximity-fade timer.
  - `RegionCaptureCheatSheetView` — SwiftUI body: `KeyboardCanvas`
    on top, two-column legend below (built-ins on the left, user
    hotkeys on the right, top 5 shown + "+N more" overflow line),
    `VisualEffect` HUD-material background with rounded corners.
  - `KeyboardCanvas` — coordinate-precise SwiftUI reproduction of
    the chat-tested SVG, scaled 0.7×. Each key is a
    `RoundedRectangle.strokeBorder` with conditional `lineWidth`
    (1.5 for highlighted, 0.5 for inactive). Letters that match
    `highlightedLetters` (system V/C/X/S plus user-defined ⌥⌘
    letters) get the thick stroke. Mouse pictogram built from two
    custom `Shape`s — `MouseShape` for the body and `MouseLeftButtonShape`
    overlaid with thick stroke to indicate "pressed".

**Wire-up**

  - `ScreenRegionCaptureController.cheatSheet: RegionCaptureCheatSheetController`
    — instance per gesture (matches the rest of the controller's
    short-lived design). `show()` from `arm()`; `hide()` from
    `beginSelection()` (user has committed to a drag — hint
    becomes noise) and from `tearDown()` (cancel path).
  - `AppDelegate.armRegionCapture()` injects the hotkeys provider
    closure that returns the current ⌥⌘<letter> set from the
    registry. Same filter as `reloadHoldPreviewMap` — exact
    `modifiers == optCmd` equality, only enabled actions.
  - `KeyName.from(keyCode:)` reused for the letter → display-name
    mapping, so a hotkey on the European AZERTY layout's Q
    position still renders as "Q" in the cheat sheet.

### 0.20.0 — #A11 screen-region capture (C1 + C2)

DrPaste gains a fourth way to fill the clipboard: hold ⌥⌘, drag a
rectangle anywhere on screen, release the mouse, the captured PNG
lands at the top of history and the BigHUD opens focused on it.
Release ⌥⌘ to paste — Paste-as-is by default, or arrow over to OCR /
ASCII art / AI Describe before releasing. One continuous press-and-
hold from "I want to grab this pixel area" to "...and paste it
(possibly transformed) into Discord". macOS-native ⌘⇧⌃4 is the
closest analogue, but it's decoupled from history, sources,
transformations, and the rest of DrPaste's surfaces — this lives
inside the same modal family as ⌥⌘V.

**Gesture flow**

  1. Hold ⌥⌘ alone past 250 ms (no other key, no mouse-down inside
     the window) → cursor changes to a crosshair across every
     display. Visual confirmation that region capture is armed.
  2. Click anywhere → selection overlay replaces the cursor overlay.
     35 % black dim over the whole screen, punched out where the
     rectangle is, 1 pt accent stroke around it, live "WxH" pixel
     readout near the cursor.
  3. Drag → rectangle resizes in real time.
  4. Release mouse → capture fires synchronously, BigHUD opens
     with the new image focused. ⌥⌘ is still held.
  5. Inside BigHUD: navigate actions with ←/→, switch focused
     clip with ↑/↓, accumulator + chain work as usual.
  6. Release ⌥⌘ → standard commit path pastes whatever you
     navigated to (or Paste-as-is if you didn't).
  7. Release ⌥⌘ before clicking → cursor overlay disappears, no
     capture, no clip. Same for Esc.

**Why the cursor swap is safe**

Earlier spec passes rejected cursor swapping because the normal
⌥⌘V / ⌥⌘C / ⌥⌘X / ⌥⌘S / ⌥⌘<letter> flow would have made the
cursor flicker on every press. The new design guards the swap
behind the same 250 ms grace timer #A10's hold-preview uses — any
keyDown or mouse-down inside the window cancels the arm, so
normal hotkey sequences (where the letter arrives within ~80 ms
of the modifiers) never trigger it. Only a deliberate "I'm
holding ⌥⌘ and waiting" intent reaches the threshold.

**Implementation — EventTap state machine**

The EventTap engine grows three new mouse events in its tap mask
(`.leftMouseDown`, `.leftMouseDragged`, `.leftMouseUp`), all
passed through unmodified except while a region capture is in
progress. State machine: `idle → armPending → armed → selecting`,
each transition driven by events the tap already sees. A
generation counter on `armPending → armed` invalidates cancelled
arms, same pattern as `pendingFireGeneration` from #A10.

  - `flagsChanged` with bare ⌥⌘ pressed, no other state →
    `scheduleRegionCaptureArm()` schedules a 250 ms grace timer.
  - Any `keyDown` while `armPending` → cancel arm. While `armed`
    or `selecting`, `kVK_Escape` cancels and tears overlays down;
    other keys are swallowed (don't leak into underlying apps).
  - Grace expiry → state becomes `armed`,
    `hotkeyEngineDidArmRegionCapture()` fires.
  - `leftMouseDown` while `armed` → state becomes `selecting`,
    `hotkeyEngineDidBeginRegionDrag(at:)` fires (CGEvent's location
    is flipped to Cocoa bottom-left global coords). While
    `armPending`, click cancels arm; the click itself passes
    through to the underlying app unmodified.
  - `leftMouseDragged` / `leftMouseUp` while `selecting` →
    update / end delegate calls. `leftMouseUp` also sets
    `bigHUDIsActive = true` so the subsequent ⌥⌘ release flows
    through the existing commit path.
  - `flagsChanged` with ⌥⌘ released while `armed` or `selecting`
    → cancel delegate call, overlays come down, no capture.

**Implementation — ScreenRegionCapture.swift**

New file. `ScreenRegionCaptureController` owns the cursor (C2)
and selection (C1) overlay panels. Instance-per-gesture — easier
than long-lived state because each gesture cleanly terminates with
`onCapture` or `onCancel`.

  - `CursorOverlayPanel` — full-screen transparent `NSPanel`,
    `level: .screenSaver`, `.nonactivatingPanel`. Hosts a
    `CursorOverlayContentView` whose `resetCursorRects()`
    installs a single `addCursorRect(bounds, cursor: .crosshair)`.
    AppKit handles the cursor swap natively — no `NSCursor.hide()`,
    no custom-drawn cursor. One per `NSScreen.screens` entry so
    the crosshair stays as the user moves between displays.
  - `SelectionOverlayPanel` — same panel kind, with a
    `SelectionOverlayContentView` backed by three CALayers: a
    `CAShapeLayer` for the dim mask (even-odd fill rule, outer
    rect minus selection rect), a `CAShapeLayer` for the 1 pt
    accent stroke around the rectangle (inset by 0.5 pt for pixel
    alignment), and a `CATextLayer` for the "WxH" pixel readout.
    `CATransaction.setDisableActions(true)` on each update so the
    rectangle follows the cursor without animation lag — 120 Hz
    smooth on ProMotion. One per screen; only the panel whose
    screen contains the selection rect draws the rect, others
    stay fully dimmed so the "selection mode" signal covers
    every monitor uniformly.
  - Capture: `CGWindowListCreateImage(rect, .optionOnScreenOnly,
    kCGNullWindowID, [.bestResolution, .boundsIgnoreFraming])`.
    Synchronous, lossless. ScreenCaptureKit would be the modern
    path but adds async setup overhead that isn't worth it for a
    one-shot rectangle grab. Result is a `CGImage` →
    `NSBitmapImageRep(cgImage:).representation(using: .png, ...)`
    → PNG `Data`.
  - Coord-system glue: CGEvent location field is top-left origin
    in points, NSScreen frames are bottom-left origin in points.
    Flip Y around the union of all screen `maxY` values so the
    point matches `NSEvent.mouseLocation`.

**Implementation — AppDelegate wire-up**

  - New properties: `regionCapture: ScreenRegionCaptureController?`
    (built lazily on first arm), `regionCaptureSourceApp:
    NSRunningApplication?` (frontmost-app snapshot taken at arm
    time, carried through to BigHUD as `savedFrontmostApp` so the
    eventual paste lands in the right window even if the user
    clicked into a different app during the drag).
  - Five new delegate methods on `HotkeyEngineDelegate`
    (`hotkeyEngineDidArmRegionCapture` and friends) routed to
    main-actor handlers.
  - `armRegionCapture()` — defensive guards against `bigHUDPanel`
    being visible, `pendingDeferredPasteApp != nil`, or
    `aiStreamingTask != nil`. The engine already blocks against
    its own `bigHUDIsActive` flag for Gesture-mode HUDs; these
    additional checks cover MiniHUD scenarios and the deferred-
    paste handoff window so no DrPaste UI ever overlaps with a
    region-capture gesture.
  - `onCapture` callback inserts the PNG into history via the new
    `ClipboardStore.addCapturedImage`, then opens BigHUD focused
    on the new clip via `openBigHUDFocusedOnCapturedImage`.

**ClipboardStore.addCapturedImage**

New helper that bypasses the pasteboard entirely. Writes the PNG
to both `images/` (thumbnail / preview rendering) and `blobs/`
(as `public.png` representation so Paste-as-is can hand the raw
bytes to the receiving app). Inserts at index 0 via
`insertSnapshot` rather than `add` so back-to-back captures of
identical pixels don't dedup. Source metadata populated from the
frontmost-app snapshot taken at arm time.

**Permissions**

macOS requires Screen Recording permission for capturing pixels
outside the calling app's own windows. The first capture attempt
triggers the system prompt; subsequent denials surface as nil
result and a paste-failure sound. Full onboarding integration
(Welcome window guide row) deferred to a follow-up tweak.

**Limitations / follow-ups**

  - Full Gesture Mode only. Limited Mode (Carbon engine, no AX)
    has no CGEventTap so the modifier-release / mouse-down
    detection can't run. Consistent with how every other gesture-
    mode feature degrades in Limited Mode.
  - Cross-display drags become single-screen captures at release
    time — `CGWindowListCreateImage` accepts a rect but treats
    cross-display rects unreliably. Single-screen for the
    initial ship.
  - Welcome-window discoverability rows ("⌥⌘ + drag — Capture
    screen region…") not yet wired. Add in a follow-up after
    user feedback on the gesture confirms the framing.

### 0.19.0 — Deferred paste during AI loading (timing-model unification)

Direct-trigger per-action hotkeys now behave predictably for slow AI
actions. The previous behaviour was the worst kind of unpredictable:
press ⌥⌘E for "Translate to English", release ⌥⌘ a fraction too
early, get the un-transformed original pasted into the target app
because the streaming task hadn't produced a result yet. The fix
collapses three previously-distinct timing branches (HUD never
opened / HUD opened but action incomplete / HUD opened and action
complete) into one rule: **whatever the user asked the AI to do
will be pasted when the AI finishes — full stop**. Releasing ⌥⌘
mid-stream stops being a race condition and becomes a deliberate
"I trust the AI, paste it when ready" signal.

**Why this matters**

A press-and-hold gesture only feels reliable when the timing model
is invariant under user behaviour. Before this change, three things
the user could not see — network latency, model speed, and the exact
moment their fingers came off the modifiers — combined to produce
three different outcomes:

  1. Quick release (< 250 ms after chord): direct paste fires from
     the EventTap modifier-release branch. AI was never even called.
     Placeholder pasted. **Wrong content.**
  2. Slow release (> 250 ms, AI still streaming when HUD opens but
     ⌥⌘ released before completion): commitHUD ran with
     `hudState.outcome == .preview(originalItem)`. Placeholder
     pasted. **Wrong content.**
  3. Slow release with completed stream: commitHUD ran with the
     transformed outcome. **Right content.**

Three branches, only one of which produced the result the user
actually asked for. The fix unifies branch 2 with branch 3 (waiting
for the stream rather than committing the placeholder) and leaves
branch 1 untouched. After: branches 2 and 3 produce identical paste
content. The user's release timing only controls **which surface
shows the wait** — fast release shows ProgressHUD, slow release
shows HUD preview pane — never **what gets pasted**.

**Implementation — deferred-paste handoff in AppDelegate**

- `pendingDeferredPasteApp: NSRunningApplication?` — new field on
  AppDelegate. Set when commitHUD detects an in-flight AI call;
  cleared when the streaming task's completion handler fires the
  paste against it. The frontmost-app reference is captured at HUD
  summon time (long before the AI returns), so the paste lands in
  the right window even if the user clicked elsewhere during the
  wait.
- `commitHUD()` refactor — when `isPreviewLoading && aiInflight != nil`,
  calls a new `deferPasteAfterAILoad(savedApp:)` instead of pasting
  the current outcome. Otherwise the existing path runs unchanged
  via a new `commitOutcome(_:savedApp:)` helper (factored from the
  inline switch so the deferred-paste path can reuse it).
- `deferPasteAfterAILoad(savedApp:)` — does NOT call `closeHUD()`,
  which would cancel `aiStreamingTask` and defeat the purpose.
  Instead manually tears down the gesture monitor, tick timer, and
  accumulator state, then `orderOut`s the HUD panel. Promotes
  `ProgressHUDController` as the in-flight indicator with the same
  `AIInflight` descriptor the HUD preview pane was showing — same
  provider · model · elapsed counter, identical visual language.
- Streaming task completion handler — additionally checks
  `pendingDeferredPasteApp`. If set, clears it, hides
  ProgressHUD, and fires `commitOutcome(outcome, savedApp: target)`.
  Runs independently of `previewToken` (the navigation guard for
  the HUD preview pane) because the user pressed a hotkey and the
  result owes them a paste regardless of whether they navigated
  away mid-stream.

**ProgressHUD — user-initiated cancel via X button**

- `ProgressHUDController.show(label:inflight:onCancel:)` — new
  trailing closure parameter. Stored in `onCancelHandler` and
  invoked only when the user clicks the X button. Programmatic
  `hide()` (the completion-path teardown) does NOT call it —
  separates "action completed normally" from "user gave up".
- The deferred-paste path passes a cancel handler that calls
  `aiStreamingTask?.cancel()`, clears `pendingDeferredPasteApp`,
  and plays the paste-failure sound. After cancel the streaming
  task's completion block still runs (Task cancellation is
  cooperative) but finds `pendingDeferredPasteApp == nil` and
  becomes a no-op for the paste branch — no accidental paste into
  the user's target app after they've explicitly dismissed the
  HUD.

**What the user sees now**

- Press ⌥⌘E, release immediately → ProgressHUD appears showing
  "Translate to English · Anthropic claude-sonnet-4-6 · 2.1s",
  AI finishes, result pastes. X button dismisses + cancels.
- Press ⌥⌘E, hold past 250 ms → HUD preview opens with loading
  spinner in the preview pane. Release ⌥⌘ while loading →
  HUD closes, ProgressHUD appears, same continuation as above.
  Release after loading → instant paste of the AI result.
- In every case: the content pasted is the content the AI
  produced for the action the user requested. Never a placeholder.

### 0.18.0 — #A10 hold-preview for per-action hotkeys (C1)

First half of #A10 — Full Gesture Mode now extends the press-and-hold
gesture to every ⌥⌘<letter> per-action hotkey. The classic
tap-and-release path stays identical (zero perceptible change for
anyone using direct paste). New: keep ⌥⌘ held past 250 ms after the
chord, and the HUD opens pre-focused on the action's preview pane.
Same release-⌥⌘-to-commit semantics as ⌥⌘V — no new gestures to learn,
no new modal state to manage.

**Why this matters**

Per-action hotkeys are fast but blind. The user presses ⌥⌘E for
"Translate to English" and the result appears in the target app
instantly — no way to peek first, no second chance if the AI rewrote
the tone unexpectedly. The fix is a no-cost opt-in: lift ⌥⌘ as
usual → direct paste; keep ⌥⌘ held → HUD opens, user inspects, lifts
⌥⌘ when satisfied → commit. The detection window is short enough
(250 ms) that an ordinary release sequence (letter then modifier,
all within ~80–150 ms) never triggers the HUD as a flash of UI.

**Implementation — EventTap engine grace-period machine**

- `EventTapEngine.holdPreviewActionHotkeys: [UInt16: String]` —
  CGKeyCode → actionID map, pushed by AppDelegate whenever
  `ActionConfig.actionHotkeys` or any enabled-state changes. Only
  ⌥⌘<letter> hotkeys are forwarded; other modifier combos
  (⌃⇧X, etc.) stay on the Carbon direct-trigger path with no
  hold-preview support because the gesture only makes sense when
  the user could plausibly keep ⌥⌘ held after the chord.
- `EventTapEngine.schedulePendingActionFire(actionID:)` —
  intercepts the chord in `handle()` (CGEventTap callback,
  background thread). Sets a pending-action ID, generation
  counter, and dispatches a 250 ms grace timer on the main queue
  via `DispatchQueue.main.asyncAfter`. Subsequent chord presses
  within the window cancel the prior pending fire (the user
  switched intent) and start a new one.
- Modifier-release detection in `handle()`'s `flagsChanged` branch
  (existing code path used by ⌥⌘V): when `hudIsActive == false`
  and a pending action fire is queued, checking `!modsPresent`
  fires the action immediately via
  `hotkeyEngineDidFireActionHotkey(actionID:, holdPreview: false)`.
  Generation counter validates the pending fire is still current
  before consuming it.
- Grace expiry callback: same generation check, then sets
  `hudIsActive = true` (so the next ⌥⌘ release flows through the
  existing release-to-commit path) and fires
  `hotkeyEngineDidFireActionHotkey(actionID:, holdPreview: true)`.
- Thread safety: all mutation of `pendingActionID` and
  `pendingFireGeneration` happens through a dedicated
  `pendingFireQueue: DispatchQueue` so the CGEventTap thread and
  the main-queue grace block can't race.

**AppDelegate routing**

- New `HotkeyEngineDelegate.hotkeyEngineDidFireActionHotkey(actionID:,
  holdPreview:)` method. AppDelegate's implementation dispatches to
  the existing direct-paste path (`actionHotkeyDidFire(actionID:)`)
  when `holdPreview == false`, or to a new
  `openHUDFocusedOnAction(actionID:)` when `true`.
- `openHUDFocusedOnAction(actionID:)` — opens the HUD panel with
  `itemIndex = 0` (freshest history clip) and `actionIndex` pointing
  at the focused action (falls back to 0 if the action isn't in the
  applicable list for that semantic kind). Reuses `showPanel()`,
  `refreshPreview()`, `updateContentMeta()` from the existing
  gesture-mode summon path. The EventTap engine has already set
  `hudIsActive = true` by the time this runs, so the user's
  subsequent ⌥⌘ release flows through the standard
  `flagsChanged → hotkeyEngineDidRelease → commit` path exactly
  like a normal ⌥⌘V session.
- `reloadHoldPreviewMap()` — pushes the current ⌥⌘<letter> map to
  the EventTap engine. Called from initial setup
  (`applicationDidFinishLaunching`), `ActionRegistry.config.didSet`
  (Settings save / hotkey rebind), and `Factory Reset`.

**Carbon coexistence (no Limited Mode regression)**

- `ActionHotkeyManager` keeps registering every per-action hotkey
  via Carbon `RegisterEventHotKey` exactly as before.
  CGEventTap's `.headInsertEventTap` placement runs strictly before
  Carbon's hotkey distribution; when EventTap returns nil for a
  ⌥⌘<letter> chord, Carbon never sees the event and the
  Carbon-registered hotkey doesn't double-fire.
- In Limited Mode (no AX permission → no EventTap → Carbon-only),
  per-action hotkeys still work exactly as before — instant paste,
  no hold-preview. Users without AX permission see the existing
  behaviour, no degradation.

**Welcome window — discoverability**

- Key features grid caption updated: "Per-action hotkeys — direct
  trigger, or hold ⌥⌘ to preview in HUD". Single-line teaser on
  first launch, surfaces the feature to users who haven't set up a
  per-action hotkey yet.
- Hotkeys section — new conditional row appears below the four
  system rows ONLY when `registry.config.actionHotkeys` is non-empty:
  "⌥⌘<key>  Custom action hotkeys — tap for instant paste, or keep
  ⌥⌘ held after the key to preview in HUD". Guarded so cold-start
  users without any custom hotkeys configured don't see a hint they
  can't act on yet; the row materialises the moment they bind their
  first hotkey.

**Limitations (acknowledged)**

- The grace timer is from chord PRESS to modifier RELEASE rather
  than letter RELEASE to modifier RELEASE (the spec's original
  framing). The difference in practice is small (~80 ms of letter-
  hold time gets folded into the 250 ms window), and the simpler
  model halves the state-machine surface area.
- Hold-preview is Full Gesture Mode only. Limited Mode (Carbon-only,
  no AX) keeps Direct-trigger semantics — there's no flagsChanged
  signal available without an EventTap, so the grace mechanism
  can't run. This is consistent with how every other gesture-mode
  feature in DrPaste (⌥⌘V hold to browse, ⌥⌘S in-HUD accumulator,
  ⌥⌘Space chain) degrades to "single-press hotkey" in Limited Mode.

### 0.17.0 — Destructive ops belong in editors, not lists

Two surface-area trims that follow the same principle: destructive
operations and ambient catalogues live behind editors, not as ambient
controls in the main list. Both bring the AI providers tab and the
Actions tab in line with the design philosophy recorded in 0.12.0.

**Delete moved inside the provider editor**

- The row-level trash button next to each provider in Settings → AI
  was the third destructive action exposed on the row (after the
  also-removed enable Toggle and the still-present Edit). One
  accidental click and the user's saved API key, configured model,
  and base URL were all gone — no confirmation, no undo. The row is
  now bipolar: radio (set default) and Edit (or Setup). That's it.
- Delete reappears inside `ProviderEditor`'s footer as a left-aligned
  destructive button, mirroring the action editor pattern shipped in
  0.12.0 ("destructive gravity inside the dialog"). A confirmation
  dialog explains the consequence: the provider's API key and
  configuration go away, AI actions following the default fall back
  to the next configured provider, no undo.
- New `ProviderEditorResult.delete: Bool` carries the editor's
  decision back to the parent sheet handler, which routes through
  `providerRegistry.remove(...)` and clears the row's live-status
  entry. Mutually exclusive with a Save result — same struct, three
  exit states (cancel / save / delete).

**Browse button removed from the Actions tab**

- The Browse button next to the Actions list opened a categorized
  palette of every available action grouped by content kind. It was
  useful before 0.12.0 because the main list hid disabled rows; an
  "everything in one place" view was the only way to find and enable
  a disabled action. 0.12.0 changed the unified list to show
  disabled rows greyed-out alongside enabled ones, so the same one-
  click enable now lives in the row's own checkbox — no extra
  navigation.
- After the unified-list ship, Browse was strictly a duplicate
  navigation layer for the same outcome. Removed per UX cleanup.
  `ActionPaletteSheet.swift` is left in place as a tombstone with a
  comment pointing at this entry so future readers of the codebase
  see the deliberate removal rather than a "where did it go?"
  mystery. The file can be hard-deleted from disk once the SwiftPM
  source enumeration moves to path-only.

### 0.16.0 — Provider list overhaul: live health, brand icons, fewer footguns

Targeted cleanup of Settings → AI after a real-world bug where an
unlabeled per-row Toggle silently disabled a provider on accidental
click and the user wasted time staring at "API key required" errors
when the key was perfectly fine. Three changes lift this surface from
"functional but easy to break" to "self-explanatory and self-healing".

**Per-provider enable / disable Toggle removed**

- The tiny unlabeled Toggle wedged between the Edit and Trash buttons
  was a UX trap. Users had no obvious cue what it did, and a misclick
  silently flipped a provider to `enabled: false`, which gated it out
  of `provider(id:)` lookups and produced misleading "missing API key"
  errors at test time. Provider lifecycle is now cleanly bipolar:
  configured (visible in the list) or removed (via the trash button).
  No third "exists but disabled" state to misunderstand.
- The `enabled` field stays on `ConfiguredProvider` for backward
  compatibility with existing `providers.json` files, but is now
  invariantly `true`. A one-shot migration runs at registry init
  (`enableAllProviders()`) and forces every provider's `enabled` to
  `true` on first launch of 0.16.0, so users who got bitten by the
  accidental flip recover automatically without manual JSON editing.
- The previous self-healing `enabled = true` writes in
  `saveWithTest` and `runTest` remain, defensively, so anything that
  somehow re-introduces a `false` value gets cleaned up on the next
  Edit interaction too.

**Brand icons on every provider row**

- Each provider row now shows its brand icon (existing
  `ProviderKind.iconName` from the HUD action list) to the left of
  the display name: `a.circle.fill` (Anthropic) /
  `circle.hexagongrid.fill` (OpenAI) / `sparkle` (Gemini) /
  `x.circle.fill` (Grok) / `wind` (Mistral) /
  `magnifyingglass.circle.fill` (DeepSeek) / `desktopcomputer`
  (Ollama) / `laptopcomputer` (LM Studio) / `terminal.fill`
  (llama.cpp) / `gearshape.fill` (custom).
- New `ProviderKind.brandColor` mirrors the badge palette used in
  the HUD chip rows so the same brand visual identity holds across
  Settings and HUD — orange Anthropic, green OpenAI, blue Gemini,
  purple Mistral, indigo DeepSeek, gray local providers.
- The user can now spot which AI is which at a glance without
  reading the name — useful when several similarly-named providers
  (custom endpoints, two OpenAI-compatible URLs, etc.) coexist.

**Live connection-health dot**

- The static green-when-ready dot was misleading — it only tracked
  "has a saved key" and gave no signal about whether that key still
  works. The dot is now driven by `testConnection` results:
  - **gray** — never tested (fresh install, just added a provider,
    cleared local state)
  - **yellow spinner** — probe in flight
  - **green** — last test passed
  - **red** — last test failed (hover for the reason: "HTTP 401",
    "Network unreachable", "HTTP 429", etc.)
- Probes fire automatically when the AI tab opens (`.task`
  modifier) and after every successful Save in the provider editor.
  Configured cloud providers and local providers with a base URL
  are tested; unconfigured providers stay gray (no point probing
  them).
- Each provider's probe runs in its own task inside a
  `withTaskGroup` so slow providers (a flaky Mistral endpoint,
  say) don't block the row updates for fast providers (Anthropic
  in 200 ms).
- Probes reuse the existing `testConnection` path which sends a
  one-line "ping" prompt — cheap, doesn't burn meaningful tokens,
  and exercises the same code path that real AI actions use, so a
  green dot genuinely means "actions through this provider will
  work right now".

**Visible self-healing on the bug that triggered this release**

- The user who hit the disabled-Toggle bug needed to either know to
  manually toggle Anthropic back on, or edit `providers.json` by
  hand. With 0.16.0:
  1. The Toggle that caused the bug no longer exists.
  2. The migration forces every persisted provider to `enabled =
     true` on launch.
  3. The live status dot would have shown a clear gray (never
     tested → not configured) instead of a misleading red message
     about API keys when the field was full.
  4. The brand icon makes the row visually distinct from a "Setup"
     placeholder, so the dialog's "Test connection" surfacing
     "missing API key" against a row that visibly has an Anthropic
     brand icon would have raised the right question
     ("why is it disabled?") instead of the wrong one ("why is the
     key empty?").

### 0.15.0 — Key storage hardening, provider onboarding polish

Small, focused release. Two themes — both about the API-key surface
inside Settings → AI. First: stop fighting Keychain in unsigned builds
by routing every key to the JSON fallback unconditionally (the
existing per-user toggle was a half-measure that still tripped the
login-password prompt on launch). Second: cut the friction in setting
up a new provider by linking directly to that provider's API-key
console from inside the editor.

**Keychain disabled across the board (#A1 will restore)**

- `APIKeyStorage` now routes every save / load / remove to the plain
  JSON fallback file at
  `~/Library/Application Support/DrPaste/provider-keys-fallback.json`
  (user-only `0o600` permissions). The Keychain code paths in all
  three functions are preserved verbatim as `/* ORIGINAL KEYCHAIN
  CODE — restore in #A1 ... */` block comments so the reactivation in
  #A1 is mechanical: remove the comment markers and the temporary
  early-return `return saveFallback(...)`, flip `fallbackOnly` back
  to reading `UserDefaults`, and the original behaviour returns.
- The "Skip macOS Keychain" toggle in Settings → AI is hidden behind
  a short informational notice that tells the user where keys live
  in 0.15.0 and confirms Keychain integration returns with the
  signed `.app` distribution. The `keyStorageSection` view is left
  defined in source so re-enabling is a one-line uncomment when #A1
  ships.
- Export / Import / Replace dialog copy revised to drop the "kept in
  Keychain" framing that became misleading after this change. New
  copy: "API keys are kept separately and never written to the
  export" / "Your stored API keys are not touched".
- #A1 release-day checklist updated with the concrete restoration
  steps and a JSON-file → Keychain migration prompt for first signed
  launch, so users who already have keys in the fallback file get
  moved into Keychain cleanly without re-entering them.

**Provider editor — "Get an API key" deep link**

- Every cloud provider now exposes an `apiKeyDocsURL` that deep-links
  to the provider's API-key console page (not their marketing front
  door). Six providers covered:

  | Provider | Link target |
  |---|---|
  | Anthropic | `console.anthropic.com/settings/keys` |
  | OpenAI | `platform.openai.com/api-keys` |
  | Gemini (Google) | `aistudio.google.com/app/apikey` |
  | Grok (xAI) | `console.x.ai/team/default/api-keys` |
  | Mistral | `console.mistral.ai/api-keys` |
  | DeepSeek | `platform.deepseek.com/api_keys` |

- `ProviderEditor` shows a `🔑 Get an API key from <Provider Name> →`
  link directly under the API Key field, indented to match the other
  form rows so the visual rhythm stays consistent. The link only
  appears when `apiKeyDocsURL` is non-nil, so local providers
  (Ollama, LM Studio, llama.cpp) and the kind-agnostic `.custom`
  endpoint type don't show it — they don't need a key.
- Rationale: most providers bury the API-key console several clicks
  deep under "Documentation" or "Developer", with the term spelled
  differently each time ("API keys" / "API keys & tokens" / "Access
  keys"). The deep-link saves an internet search every time the user
  configures a fresh provider.

### 0.14.0 — Streaming AI responses

AI actions now stream their responses into the HUD preview pane token
by token instead of producing a single opaque wait followed by the full
result. Same provider list as 0.13.0 (Anthropic, OpenAI, Grok, Mistral,
DeepSeek, Gemini, Ollama, LM Studio, llama.cpp, custom OpenAI-compatible);
every one of them now streams.

**Why this matters**

- Live-feedback: the user sees the translation / summary / rewrite
  materialise word by word; the spinner disappears the moment the first
  token arrives. No more staring at a 20-second wait wondering whether
  the request is alive.
- Offline-tolerant: when a flaky connection cuts mid-stream (planes,
  trains, hotel Wi-Fi, conference networks), the partial content that
  already arrived is surfaced as a recoverable preview. A 60 %
  translation is still 60 % useful — the user can read it, copy it,
  chain it into ⌥⌘Space, or commit it directly into the target app.

**Protocol layer**

- New `AIProvider.stream(prompt:input:) -> AsyncThrowingStream<String, Error>`
  declared on the protocol with a default extension implementation
  that wraps the existing `run()` and emits the whole result as a
  single chunk. Providers without native streaming continue to work
  unchanged; only the user-facing perception of "live" requires the
  override.
- New `ClipboardAction.applyStreaming(item:context:onPartial:)`
  declared on the protocol so dynamic dispatch picks up the AIAction
  override even when called through a `ClipboardAction` existential.
  Default extension falls back to `apply()` and produces no
  intermediate updates, so local transformations, image actions, and
  files actions keep working identically.

**Provider implementations**

- `AnthropicProvider.stream` — `/v1/messages` with `stream: true`,
  parses SSE `event: content_block_delta` lines for
  `delta.text` chunks.
- `OpenAICompatibleProvider.stream` — single implementation that
  covers **eight providers** in one shot: OpenAI proper, xAI Grok,
  Mistral, DeepSeek, Ollama (OpenAI mode), LM Studio, llama.cpp,
  and the custom OpenAI-compatible endpoint type. SSE
  `data: { choices: [{ delta: { content: "…" } }] }` with a
  `data: [DONE]` terminator.
- `GeminiProvider.stream` — `:streamGenerateContent?alt=sse`
  variant, parses `data: { candidates: [{ content: { parts: […] } }] }`
  per chunk. Multiple text parts per chunk are yielded sequentially
  to keep the consumer logic simple.

**HUD wiring**

- `AIAction.applyStreaming` consumes the provider's stream, builds
  partial ClipboardItems from the accumulating text, and surfaces
  them to the HUD through an `@MainActor` `onPartial` callback. The
  HUD's preview pane flips `isPreviewLoading` to false on the first
  token (spinner gone) and refreshes the text on every subsequent
  one. `previewToken` check inside `onPartial` discards updates from
  any stream the user has navigated away from.
- During streaming the partial preview is always rendered as plain
  text (`semantic = .text`), even for rich-text-preserving actions.
  This keeps SwiftUI's Text view re-render cheap at token rate.
  The final outcome rehydrates rich text via
  `RichTextHelpers.markdownToAttributedString` exactly once at
  completion, so NSTextView reflow only happens at the end.
- New `aiStreamingTask: Task<Void, Never>?` field on AppDelegate
  tracks the outstanding stream. Cancellation fires in two places:
  on every fresh `refreshPreview()` call (the user navigated to a
  different action mid-stream — stale stream is no longer
  meaningful) and inside `closeHUD()` (HUD closed). Cancellation
  cascades through the `AsyncThrowingStream.continuation`'s
  `onTermination` hook into the underlying URLSession data task,
  closing the connection promptly so the provider stops billing for
  unconsumed tokens.

**Heartbeat and offline-tolerance**

- Shared `StreamingHTTP.session` with
  `timeoutIntervalForRequest = 15` gives every streaming request a
  native heartbeat: URLSession resets the timer on every received
  byte, so 15 idle seconds without any chunk throws
  `URLError.timedOut`. Reused across all three concrete provider
  implementations so the behavior is uniform — no per-provider
  tuning, no Settings UI for the timeout (15 seconds is plenty for
  any reasonable model).
- `applyStreaming`'s catch path distinguishes the heartbeat-hit
  ("Stream stalled — N chars received, no further data for 15 s")
  from a hard mid-stream drop ("Stream interrupted — N chars received:
  &lt;reason&gt;"). Both surface accumulated content as
  `.failed(original: partialItem, …)` so the partial is still
  available to copy, chain, or commit.
- `timeoutIntervalForResource = 600` (10 minutes) is the hard ceiling
  for any single response — generous but bounded against runaway
  requests.

**Compatibility**

- Existing actions, providers, and tests all keep working. The only
  visible change for non-streaming providers (none after this
  release, but the architecture supports adding one without breaking
  others) would be a single-chunk emission on completion via the
  default extension — semantically identical to the current
  experience.

### 0.13.0 — Fancy text, image polish, HUD super-powers

A heavily user-driven cycle. The action surface grew by 25 entries
covering Unicode pseudo-fonts, Cyrillic transliteration, and ASCII art;
the HUD gained two foundational shortcuts (in-HUD clip accumulator with
a green carrier, and ⌥⌘Space chain-preview) that turn the HUD into a
miniature workspace instead of a one-shot picker; image actions stopped
showing stale previews; the Welcome screen tightened up and now does
its own visual demo of Fancy Unicode as a marketing line.

**Action surface — Fancy text and friends**

- 22 Unicode pseudo-font actions covering the full Math Alphanumerics
  block plus enclosed / fullwidth / small-caps / upside-down: Bold,
  Italic, Bold Italic, Script, Bold Script, Fraktur, Bold Fraktur,
  Double-struck, Sans, Sans Bold, Sans Italic, Sans Bold Italic,
  Monospace, Fullwidth, Small Caps, Circled, Filled Circled, Squared,
  Filled Squared, Upside Down, and Plain ASCII (the reverse pass that
  strips any styled Unicode back to plain Latin via NFKC + a custom
  reverse map for upside-down / small-caps). Titles use the styled
  glyph itself as the prefix so each action shows what it produces:
  "𝐀 Bold", "𝒜 Script", "𝔄 Fraktur", "𝒜 → ABC Plain ASCII". All
  applicable to plain `.text` only — decorative glyphs don't belong
  in code, URLs, or markdown where exact characters matter. Curated
  on by default; one engine (`TransformationEngine.unicodeStyle`),
  one style picker in the editor with live samples per option.
- "Unicode Fancy" — standalone Rich Text action that walks rich-text
  runs and renders bold runs as Unicode Bold (𝐁𝐨𝐥𝐝), italic as
  Italic (𝐼𝑡𝑎𝑙𝑖𝑐), bold-italic as 𝑩𝒐𝒍𝒅 𝑰𝒕𝒂𝒍𝒊𝒄, monospace runs as
  𝙼𝚘𝚗𝚘𝚜𝚙𝚊𝚌𝚎. Result is plain text that preserves emphasis in
  platforms with no rich-text formatting (Twitter / X, Telegram bios,
  LinkedIn captions, Discord profile descriptions). Only applies to
  `.richText` so it never clutters plain-text HUD chip rows.
- "К → K Cyrillic transliteration" with auto-detected script variant.
  Heuristic by marker letters: ћ ђ ј љ њ џ ѓ ќ ѕ → Serbian / Macedonian
  (Gaj's Latin: ж→ž, ч→č, ш→š, х→h, ц→c, plus the script-specific
  letters); ъ without ы/э/ё → Bulgarian (Streamlined 2009: щ→sht,
  ъ→a, ь→y); є ї ґ → Ukrainian extensions; ў → Belarusian; default
  Russian digraphs (zh, ch, sh, kh, ts, shch). Preserves word case by
  scanning the nearest Cyrillic neighbour — "Привет" → "Privet",
  "ПРИЩУР" → "PRISHCHUR" (not "PRIShchUR"). Chains beautifully into
  the Fancy Unicode actions: paste Cyrillic name → transliterate →
  ⌥⌘Space → "𝐀 Bold" → styled Latin output.
- "ASCII art" — local tonal-density renderer for small images.
  Rasterizes the source to a 100-column grayscale grid, applies a
  brightness threshold so light backgrounds (white, mint, beige) become
  whitespace instead of a sea of dots, maps the remaining range to a
  density gradient (" .:-=+*#%@" with the lightest slot reserved for
  background), then auto-crops to the bounding box of non-space cells.
  Tight result that frames the subject. Chains nicely with "Wrap in
  code block" via ⌥⌘Space for Discord / GitHub posting. No AI required.

**HUD super-powers**

- In-HUD clip accumulator on ⌥⌘S, redesigned to the "walking carrier"
  model. First press anchors the focused clip and paints it green
  (distinct from the standard accent-blue focus highlight). The user
  can then navigate up / down without dropping the accumulator (consumed
  rows skip automatically). Pressing ⌥⌘S on a *different* clip folds
  the previous carrier into `consumed` (visually removed from the list)
  and the newly focused clip becomes the new carrier showing the
  merged text right in its own row. Pressing ⌥⌘S on the same green
  carrier toggles the accumulator off — consumed rows reappear, green
  vanishes, preview reverts. Commit pastes the merged text; close /
  Esc discards.
- ⌥⌘Space — promote current preview to a new history clip placed
  one row above the focused position. Enables chained transformations
  without leaving the HUD: pick clip → apply action → ⌥⌘Space →
  result becomes a real history item → apply another action → ⌥⌘Space.
  Skips silently when no `.preview` outcome is available (e.g. AI still
  loading); preserves image metadata so image-chain workflows (resize →
  grayscale → strip metadata) don't lose pixel dimensions.
- Backspace honours the accumulator. Deleting a clip while a merge
  is active now correctly shifts `consumed` indices and decrements
  `anchorIndex` so the green carrier stays on the same logical row.
  Deleting the carrier itself drops the entire accumulator (no clean
  way to re-anchor). Cursor repositions onto the next visible row,
  skipping any consumed rows that would otherwise feel like a stuck
  cursor.
- HUD footer key legend now lists `S merge` and `␣ chain` alongside
  the existing navigation / delete / paste / esc / zoom hints. Hints
  use bare keys because the modifiers are either implicitly held
  (Gesture Mode: ⌥⌘V is the open-gesture), or absent altogether
  (Limited Mode: the HUD has no text-input context, so bare letters
  read as commands). Limited Mode local key monitor accepts both bare
  S and ⌥⌘S, bare Space and ⌥⌘Space — covers muscle memory either way.
- Removed the "tap" badge from the HUD header (next to the close-X).
  It was the internal `HotkeyEngineKind` raw value surfaced as a tiny
  monospace chip — dev-jargon that read like "tab" at the rendering
  size. Mode is already conveyed by the footer's `release` vs `⏎`
  paste hint, so the badge had no remaining purpose.

**Image actions**

- "Grayscale", "Invert", "Rotate", "Resize", "Compress JPEG", "Strip
  metadata" — all previously displayed the *pre*-transformation image
  in the HUD preview pane. Root cause: `saveImage(_:originalItem:)`
  uses `var copy = originalItem` which preserves the source UUID; the
  HUD's `ImagePreview` view keyed `.id(item.id)` and SwiftUI saw the
  transformed item as the same view it had already rendered, so it
  reused the cached `Image(nsImage:)` and the new PNG file was never
  loaded. Fixed by extending the SwiftUI identity key to include
  `previewImageRel` (which always changes per transformation result).
- "Rotate right (90° CW)" and "Rotate left (90° CCW)" — added the
  left rotation as a peer to the existing right rotation. Both share
  a `rotateImage(_:radians:)` primitive that translates the CIImage
  extent back to (0, 0) before rasterizing, so the saved PNG is tight
  to the rotated content with no transparent border. Both curated.
  Title clarified: "Rotate 90° CW" → "Rotate right (90° CW)".

**Multi-monitor**

- Both the main HUD and the ProgressHUD mini-window now position
  themselves relative to the mouse cursor's screen instead of
  `NSScreen.main`. `NSScreen.main` returns "screen with the focused
  key window", which is fine in Gesture Mode (DrPaste never grabs
  focus) but can land on the wrong display in Limited Mode after
  `NSApp.activate(ignoringOtherApps:)`. The cursor's screen is the
  most reliable signal for "where the user is actually working right
  now".
- ProgressHUD positions ~30 pt above the cursor, centered horizontally,
  clamped to the active screen's visible frame with an 8 pt margin.
  Keeps the spinner inside the user's visual focus area so they don't
  have to glance across the display to confirm the hotkey fired. Main
  HUD continues to center on the cursor's screen (it's too large for
  cursor-relative placement to make sense).

**Welcome screen polish**

- "Key features" and "Hotkeys" sections rebuilt with SwiftUI Grid for
  consistent column alignment. Emoji icons (📋✨🛠⌨🖼🌐) had ragged
  widths that pulled the text column out of line; replaced with cleanly
  sized SF Symbols in a fixed-width icon column.
- New "Fancy Unicode" feature row that demonstrates itself: the row
  text reads "𝐅𝐚𝐧𝐜𝐲 𝐔𝐧𝐢𝐜𝐨𝐝𝐞 — paste 𝑩𝒐𝒍𝒅, 𝐼𝑡𝑎𝑙𝑖𝑐, 𝒮𝒸𝓇𝒾𝓅𝓉
  anywhere (Twitter, Telegram, LinkedIn)" using the actual Unicode
  pseudo-fonts the action produces. Marketing line that visually
  proves the feature on the welcome screen itself.
- Hotkey grid limited strictly to the four system-level shortcuts
  (⌥⌘V, ⌥⌘C, ⌥⌘X, ⌥⌘S) plus the user's custom action hotkeys. HUD-
  internal shortcuts (S, ␣, ↑↓, ←→, ⌫, ⌘+/-) live in the HUD footer
  where they have context. The welcome window now respects the
  "system hotkeys here, HUD hotkeys there" boundary.
- Custom action hotkey rows use uniform 64 pt key badges with light
  borders so combinations of different glyph widths align in the same
  column.

**Migrations**

- Existing 0.12.0 installs had 22 `builtin.font_*` descriptors with
  "Font: <Style>" titles and `applicableTypes = [text, markdown, code]`.
  Seed version bumped to 4; new launch runs `rebrandFancyTextIfNeeded`
  which: replaces titles that still match the old factory default with
  the new stylized-glyph prefix; narrows applicableTypes from the
  legacy seeded set to `[text]` only if it's still the exact legacy
  set (so any user customization survives); deletes the
  `builtin.font_regional_indicator` entry outright (boxed regional-
  indicator letters were unreadable as a curated default). User-set
  custom titles and hotkeys are preserved across the rebrand.
- `BuiltinActionIcons.iconName(for:)` now returns `textformat` for
  any `builtin.font_*` id via a hasPrefix check at the top of the
  function. Avoids 22 case-by-case mappings; the engine icon is
  uniform across the fancy-text family.

**Reliability fixes**

- ⌥⌘Space chain-preview was rejecting every transformed outcome.
  Root cause: `makeTextItem(_:from:)` copies the source ClipboardItem
  with the same UUID, and the original guard rejected any preview
  whose `id` matched the focused item. So every transformation
  preview hit the "no change, no-op" failure beep. Fixed by removing
  the UUID-equality guard — the promoted clip gets a fresh `UUID()`
  at insertion time so duplicates are impossible by construction.
- Limited Mode `S` / `Space` bare-key handling correctly masks
  `event.modifierFlags` with `.deviceIndependentFlagsMask` before
  checking for "no modifiers held", avoiding stray device-level
  flags that would otherwise prevent the bare-key path from firing.

**Internal naming and renames**

- "Rich → Unicode style" (the standalone Rich Text action) renamed
  to "Unicode Fancy" to match the marketing line used on the Welcome
  screen and the popular term users actually search for. Action ID
  unchanged (`builtin.rich_to_unicode_style`) so existing hotkeys
  and enabled flags carry over.
- HUD accumulator data model documented as a "walking carrier" with
  `consumed: Set<Int>`, `anchorIndex: Int`, `text: String`. Previous
  indices-array model from the original 0.12.0 implementation was
  replaced wholesale per the user's UX redesign.

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
