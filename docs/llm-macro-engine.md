# DrPaste — LLM-authored macro engine (design exploration)

> ⚠️ **CONDITIONAL / NOT COMMITTED.** This is a captured design exploration,
> recorded **only in case we decide to build the LLM-macro direction.** Nothing
> here is a committed plan, a scheduled feature, or an approved architecture. No
> code exists for any of it. If and when we commit, the actionable scope lives in
> `BACKLOG.md` items **#A88** (declarative IR, v1) and **#A89** (Lua escape-hatch,
> later). This document holds the full reasoning behind those items so a cold
> reader (or a future model) can reconstruct *why*, not just *what*.

---

## 1. Origin: the problem with the current Actions UI

DrPaste's Settings expose a complex, per-content-kind Actions surface (tabs for
plain text, rich text, URL, JSON, table, markdown, code, image, files; each with
its own action list, AI-prompt editors, transformation builders). It works, but
it is a lot of UI, and every new capability grows it.

The opening idea: replace that with a single **universal "macro" window** where an
action's behaviour is expressed as *code* — one uniform mechanism for everyone:
trait handling, built-in functions, parameterised steps, prompts, regexes, all as
code. Candidate languages: **Lua** or **WASM**.

## 2. The decisive pivot: the author is the AI, not the user

The user should **never write code**. They describe, in natural language, the
action they want. An LLM assembles the macro and reports "done." Code (Lua / IR /
whatever) becomes a **hidden implementation detail**, not a language the user
learns.

This single decision reframes every downstream choice. Normal language/DSL design
optimises for *human* authors. Here the human never sees the code, so human
ergonomics are irrelevant. What matters instead:

1. How reliably an **LLM** can generate correct code for it.
2. How cheap and safe it is to **execute**.
3. How well the representation supports the **feedback / self-repair loop** and
   the **backend mining** (see §8).

## 3. Lua vs WASM — and why WASM essentially drops out

Two different layers were considered:

- **Lua** — for *authoring*. Tiny, embeddable, synchronous, instant startup,
  sandboxable out of the box. The natural target for "assemble a small transform"
  (Hammerspoon, Neovim, Redis, game scripting all use it). LLMs write Lua well —
  huge training corpus (Roblox, Neovim, WoW addons).
- **WASM** — for *compiled, distributable plugins* (bring a binary from any
  language, strong isolation). But the author would need a toolchain to compile,
  string/image marshalling across the boundary is painful, and **LLMs do not
  write WASM/WAT by hand**. Shipping an in-app Rust/AssemblyScript compiler just
  to host LLM output is absurd.

With the author being an LLM, **WASM all but disappears**. It only ever returns
for heavy number-crunching, which is a distant "maybe." For this vision:
**Lua-only, and even Lua is demoted to a rare escape hatch (see §6).**

## 4. The core conceptual win: authoring-time AI vs runtime AI

Today an "AI action" calls the LLM on **every run** — slow, paid per use, online,
non-deterministic. The new category is fundamentally different:

| Action type | LLM runs… | Runtime speed | Cost | Offline | Deterministic |
|---|---|---|---|---|---|
| Built-in (Swift) | never | instant | 0 | yes | yes |
| AI action (today) | every run | slow | $ per run | no | no |
| **AI-authored macro** | **once, at creation** | **instant** | **0 after authoring** | **yes** | **yes** |

A large share of what people do as runtime-AI actions (reformat, extract by
pattern, regex-style transforms) does **not need an LLM at runtime** — only once,
to *write* the transform. This moves a big chunk of runtime cost and latency
toward **zero**. That is the strategic prize, not mere convenience.

## 5. Do we even need a full language? — declarative IR as the primary form

The sharpest question raised: if `match` can be a declarative predicate, maybe
`run` can too — maybe a Turing-complete language isn't needed at all.

Answer: as the **primary** form, no — and declarative isn't merely "enough," it
makes the **whole surrounding system** better. The two halves of a macro are the
same family:

- **`match` = a filter.** A laconic **declarative predicate over pre-computed
  traits** (the existing central trait pass): "when to show this action / apply
  this macro." Runs on the hot path — every focused clip × every macro while
  ⌥⌘V is held — so it must be near-instant and memoised per clip. Never arbitrary
  code.
- **`run` = the processing.** A **pipeline of typed pure operators** from a
  curated catalog, plus `conditional` (when → sub-pipeline) and `map-over-items`
  (per line / element).

Same IR, two return types: `match` returns bool/score, `run` returns content.
Collapsing both into one declarative representation buys one grammar, one sandbox
story, one mining pipeline, one NL-renderer.

### Why declarative is primary (five reasons, all amplified by "author = LLM")

1. **Static verifiability** — the IR can be validated (operators exist, args
   type-check) *before* running. A much stronger correctness gate than
   dynamically testing arbitrary code and hoping.
2. **Mineable for the flywheel** — a normalised operator list clusters and
   generalises on the backend; arbitrary code ASTs do not (see §8).
3. **Cost dedup** — a structural hash of the IR is stable, so two differently
   phrased NL requests that yield the same pipeline hit the same cache entry
   (zero LLM calls — see §7).
4. **Precise self-repair signal** — "operator 3 `regex_extract` produced empty on
   the sample" is a far better repair prompt than a Lua stack trace.
5. **Free NL explanation** — "extract emails → dedupe → lowercase" renders the
   trust moment ("done; here's what it does") for nothing.

### Control-flow boundary

Allowed in the declarative tier: `conditional` and `map-over-items`. **Forbidden:
unbounded loops and recursion** — and that line is exactly the trigger for the
Lua escape hatch. "Needs unbounded iteration → you are no longer declarative."
Clean and defensible.

## 6. Lua as one node type — the frontier, not the language

~10% of transforms are genuinely algorithmic and a finite operator catalog
cannot express them without becoming a de-facto language:

- arithmetic (unit conversion — already bit us: #A20, time boundaries, stone
  parsing),
- real parsers (CSV with quoted fields containing commas),
- state machines (bracket balancing, smart-quote pairing),
- unbounded iteration (renumber a nested markdown list).

Resolution — you do **not** choose declarative XOR Lua. **Lua becomes one node
type inside the declarative pipeline** (`{ lua: "…" }`). 90% of the graph stays
pure declarative (safe, mineable, explainable); the tail drops into a sandboxed
Lua node without abandoning the structure.

Better still: most of the tail is "no operator exists for this," not "needs
Turing-completeness." Each such need is one high-level **native** operator
(`unit_convert`, `parse_csv`, `roman_numeral`) implemented in Swift. So the
escape hatch is also a **frontier signal**: frequent Lua nodes are clustered on
the backend and the common ones are **promoted to vetted native operators**, so
the Lua share **decays over time**. Lua = frontier; native operators = settled
territory. The system trends toward *more* declarative, not bloat-rot.

**Start declarative-only.** Add the Lua node only when the catalog empirically
falls short.

## 7. Cost control

Generation goes through the user's **already-configured AI provider** — both
ways:

- **BYOK** (user's own key/model) — unlimited, the user pays.
- **Our hosted provider** — must be **metered** (free tier + upsell), or per-seat
  monthly economics break. Ties into the monetization section of `BACKLOG.md`.

The real lever, though, is **dedup-against-library before calling the LLM**:
embed the NL request, match it against the accumulated macro library, and serve a
ready macro when one fits ("looks like you want X — here it is", instant, free).
So the self-tuning library (§8) is *also* a cost-reduction mechanism: the more it
grows, the fewer novel generations are needed. Plus a hard **cap on self-repair
iterations (≈3)**.

## 8. The federated self-tuning flywheel (the moat)

Wrapping an LLM to emit a transform is trivial — anyone can. The defensible asset
is an **accumulated, usage-validated, auto-generalised macro library + ranking
signal** that compounds and can't be copied.

Mechanism (strictly **opt-in**):

- **Telemetry = macro SIGNATURES only** — normalised IR + match predicate +
  usage counts. **NEVER** the clipboard content, **NEVER** the raw NL spec (both
  can carry PII). The signature format must be designed so the user's buffer is
  physically unreconstructable. *Leak the clipboard and the project dies in a
  day.*
- **Clustering** — embed the (scrubbed) spec + normalise the IR → cluster
  "many users build extract-emails → dedupe."
- **Auto-generalisation** — promote common clusters into vetted **native
  operators** / shipped built-ins, **quality-gated** against a test battery,
  **versioned**, with **rollback**. Generalised macros arrive as **new suggested
  built-ins that coexist** with the user's local one — never overwrite local
  edits.
- **Ranking & pruning** — usage drives default ordering (data-driven, extends
  #A85) and demotion/removal of dead macros, **with an exploration allowance** so
  brand-new, never-used macros still get a chance to surface (exploration vs
  exploitation / cold-start — don't freeze on today's popular set).

Net effect: library growth **raises quality and lowers our generation cost at the
same time**, while pruning trims the tail. A rare case where unit economics
*improve* over time.

## 9. Verification harness (already mostly built)

The existing **per-action playground / sample system** is the closed loop that
makes LLM-generated code trustworthy:

NL spec → model emits IR → **static-validate** → **run on the content-kind
sample(s)** → **show live preview on the user's clip** → **self-repair** on
validation/empty/error (cap ≈3). The user accepting the live preview *is* the
acceptance test — and DrPaste already renders previews live while ⌥⌘V is held.

## 10. Fallback ladder

Prefer a **local declarative macro**. If the intent cannot be compiled into the
catalog → fall back to a **runtime-AI action**. The system always returns
something usable; "can't compile it offline → I'll run it as a live AI action."

## 11. Precedent

iOS Shortcuts, Zapier, n8n, Automator, Pipedream all converged on a **declarative
action-graph + an optional code node**. The ones that went full-code (Hammerspoon,
AutoHotkey) target a **human power-user** who wants control — not our case
(LLM author + non-coding user). The convergence lands exactly on "author is not
the power-user → declarative + a confined escape hatch."

## 12. Decisions taken in this discussion

- **v1 = declarative-only**, including `conditional` + `map-over-items` →
  near-term backlog (**#A88**).
- **Lua node = deferred**, added only when the tail demands it → long-term
  backlog (**#A89**).
- WASM: out (returns only for hypothetical heavy compute, distant).
- **The operator catalog (~50–80 orthogonal ops) is the real design surface** —
  the next thing to actually design, more than the engine.

## 13. Open questions (next time)

- The operator catalog: which ~50–80 ops, how typed, how versioned, how the model
  is taught to compose them (the catalog doubles as the model's vocabulary /
  system prompt).
- Exact trait set that `match` predicates read from.
- Signature/telemetry schema that is provably PII-free.
- Where generation runs by default when both BYOK and hosted are configured.
