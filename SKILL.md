---
name: drpaste
description: Память и рабочий контекст проекта DrPaste — нативное clipboard-расширение для macOS под press-and-hold философию ("расширение жеста Paste"). Имя "Dr" читается как "образованный/умный" (PhD), не "doctor/медик". Загружай этот skill при любом упоминании DrPaste, Dr Paste, paste manager, paste extension, clipboard manager для Mac, clipboard HUD, press-and-hold paste, ⌥⌘V HUD, intelligent paste, Flycut/Jumpcut/Maccy/Paste-аналог, BYO AI paste tool. Прежнее рабочее имя проекта — ClipMacPoC (тоже триггер). Содержит полное ТЗ, архитектурные решения, описание всех файлов, тонкости реализации (CGEventTap vs Carbon vs NSEvent.addGlobalMonitor, NSPanel non-activating vs key-window, simulated paste, keyboard layout repair, Full Gesture vs Limited Mode auto-detect), статус и roadmap.
---

# DrPaste

Прототип нативного clipboard-расширения для macOS под press-and-hold UX-философию. Цель — не "ещё один clipboard manager", а **расширение самого жеста Paste** в системе.

Прежнее рабочее имя — **ClipMacPoC**. Финальное имя продукта — **DrPaste** (выбрано 25 мая 2026). Семантика "Dr" — **PhD / образованный / умный**, не врач. Иконка отражает это: clipboard + mortarboard cap (академическая шапка), не medical cross.

## Расположение проекта

```
~/Dropbox/Claude My/DrPaste/
  Package.swift
  README.md                             на английском, готов к публикации
  LICENSE                               GPL-3.0-or-later + attribution §7(d), ссылка на canonical text
  SKILL.md                              этот файл
  Sources/DrPaste/
    main.swift                          AppDelegate + bootstrap + AX monitor + restart
    AppBrand.swift                      AppBrand.name = "DrPaste", AppBrand.icon
    ClipboardModel.swift                ClipboardItem (var kind!), Store, Watcher, AppStorage paths
    ContextDetector.swift               локальный классификатор content
    Actions.swift                       protocol ClipboardAction + 11 local actions + Registry
    KeyboardLayoutRepair.swift          RU↔EN swap + NSSpellChecker scoring
    HotkeyEngine.swift                  EventTapEngine + CarbonHotKeyEngine + GlobalMonitorEngine + factory
    HUD.swift                           HudState + HudPanel (один класс, параметризован) + HudView (один view)
    AIProvider.swift                    protocol + AnthropicProvider + AIAction + default pack
    PasteSimulator.swift                ⌘V через CGEvent + PasteboardWriter
    Resources/
      AppIcon.svg                       placeholder иконка (clipboard + mortarboard / "Dr" в смысле PhD)
```

При сборке появится `.build/` с десятками тысяч мелких файлов — исключить в Dropbox через Selective Sync.

## Концепция (one-liner)

Пользователь удерживает `⌥⌘V` → появляется HUD overlay → стрелками `↑↓` листает clipboard history, стрелками `←→` — actions, live preview обновляется → отпускает модификаторы → текущий preview мгновенно вставляется в курсор активного приложения. Escape — abort.

**Dr = "образованный paste"** — продукт диагностирует контекст (URL / JSON / wrong layout / markdown / code) и предлагает уместные трансформации.

## Главные принципы (ТЗ)

- **Press-and-Hold** — "Нажал → выбрал → отпустил → вставилось"
- **Preview-First** — любая transformation сначала показывается
- **Context-Aware Actions** — определяются локально, показываются только релевантные
- **Local-first** — полезен без AI и без интернета
- **Bring Your Own AI** — никакого встроенного backend
- **Keyboard-first, mouse-available** — как Spotlight/Cmd-Tab
- **System HUD aesthetic** — translucent, light/dark, system accent
- **Graceful Degradation** — работает и без Accessibility (Limited Mode)
- **Open Source** — GPL-3.0 с attribution, community-extensible

## Архитектурные решения

**Стек.** Swift 5.9 + SwiftUI + AppKit + Carbon.HIToolbox, macOS 13+. SwiftPM executable.

**Hotkey: ⌥⌘V в обоих режимах.** Конфликт с Word "Paste Special" принимается осознанно.

**Три hotkey engine с auto-detect:**

| Engine | Use | Permission | Может swallow |
|---|---|---|---|
| `EventTapEngine` | Full Gesture Mode (production) | требует AX | да |
| `CarbonHotKeyEngine` | Limited Mode (fallback) | не нужна | нет |
| `GlobalMonitorEngine` | debug only | требует AX | нет |

Selection: `AXIsProcessTrusted()` true → EventTap, false → Carbon. Env var `CLIPMAC_ENGINE=tap|carbon|monitor` для override.

**Единый HUD для обоих режимов.** Это важный архитектурный принцип. У нас:

- **Один** `HudView` (SwiftUI). Body тот же.
- **Один** `HudState` (модель).
- **Один** `HudPanel` класс (параметризован конструктором `init(contentRect:allowsKey:)`).
- Различия между Full Gesture и Limited Mode — это **только** различия в `HudPanel.styleMask` / `canBecomeKey`, плюс **одно** условие в HudView (`if state.mode == .summon { limitedModeBanner }`), плюс **одна** строка в footer (release vs enter), плюс key event monitor устанавливается только в summon mode (в gesture mode keys ловит engine).

То есть **никаких двух копий, никаких двух логик**. Один view, один state, один panel-класс. Различия минимальные и сосредоточены в одном условии `state.mode == .gesture vs .summon`.

**Два варианта panel (один класс с параметром):**

- **`.gesture`** (Full): `NSPanel` со `styleMask: [.borderless, .nonactivatingPanel]`, `canBecomeKey: false`, `level: .statusBar`. EventTap глотает все нажатия пока HUD активен. Commit на release modifiers.
- **`.summon`** (Limited): тот же `NSPanel` со `styleMask: [.borderless, .titled, .fullSizeContentView]`, `canBecomeKey: true`, ставится `makeKeyAndOrderFront`. `NSEvent.addLocalMonitor` (в AppDelegate) ловит Enter/Esc/arrows/⌘±. Commit на Enter или double-click. В HUD виден баннер "Limited Mode — Press Enter to paste. Enable Accessibility for release-to-paste" с встроенной кнопкой "Open Settings…".

**AX trust monitor.** Фоновый Timer каждые 3 сек поллит `AXIsProcessTrusted()`. При `false → true` показывает NSAlert "Advanced gesture mode is now available. Restart?". При обратном — тихо понизится при следующем старте.

**HUD дизайн (правки 1-7):**

1. **Actions bar:** горизонтальный `ScrollView` + `ScrollViewReader.scrollTo(actionIndex, anchor: .center)` с анимацией 0.18s. По краям `.mask(LinearGradient)` для fade-out.
2. **Mouse support:** `HudHostingView<Content: View>: NSHostingView` override `acceptsFirstMouse(for:) -> true`. `.onTapGesture(count: 1)` = select (обновляет preview, HUD открыт), `count: 2` = commit. `.onHover` для подсветки.
3. **Rich text preview:** `NSAttributedString(data:options:)` из RTF/HTML → `AttributedString(ns, including: \.swiftUI)` → `Text(attributedString)`. Fallback на plain.
4. **AppBrand** — единая константа имени и иконки. `Bundle.module.url(forResource: "AppIcon", withExtension: "svg")` через `.process("Resources")` в Package.swift.
5. **System accent + light/dark.** `Color(nsColor: .controlAccentColor)` везде. `isEmphasized = false` на NSVisualEffectView — более лёгкий blur.
6. **Font scale:** `HudState.fontScale: CGFloat` с persistence в UserDefaults (`drpaste.hud.fontScale`). Хелпер `sz(_ base: CGFloat) -> CGFloat { base * fontScale }`. Bounds 0.7..1.6 шагом 0.1.
7. **Dynamic visibleRowCount + chevrons:** `Int(round(11.0 / fontScale))` clamp 5..items.count. Окно центрируется на активном, прижимается к краям. `chevron.compact.up/down` над/под колонкой.

**Context detection.** `ContextDetector.detect(item) -> ContentContext` (битмаска). Локальные эвристики, никакого AI/сети.

**Action registry.** `protocol ClipboardAction { id, title, isLocal, isApplicable, apply async throws }`. Local выполняются sync, AI — async с loading state и preview computation token (защита от старых результатов).

**AI provider abstraction.** `protocol AIProvider`. Реализован `AnthropicProvider` (messages API, model `claude-sonnet-4-6`). Ключ из env var `ANTHROPIC_API_KEY` или `~/Library/Application Support/DrPaste/providers.json`.

**Persistence.** JSON + PNG в `~/Library/Application Support/DrPaste/`. До 500 записей, дедуп, trim. `AppStorage` enum инкапсулирует пути.

**Keyboard layout repair.** Char-mapping QWERTY ↔ ЙЦУКЕН. Scoring через `NSSpellChecker.checkSpelling`.

## Иконка

Семантика "Dr" — **PhD / scholar / educated**, не медик. AppIcon.svg — clipboard со скруглёнными углами + mortarboard (академическая шапка) сверху или внутри. Не medical cross. Цвета — мягкий accent (indigo/blue), без излишней яркости — в стиле macOS overlay.

## Встроенные actions

Local (всегда): Paste as is, Fix keyboard layout, Plain text, Pretty JSON, Minify JSON, Clean URL, Just domain, Markdown → plain, Trim whitespace, UPPERCASE, lowercase.

AI (если есть key): AI: summarize, AI: translate RU↔EN, AI: fix grammar, AI: formal tone.

## Build & Run

```bash
cd ~/Dropbox/"Claude My"/DrPaste
swift run
```

Релизная: `swift build -c release && ./.build/release/DrPaste`. С AI: `ANTHROPIC_API_KEY=sk-ant-... swift run`. С другим engine: `CLIPMAC_ENGINE=monitor swift run`.

## Лицензия

GPL-3.0-or-later с attribution requirement через GPL §7(d). LICENSE содержит attribution clause + ссылку на canonical text. Полный канонический GPL текст в LICENSE НЕ воспроизводится — стандартная open-source практика, инструкция curl-нуть его в COPYING. Юридически валидно: license id указан, full text общедоступен.

Copyright "© 2026 iLya Os". Никнейм iLya Os — стандартный для public-credit/copyright headers (см. profile.json).

## Известные технические нюансы / тонкости

**`ClipboardItem.kind` должен быть `var`, не `let`.** Трансформации меняют kind.

**Top-level `MainActor.assumeIsolated { ... }`** в main.swift. AppDelegate `@MainActor`, `init()` тоже main-isolated → top-level код в Swift 6 не считается @MainActor.

**Carbon `kVK_*` константы — Int, `CGKeyCode` — UInt16.** В switch — `switch Int(kc) { case kVK_UpArrow: ... }`.

**CGEventTap callback приходит на main runloop**, если source добавлен через `CFRunLoopGetCurrent()` из main thread.

**Carbon RegisterEventHotKey НЕ требует Accessibility** — фундамент Limited Mode.

**Limited Mode panel** должен иметь styleMask **без** `.nonactivatingPanel`, и override `canBecomeKey: true`. NSPanel с .nonactivatingPanel НЕ может становиться key window.

**`HudHostingView<Content: View>: NSHostingView`** с override `acceptsFirstMouse(for:) → true`. Без этого клики в nonactivating panel игнорируются.

**`Bundle.module`** работает только при `resources: [.process("Resources")]` в Package.swift.

**`AttributedString(ns, including: \.swiftUI)`** для конверсии NSAttributedString → SwiftUI AttributedString. С macOS 12+.

**Pasteboard write порядок:** clearContents → setString/setData/writeObjects → ignore next change через watcher.

**Threading у HudState** — `@MainActor`. AppDelegate тоже. CGEventTap callback приходит на main runloop.

**Preview computation token** (`previewToken`) — защита от устаревших AI результатов при быстром листании actions.

## Pending архитектурные правки (next iteration)

**Backlog #1 — Universal Semantic Clipboard Layer.** Полный raw snapshot всех NSPasteboard representations (lossless), три уровня (raw preservation / semantic interpretation / transformation), source metadata (bundle ID + window title) в HUD, diagnostics mode.

**Backlog #2 — Visible action failures.** PreviewResult.ok/.failed, inline notice в preview pane с recovery action, AI actions всегда регистрируются (без ключа возвращают .failed), commit в failed state пишет original item (paste-as-is). "Неудачная попытка тоже попытка".

**Backlog #3 — Local image actions** (зависит от #2). 8 actions: OCR через Vision, decode QR/barcode, strip EXIF/GPS, resize 1920, compress JPEG 80%, grayscale, rotate 90, invert. Всё локально, Core Image + Vision.

**Backlog #4 — Content-aware action expansion.** ~56 новых local actions по типам: Files (paths/markdown links/SHA-256/reveal), URL (★ **Generate QR code**, markdown link, query params), Plain text (Title Case/camelCase/snake/sort/unique/base64/slugify), JSON (→ YAML / → CSV / extract keys / flatten), CSV (→ JSON / → Markdown table / transpose), Markdown (→ HTML / extract headings), Rich text (→ Markdown), Code (wrap in code block, tabs↔spaces). После правки — 75 actions total, context-aware фильтрация показывает 5–15 одновременно. Side-effect actions (Reveal/Open) и info actions (Size/Count/Hash) как новые архитектурные категории.

**Backlog #5 — Menu bar status item icon (template, standard width).** Сейчас в menu bar используется та же цветная HUD-иконка с прозрачными полями → статус-айтем "неприлично широкий" и нестандартный. Решение: отдельная template-иконка (монохром, tight viewBox, isTemplate=true), отдельный MenuBarIcon.pdf в Resources/, fallback на SF Symbol. Цветная остаётся в HUD-header. Маленькая правка ~30 строк.

**Backlog #7 — Type Slowly action (обход paste-block в банковских формах).** Новый action для plain text: вместо стандартного paste печатает текст символ за символом через `CGEvent.keyboardSetUnicodeString` с задержкой 0.2s ± 20% jitter. Обходит `onpaste="return false"` в банках, government forms, password fields. Архитектурное расширение — `CommitStyle` enum в `ApplyOutcome` (standardPaste / typeSlowly / typeFast). Cancellation через Esc, progress overlay для длинных строк, auto-cancel при смене focus. Требует AX (в Limited Mode .failed). Default ≤500 символов. ~100-150 строк + TypeSimulator.swift.

**Backlog #10 — Звуковой фидбек (copy/paste/type).** Короткие звуки для всех clipboard операций, особенно важны для ⌥⌘C Quick Copy где нет визуального HUD: copy-success (тихий tink), copy-failure (короткий buzz при пустом selection — детектируется через pasteboard.changeCount до/после simulateCopy за 150ms), paste-success (мягкий click на commit), paste-failure (на ApplyOutcome.failed после Backlog #2), type-tick (тихий клик на каждый символ Type Slowly). Bundled aiff в Resources/Sounds/ или system NSSound("Tink"/"Funk"/"Pop"/"Morse") fallback. Settings → General: раздельные toggles per-sound + global volume slider. Throttle 200ms на одинаковые звуки. Smart paste verification (AX-based проверка что текст реально вставился) — out of scope v1, идея в backlog как Advanced toggle. Accessibility benefit: для слабовидящих звук primary feedback channel. ~150-200 строк + 5 sound assets.

**Backlog #9 — ⌥⌘C (Copy) и ⌥⌘X (Cut & Replace) hotkeys.** Расширение унифицированной mental model "⌥⌘ для всех clipboard операций". `⌥⌘C` — simulated `⌘C` в frontmost, HUD не открывается, transient flash на menu bar icon как feedback. `⌥⌘X` — simulated `⌘X` (selection в pasteboard и в историю) → открывается HUD → на commit replace на месте вырезанного (swap-paste). HotkeyConfig расширяется на 3 keys, HotkeyEngineDelegate новый метод didQuickCopy, оба engine регистрируют 3 hotkey, PasteSimulator получает simulateCopy/simulateCut. Edge cases: empty selection, frontmost=DrPaste, race watcher→HUD при cut. Opt-out в Settings General tab. ~150-200 строк.

**Backlog #8 — Settings window + customizable action registry + playground + import/export.** Большая правка ~700-1000 строк. Превращает DrPaste в платформу для action packs. Settings TabView: системные tabs (General, AI Providers) + динамические по content types (Plain text / URL / JSON / Image / Files / ...). **Каждый content tab — playground**: editable sample input + Result pane + список actions с checkbox enable/disable, кнопкой [Edit] для AI и кнопкой [Run] на каждом — сразу выполняет action на sample, показывает результат в Result pane. Discovery / debugging AI prompts / safe preview action packs до enable. Side-effect actions (Reveal/Open URL) показывают "what would happen" вместо реального side-effect. Bundled default samples в Resources/SettingsSamples/. ActionRegistry data-driven через ActionDescriptor (Codable). Export/Import JSON config + drag-and-drop `.drpaste-actions.json`. API keys в export не включаются. Subsumes Backlog #6 Settings stub. Зависит от #2 (failure visibility) и #4 (action expansion).

**Backlog #6 — Status menu reorganization.** Новая структура: `DrPaste — Mode` [label] → `Recent clipboard ▶` (динамический submenu с 15 последними items, первый пункт `──── Clear history ────`, click на item делает **paste-to-frontmost**: snapshot frontmost через menuWillOpen → pasteboard write → activate saved app → delay 120ms → simulatePaste; в Limited Mode без AX — только pasteboard write с hint) → `Settings…` (новое окно, SwiftUI tabs: General/AI/About) → `About DrPaste…` (`NSApp.orderFrontStandardAboutPanel`) → `Quit ⌘Q`. NSMenuDelegate для lazy rebuild submenu. ~150–200 строк.

Подробные технические планы и code snippets — в `BACKLOG.md` в корне проекта.

## Roadmap

1. Перевод в Xcode-проект с .app bundle (architecture уже совместим)
2. Sparkle + Developer ID + notarization
3. JSON action packs с импортом drag-and-drop
4. Settings UI на SwiftUI (вкладки hotkey/providers/exclusions через `KeyboardShortcuts` package)
5. OpenAI + Ollama + OpenRouter providers через AIProvider protocol
6. Image actions через Vision framework (OCR, resize)
7. CloudKit sync для clipboard history Mac/iOS
8. Onboarding window с GIF
9. App exclusions + `org.nspasteboard.ConcealedType` маркер
10. iOS companion (keyboard extension)

## Связанные точки в персональном профиле

iLya Os — engineer/inventor 30+ патентов, любит embedded/edge AI, не любит лишние обёртки. Низкоуровневые API без библиотек (Carbon, CGEventTap, NSPanel напрямую). Open source ориентация. Русские комментарии в коде естественны. Copyright/attribution использует никнейм **iLya Os** (маленькая i, заглавная L, без точки).
