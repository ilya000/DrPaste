# DrPaste — Backlog

Отложенные правки в порядке приоритета. Когда стабилизируется текущая база и начнётся следующая итерация — берём №1 первой.

---

## Правка №1 (next iteration) — Universal Semantic Clipboard Layer

**Статус:** запланирована. Архитектурная правка такого же масштаба как Full/Limited Mode (Правка №9 текущей итерации). Оценка 600–900 строк изменений в 4–5 файлах.

**Затрагивает:** `ClipboardModel.swift`, `ClipboardWatcher` (внутри `ClipboardModel.swift`), `ClipboardStore` (там же), `PasteboardWriter` (`PasteSimulator.swift`), preview-секция в `HUD.swift`, persistence layout, опционально `AppDelegate` (diagnostics menu).

### Философия

DrPaste должен проектироваться как **universal semantic clipboard layer**, а не text-only clipboard manager. Clipboard в macOS представляет собой набор representations одного и того же объекта. Один clipboard item может одновременно содержать plain text, rich text, HTML, URLs, изображения, spreadsheet payloads, PDFs, proprietary application formats и другие representations.

Приложение не должно рассматривать clipboard как "строку текста". Основная архитектурная задача — максимально полно и без потерь сохранять original clipboard payload.

### Три уровня архитектуры

**1. Raw preservation layer** отвечает за lossless storage clipboard content. Приложение сохраняет весь набор clipboard representations без изменений. Если пользователь копирует содержимое из Excel, Numbers, Safari, Word, Figma, Photoshop или другого сложного приложения — DrPaste сохраняет все representations одновременно, включая proprietary payloads приложений.

Даже если DrPaste не умеет интерпретировать конкретный тип данных, payload должен сохраняться и восстанавливаться при Paste-as-is operation. Tolerant к unknown formats: unknown payload сохраняется как raw representation и участвует в Paste-as-is restoration.

Особенно важно корректно поддерживать spreadsheet ecosystems. Clipboard payload из Excel или Numbers может одновременно содержать TSV representation, HTML table, RTF representation, plain text representation и proprietary spreadsheet metadata. Сохранять весь набор целиком — без потери formatting, formulas, merged cells или internal metadata.

**2. Semantic interpretation layer** существует отдельно от raw payload storage. Определяет high-level meaning clipboard content и используется только для preview generation, contextual transformations и filtering actions. Не разрушает original payload и не заменяет original clipboard representations.

Semantic классификация поддерживает как минимум: plain text, rich text, HTML, URL, file references, image, PDF, spreadsheet/table, markdown, JSON, source code, structured data, email content, drag-and-drop payloads, unknown binary content.

**3. Transformation layer** работает поверх semantic interpretation. Каждое action явно определяет совместимость с semantic content types и своё отношение к original payloads.

Non-destructive actions по возможности сохраняют original representations и metadata. Destructive transformations могут создавать новый transformed payload, но HUD визуально показывает что результат больше не original.

### Минимальный production-level format support

Plain text (UTF-8), RTF, HTML, URLs, file URLs, PNG, TIFF, JPEG, PDF, attributed text, webarchive representations, spreadsheet-related payloads (public.tab-separated-values-text, com.microsoft.excel.xls, dyn.* dynamic UTTypes).

### Preview system — semantic-first, не raw

Пользователь видит понятный компактный preview независимо от внутреннего формата. Для preview используется наиболее human-readable representation.

| Что в clipboard | Что показываем в HUD |
|---|---|
| plain text + HTML | clean readable text |
| image payload | thumbnail preview |
| PDF | preview страницы или extracted snippet |
| spreadsheet payload | compact table preview |
| file references | file icons + filenames + count |
| URL | cleaned readable link + domain |
| unknown binary | размер + UTType hint (только в diagnostics) |

Raw binary payloads и UTType identifiers в normal mode не показываются — internal representations это implementation detail.

### Diagnostics / debug mode

Optional для разработчика. Активация: env var `DRPASTE_DEBUG=1` или пункт меню "Diagnostics…".

Показывает: полный список pasteboard representations clipboard item — все UTTypes, proprietary formats, payload sizes, semantic classification results. Необходим для reverse engineering compatibility популярных приложений и постепенного расширения support matrix.

### Source metadata

Каждый clipboard item содержит информацию о приложении-источнике: bundle identifier (есть уже). Дополнительно — window title, document title, browser tab title где доступно (через AX API на frontmost app или AppleScript Bridge для Safari/Chrome).

HUD отображает source рядом с preview, например под header:

```
"Copied from Safari — OpenAI Documentation"
"Copied from Excel — Budget2026.xlsx"
"Copied from Figma — Onboarding Flow"
"Copied from VS Code — Actions.swift"
"Copied from Finder"
```

Source metadata — часть cognitive UX. Пользователь распознаёт нужный clipboard item по source application быстрее чем по тексту.

Clipboard history позволяет фильтровать или визуально группировать items по source application (в будущем — отдельная правка).

### Технический план реализации

```swift
// 1. ClipboardItem rewrite
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date

    // Raw preservation — все representations как они есть
    /// UTType identifier (например "public.utf8-plain-text") → blob storage path
    var representations: [String: String]   // type → relative path в data dir
    /// Ordered list of UTTypes from pasteboard, в исходном порядке приоритета.
    var typesOrdered: [String]

    // Semantic interpretation — вычисляется при snapshot
    var semantic: SemanticKind               // .text/.richText/.image/.pdf/.spreadsheet/.url/.files/.unknown
    var previewText: String?                 // human-readable snippet
    var previewImageRel: String?             // path к PNG-превью (для image/PDF)

    // Source metadata
    var sourceBundleID: String?
    var sourceAppName: String?
    var sourceWindowTitle: String?           // если получили через AX

    var tags: [String]
}

enum SemanticKind: String, Codable {
    case text, richText, html, url, files, image, pdf, spreadsheet,
         markdown, json, code, email, unknown
}

// 2. ClipboardWatcher rewrite
//    Вместо четырёх специализированных snapshot путей —
//    общий цикл по pasteboard.types, blob storage для каждого type.
func snapshotPasteboard() -> ClipboardItem? {
    guard let types = pasteboard.types, !types.isEmpty else { return nil }
    var reps: [String: String] = [:]
    var ordered: [String] = []
    for t in types {
        guard let data = pasteboard.data(forType: t) else { continue }
        let rel = store.writeRawBlob(data, type: t.rawValue)
        reps[t.rawValue] = rel
        ordered.append(t.rawValue)
    }
    let semantic = SemanticClassifier.classify(types: ordered, pasteboard: pasteboard)
    let preview = PreviewSynthesizer.synthesize(types: ordered, pasteboard: pasteboard, semantic: semantic)
    let src = SourceResolver.resolve()
    return ClipboardItem(...)
}

// 3. PasteboardWriter rewrite
//    Восстанавливает ВСЕ representations при commit.
static func write(_ item: ClipboardItem) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.declareTypes(item.typesOrdered.map(NSPasteboard.PasteboardType.init), owner: nil)
    for type in item.typesOrdered {
        guard let rel = item.representations[type],
              let data = try? Data(contentsOf: store.blobURL(rel)) else { continue }
        pb.setData(data, forType: NSPasteboard.PasteboardType(type))
    }
}

// 4. Persistence layout
//    ~/Library/Application Support/DrPaste/
//      index.json                     - metadata всех items
//      blobs/<uuid>/<sanitized-type>  - один файл на representation

// 5. HUD preview
//    Использует item.previewText / item.previewImageRel / etc.
//    Source label под header.
//    Diagnostics mode (env var) — раскрывает список representations.
```

### Преимущества после внедрения

- **Настоящая Paste-as-is** для Excel/Word/Figma/Numbers — все proprietary formats сохраняются.
- **Legacy и dynamic UTTypes** не теряются.
- **Tolerant к unknown formats** — будущая совместимость без правок кода.
- **Source-aware UX** — навигация по истории становится визуально проще.
- **Diagnostics mode** — основа для reverse engineering и расширения support matrix.

### Что осознанно не входит

- Шифрование blob storage (рассматривается отдельной правкой если потребуется).
- CloudKit sync для blob storage (rough даже для текстового layer'а).
- Полная поддержка drag-and-drop payloads сверх pasteboard (требует drop handler в приложении).
- Транскодирование между форматами (например HTML → markdown на сохранении). Сохраняем как есть.

---

## Правка №2 (next iteration) — Visible action failures (preview-side error state)

**Статус:** запланирована. Косметико-архитектурная правка, средний scope (~150–250 строк изменений).

**Затрагивает:** `Actions.swift` (ClipboardAction.apply возвращает не item, а result type), `HUD.swift` (preview pane + новый inline notice), `AppDelegate.refreshPreview` / `.commitHUD`, опционально `AIProvider.swift` (always register AI actions, fail at apply time).

### Принцип

«Неудачная попытка тоже попытка — не нужно её скрывать.» Сейчас action либо тихо возвращает `item` без изменений (JSON parse failed → ничего не происходит), либо вовсе не появляется в списке (AI без ключа). Это плохой UX:

- Пользователь не понимает почему JSON не отпрямился — выглядит как баг.
- AI actions невидимы без ключа — discovery страдает, пользователь не знает что есть.

Правка делает любой fail видимым в preview pane как inline notice со внятной причиной и optional recovery action.

### Архитектура

```swift
enum PreviewResult {
    case ok(ClipboardItem)
    case failed(original: ClipboardItem, reason: String, recovery: RecoveryAction?)
}

enum RecoveryAction {
    case openProvidersConfig          // для AI fail → открыть providers.json
    case openAccessibilitySettings    // если когда-то понадобится
    case custom(label: String, url: URL)
}

protocol ClipboardAction {
    // signature меняется: apply возвращает PreviewResult вместо ClipboardItem
    func apply(item: ClipboardItem, context: ContentContext) async -> PreviewResult
}
```

### Поведение в HUD

В preview pane:

- `.ok` — как сейчас: рендерим обновлённый item (text/richText/image/files).
- `.failed` — рендерим **original** item как preview (пользователь видит что бы вставилось), плюс **inline notice** сверху или снизу preview: полупрозрачная плашка с reason ("Couldn't parse as JSON" / "AI provider not configured") + кнопка recovery (если есть) — например "Open AI Settings…".

Footer-keyhints в failed state остаются такими же — release/Enter работает, double-click работает.

### Commit в failed state

Записываем в pasteboard **original item** (paste-as-is). Пользователь получает рабочую вставку, не пустую. Это совместимо с ТЗ ("не требует подтверждений, не блокирует workflow") и с принципом "неудачная попытка тоже попытка — пользователь увидел что не сработало, но получил полезный результат".

Альтернативу (блокировать commit) рассмотрели и отвергли — это противоречит preview-first / no-confirmation философии.

### AI actions всегда регистрируются

`DefaultAIActions.make(provider:)` вызывается всегда, независимо от наличия ключа. Внутри `AIAction.apply`: если `AIProviderError.missingAPIKey` — возвращаем `.failed(original, reason: "AI provider not configured", recovery: .openProvidersConfig)`.

Это даёт discovery: пользователь видит "AI: summarize" в списке actions и понимает что фича есть, надо настроить ключ.

### Применимо ко всем actions, не только AI

JSON malformed → `.failed(original, reason: "Couldn't parse as JSON", recovery: nil)`.
URL strip не нашёл tracking params → пока остаётся `.ok` с unchanged item (это не fail, просто нечего стрипать).
Markdown → plain на тексте без markers — то же.
Layout repair решил что swap хуже оригинала → `.ok` с unchanged item (heuristic не fail).

Failure = action *должен был* применить трансформацию, но не смог из-за внешнего условия (отсутствие config, malformed input). Не любое no-op возвращает `.failed`.

---

## Правка №3 (next iteration) — Local image actions

**Статус:** запланирована. Новый action pack для image clipboard items, всё локально через Core Image и Vision.

**Затрагивает:** `Actions.swift` (новые action structs), опционально `ClipboardModel.swift` (helper для конверсии image item ↔ NSImage), новый `ImageActions.swift` если pack разрастётся.

### Production-минимум — 8 actions

| Action | API | Семантика | Wow-эффект |
|---|---|---|---|
| **Extract text (OCR)** | `VNRecognizeTextRequest` | image → text item | очень высокий |
| **Decode QR / barcode** | `VNDetectBarcodesRequest` | image → text item | высокий |
| **Strip metadata (EXIF / GPS)** | `CGImageDestination` без metadata | image → image (clean) | privacy-критично |
| **Resize to max 1920px** | `CIFilter.lanczosScaleTransform` | image → resized image | повседневное |
| **Compress to JPEG 80%** | `NSBitmapImageRep.representation(using: .jpeg)` | image → smaller JPEG | для email/messengers |
| **Grayscale** | `CIPhotoEffectMono` или `CIColorMonochrome` | image → BW image | accessibility + декор |
| **Rotate 90° CW** | `CIFilter.affineTransform` | image → rotated | fix screenshots |
| **Invert colors** | `CIColorInvert` | image → inverted | dark/light theme conversion |

### Дополнительные (низкий приоритет, fun)

- Rotate 90° CCW / 180° — варианты `affineTransform`
- Flip horizontal / vertical
- Sepia (`CIPhotoEffectSepia`) / Noir (`CIPhotoEffectNoir`) — стилизация
- Convert to base64 data URI — для разработчиков (image → text item с `data:image/png;base64,...`)
- Format conversion PNG ↔ JPEG ↔ HEIC

### Особенности реализации

**OCR action** меняет kind: image → text. На commit — текст в pasteboard. Layout repair и другие text actions становятся доступны после OCR. То есть OCR работает как первый шаг pipeline (но pipeline-actions — отдельная правка позже).

**OCR language hints.** `VNRecognizeTextRequest.recognitionLanguages` — для лучшего качества можно автодетектить язык по системной локали или по характерам в other clipboard items. Для PoC — multi-language by default.

**Strip metadata** должен сохранять image data integrity. Использовать `CGImageDestinationAddImageFromSource` с `kCGImageDestinationMetadata` = nil. Тестировать на photos с iPhone (там GPS), на скриншотах (там cropping metadata).

**Resize / Compress** действуют только если результат меньше оригинала. Иначе возвращают `.ok` с unchanged (или `.failed` с reason "Already within size limits" — обсудим).

**Decode QR** должен fail gracefully если QR не найден — `.failed(original, reason: "No QR or barcode detected", recovery: nil)`. Это идеально ложится на Backlog #2.

### Зависимости

Эта правка опирается на **Backlog #2** (PreviewResult с .failed state) — для OCR/QR где результат может не получиться, и для "ничего не подходит" cases. Логично делать после #2 или вместе.

---

## Правка №4 (next iteration) — Content-aware action expansion

**Статус:** запланирована. Большой набор новых actions по всем основным content types. Хайлайт — **Generate QR code из URL** (text → image, локально, без сети).

**Затрагивает:** `Actions.swift` (расширение, либо новый `FileActions.swift` / `URLActions.swift` / `TextActions.swift` / `JSONActions.swift` / `TableActions.swift` / `MarkdownActions.swift` / `CodeActions.swift` для аккуратной структуры), `ContextDetector.swift` (новые типы), `ClipboardModel.swift` (если потребуются side-effect и info paths).

### Архитектурные принципы (применимы ко всей правке)

**Many actions меняют kind.** URL → image для QR. Image → text для OCR. Files → text для paths. CSV → text для markdown table. Это уже работает в нынешнем `var kind`.

**Side-effect actions.** Reveal in Finder, Open URL, Open in default app — категория где action не возвращает новый item для commit, а делает что-то в системе и закрывает HUD. Архитектурно расширяем `apply`:

```swift
enum ApplyOutcome {
    case preview(ClipboardItem)       // обычная transformation
    case failed(ClipboardItem, ...)   // из Backlog #2
    case sideEffect                   // действие выполнено, HUD закрыт, commit не нужен
}
```

В preview pane для side-effect показываем оригинал + плашку "This action will [reveal in Finder / open in browser]" — пользователь видит что произойдёт до commit.

**Info actions.** Size info, Word count, SHA-256, файл metadata — превращают item в plain text с информацией. На commit вставляется этот текст. Это обычная transformation (kind → text), не side-effect.

**External-network actions.** URL shorten, expand short URL, fetch title для markdown link — нарушают local-first. Только если есть user-configured provider (как с AI). В правку №4 НЕ включаем.

### Action list по типам

#### Files (clipboard содержит file references)

| Action | Что делает | kind в результате |
|---|---|---|
| **Copy paths as text** | абсолютные пути по строке | files → text |
| **Filenames only** | только имена без path | files → text |
| **Bash-quoted list** | `"file 1" "file 2"` для shell | files → text |
| **Markdown links** | `[name](file:///path)` | files → text |
| **HTML links** | `<a href="...">...</a>` | files → text |
| **Size info** | `3 files, 4.2 MB total — 2 images, 1 PDF` | files → text (info) |
| **SHA-256 hash** | hex hash одного файла | files → text (info) |
| **Reveal in Finder** | открывает Finder с selection | side-effect |
| **Parent folder** | reference к родительскому каталогу | files → files |

#### URL

Уже есть: Clean URL (strip tracking), Just domain.

Новые:

| Action | Что делает | kind в результате |
|---|---|---|
| **Generate QR code** ★ | URL → QR image через `CIQRCodeGenerator` | text → image |
| **Markdown link** | `[domain.com](url)` или `[cached-title](url)` | text → text |
| **HTML link** | `<a href="...">...</a>` | text → text |
| **URL-decode** | `%20` → пробел, percent-encoded → readable | text → text |
| **Query params as table** | `?a=1&b=2` → две колонки key/value (TSV) | text → table-text |

★ **Generate QR code** — highlight правки. Reasoning: классическая задача "ссылку из ноута на телефон без AirDrop". Реализация одна строка:

```swift
let qr = CIFilter.qrCodeGenerator()
qr.message = data
let outputImage = qr.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
```

Меняет kind .text → .image, на commit пользователь получает PNG QR в pasteboard и Cmd+V в любое image-field. Для Slack/Discord/iMessage сразу работает.

#### Plain text

Уже есть: UPPERCASE, lowercase, Trim whitespace.

Новые:

| Action | Что делает |
|---|---|
| **Title Case** | заглавная буква в каждом слове |
| **Sentence case** | заглавная только в начале предложений |
| **camelCase** | `Hello World` → `helloWorld` |
| **snake_case** | `Hello World` → `hello_world` |
| **kebab-case** | `Hello World` → `hello-world` |
| **Sort lines** | по алфавиту |
| **Unique lines** | dedup |
| **Generate QR** | text → image (любая короткая строка как QR) |
| **Base64 encode / decode** | text ↔ base64 |
| **URL encode / decode** | text ↔ percent-encoded |
| **HTML entities encode / decode** | `<` ↔ `&lt;` |
| **Slugify** | `Hello, World!` → `hello-world` |
| **Word / char count** | info action: `247 words, 1532 chars, 18 lines` |

#### JSON

Уже есть: Pretty, Minify.

Новые:

| Action | Что делает |
|---|---|
| **JSON → YAML** | format conversion |
| **JSON → CSV** | array of objects → CSV (headers from keys) |
| **Extract keys** | список ключей, по одному на строку (для понимания схемы) |
| **Flatten** | `{"a":{"b":1}}` → `{"a.b":1}` |
| **Remove null values** | очистка |

#### CSV / Table (новый context type — `.table`)

| Action | Что делает |
|---|---|
| **CSV → JSON** | array of objects |
| **CSV → Markdown table** | для документации |
| **CSV → HTML table** | |
| **Transpose** | rows ↔ columns |
| **Sort by column N** | пользователь указывает номер |
| **Sum / count column** | если все значения numeric |

#### Markdown

Уже есть: Markdown → plain.

Новые:

| Action | Что делает |
|---|---|
| **Markdown → HTML** | render через native cmark или библиотеку Down |
| **Extract headings** | для table of contents |
| **Extract links** | все `[...](...)` → список URLs |
| **Strip code blocks** | оставить только prose |

#### Rich text

Уже есть: Plain text.

Новые:

| Action | Что делает |
|---|---|
| **Rich → Markdown** | bold/italic/headings/links preserved |
| **Strip styles, keep structure** | оставить только bold/italic, убрать цвета/шрифты |

#### Code (новый context type — `.code` уже детектится)

| Action | Что делает |
|---|---|
| **Wrap in code block** | для markdown: `\`\`\`lang\n...\n\`\`\``, language autodetect heuristic |
| **Tabs → Spaces** | configurable indent size |
| **Spaces → Tabs** | обратное |
| **Strip comments** | language-aware, начнём с `//`, `#`, `--` |

### Реализационные нюансы

**Generate QR (highlight).** `CIQRCodeGenerator` filter, output 10x scale для читаемости. Уровень коррекции `M` (15%) по умолчанию, можно настроить до `H` (30%) для логотипов в центре (out of scope для PoC).

**Sort by column N в CSV.** N задаётся в action title или через preferences. Для PoC — фиксированный sort по первой колонке, плюс отдельная action "Sort by second column".

**Rich → Markdown.** Использовать сторонний package или native NSAttributedString → enumerate attributes → emit markdown markers. Существует `swift-html-to-markdown` и подобные. Для PoC — простой emitter handling bold/italic/h1-h6/links/lists, остальное скипаем.

**Markdown → HTML.** Native `swift-markdown` от Apple (`import Markdown`) или `Down`. Apple package — preferred (zero external deps).

**Strip comments language-aware.** Сначала детектим язык (расширение или эвристика keywords из ContextDetector), потом применяем regex для line comments этого языка. Block comments (`/* */`) — отдельная сложность, начнём с line comments.

**Side-effect actions UI.** Preview pane показывает original + плашку "This action will reveal these files in Finder" / "This action will open this URL in your default browser". Commit (release/Enter/dbl-click) выполняет действие и закрывает HUD без записи в pasteboard.

**Generate QR из text.** Активируется для любого text item, не только URL. URL получает приоритет в action ordering, но любой short string тоже становится QR. Лимит длины ~ 2900 alphanumeric, для длинного текста QR деградирует — показываем `.failed(reason: "Text too long for QR code")` после Backlog #2.

### Action count после правки №4

Текущий ActionRegistry: 11 local + 4 AI = 15 actions.

После №4: +9 files + 5 URL + 13 plain text + 5 JSON + 6 table + 4 markdown + 2 rich text + 4 code + 8 image (Backlog #3) = +56 → **71 local + 4 AI = 75 actions**.

Context-aware фильтрация показывает только релевантные, поэтому видно одновременно всегда 5–15. Без фильтрации UI был бы непригоден.

### Зависимости

Опирается на:
- **Backlog #2** (failure visibility) — для actions которые могут не сработать (QR too long, malformed input).
- **Backlog #1** (universal semantic layer) полезен но не обязателен — некоторые actions (например full Excel TSV preservation) выигрывают, но базовый набор работает на текущей архитектуре.

Может делаться параллельно с #2 и #3 — пересечений в коде немного.

---

## Правка №5 (next iteration) — Menu bar status item icon (template, standard width)

**Статус:** запланирована. Маленькая правка, ~30 строк.

**Затрагивает:** `AppBrand.swift` (новый `menuBarIcon: NSImage`), `main.swift` (installStatusItem), `Resources/` (опционально новый `MenuBarIcon.pdf`).

### Проблема

Сейчас в menu bar status item используется та же цветная иконка `AppBrand.nsIcon` что и в HUD header. Это даёт два неприятных эффекта:

1. **Лишняя ширина.** AppIcon.svg имеет много прозрачного padding по краям (viewBox 128×128, реальное содержимое примерно 22..106 × 30..120). `NSStatusItem.variableLength` учитывает весь viewBox включая прозрачность, поэтому status item занимает 22+18+22+padding пикселей и выглядит "неприлично широким" по сравнению с другими macOS-утилитами.

2. **Цветная иконка в menu bar нестандартна.** По macOS HIG menu-bar иконки должны быть монохромными template images, чтобы macOS сам красил их под текущую appearance (light/dark/highlighted-on-open) и они выглядели нативно рядом с другими утилитами.

### Правильное решение

**Отдельная template-иконка для menu bar** (не та же что в HUD-header).

1. В `Sources/DrPaste/Resources/` положить `MenuBarIcon.pdf` — монохромный, тонкие линии, прозрачный фон, реальное содержимое впритык к границам (без лишнего padding). Формат PDF предпочтителен — vector, scaling без потерь. Размер ~16×16 при создании.

2. В `AppBrand.swift` добавить getter:
   ```swift
   static var menuBarIcon: NSImage {
       let img: NSImage
       if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "pdf"),
          let i = NSImage(contentsOf: url) {
           img = i
       } else if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "svg"),
                 let i = NSImage(contentsOf: url) {
           img = i
       } else {
           // fallback на SF Symbol — он уже template и выглядит нативно
           img = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: name) ?? NSImage()
       }
       img.isTemplate = true
       img.size = NSSize(width: 18, height: 18)
       return img
   }
   ```

3. В `main.swift.installStatusItem` использовать `AppBrand.menuBarIcon` вместо `AppBrand.nsIcon`, убрать ручную установку size/isTemplate.

### Дизайн template иконки

Идея под бренд DrPaste — тонкая монохромная стилизация clipboard + cap. Например:
- Outline clipboard rectangle с скруглёнными углами
- Простой mortarboard силуэт сверху (squared diamond с центральной точкой)
- Без gradients, без fills внутри, только strokes

Альтернативно — чистый clipboard outline без cap (cap в menu bar в маленьком размере читается плохо).

Реализовать как SVG/PDF после первой публикации, для PoC устраивает fallback на SF Symbol `doc.on.clipboard`.

### Что НЕ делается

Цветная иконка в HUD header (`AppBrand.icon` / `nsIcon`) **остаётся** — там брендинг к месту, окно видно один раз во время использования.

---

## Правка №6 (next iteration) — Status menu reorganization

**Статус:** запланирована. Средняя правка, ~150–200 строк (включая About window и Settings stub).

**Затрагивает:** `main.swift` (installStatusItem полностью пересобирается + NSMenuDelegate для динамического submenu), новый `SettingsWindow.swift` (минимальная заглушка), `AppBrand.swift` (метаданные для About panel).

### Целевая структура меню

```
DrPaste — Full Gesture Mode       [disabled, label]
─────────────────────────────────
Recent clipboard            ▶     [submenu, динамический]
    ──── Clear history ────       [визуальный separator-with-action, первый]
    ─────────────────────
    📋  Hello, this is the first…
    🖼   Image  124 KB
    📁  3 files: report.pdf, …
    📋  https://example.com/long…
    📋  {"name": "test", "value": 1}
    ...                            (последние 15 items)
─────────────────────────────────
Settings…                          (открывает Settings window)
About DrPaste…                     (NSApp.orderFrontStandardAboutPanel)
─────────────────────────────────
Quit DrPaste                  ⌘Q
```

### Подзадачи

#### 6.1. Динамическое submenu "Recent clipboard"

NSMenuDelegate с `menuNeedsUpdate(_:)`. При открытии submenu пересобираем items из текущего `ClipboardStore.items`.

```swift
final class AppDelegate: ..., NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentClipboardMenu else { return }
        rebuildRecentMenu()
    }
    private func rebuildRecentMenu() {
        recentClipboardMenu.removeAllItems()
        // 1. Clear history (визуальный separator+action)
        let clear = NSMenuItem(title: "──── Clear history ────",
                               action: #selector(clearHistory),
                               keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !store.items.isEmpty
        recentClipboardMenu.addItem(clear)
        recentClipboardMenu.addItem(.separator())
        // 2. Последние 15 items
        for (idx, item) in store.items.prefix(15).enumerated() {
            let mi = NSMenuItem(title: snippet(item),
                                action: #selector(recentItemSelected(_:)),
                                keyEquivalent: "")
            mi.image = iconFor(item.kind)
            mi.target = self
            mi.tag = idx
            recentClipboardMenu.addItem(mi)
        }
        if store.items.isEmpty {
            let empty = NSMenuItem(title: "(history is empty)",
                                   action: nil, keyEquivalent: "")
            empty.isEnabled = false
            recentClipboardMenu.addItem(empty)
        }
    }
}
```

`snippet(item)` — truncated text / filename / "Image XX KB", макс ~50 символов.
`iconFor(kind)` — маленькие SF Symbols (16×16): `text.alignleft` / `doc.richtext` / `photo` / `doc.on.doc`.

#### 6.2. Поведение click на recent item

**Решение:** записать item в pasteboard и сразу симулировать `⌘V` в frontmost app (paste-to-frontmost, как в HUD-режиме).

Реализация требует трёх вещей:

1. **Snapshot frontmost app до открытия меню.** NSMenu забирает focus в menubar сразу при открытии, поэтому `NSWorkspace.shared.frontmostApplication` уже к моменту клика на item возвращает либо `Window Server` либо наше приложение. Решение — поймать frontmost в момент когда меню только-только начинает открываться через NSMenuDelegate.menuWillOpen:

   ```swift
   private var savedFrontmostApp: NSRunningApplication?

   func menuWillOpen(_ menu: NSMenu) {
       if menu === recentClipboardMenu || menu === statusItem.menu {
           savedFrontmostApp = NSWorkspace.shared.frontmostApplication
       }
   }
   ```

2. **Активировать сохранённое приложение до симуляции paste.** После клика на item:

   ```swift
   @objc private func recentItemSelected(_ sender: NSMenuItem) {
       let item = store.items[sender.tag]
       PasteboardWriter.write(item)
       watcher.ignoreNextChange = true

       // Закрываем меню (происходит автоматически), вернуть focus прежнему приложению,
       // дать macOS зарегистрировать переключение, и симулировать Cmd+V.
       savedFrontmostApp?.activate(options: [])
       DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
           PasteSimulator.simulatePaste()
       }
       savedFrontmostApp = nil
   }
   ```

   Задержка ~120 ms эмпирическая — нужно дать macOS переключить focus после menu close. В HUD-flow мы используем 50 ms потому что HUD non-activating и focus не уходил; здесь focus реально уходил в menubar — нужно больше.

3. **Учесть Limited Mode.** В Limited Mode AX не выдано → `CGEvent.post` для simulated paste не сработает (или сработает невидимо без эффекта). В этом случае меню должно:
   - всё равно записать item в pasteboard (это работает без AX);
   - не пытаться симулировать paste;
   - показать однократный transient hint (notification или флэш в menu bar) "Pasted to clipboard — press ⌘V to paste" — opt-in для discoverability, можно отключить в Settings.

   Проверка: `AXIsProcessTrusted()` перед `simulatePaste()`. Если false — skip simulatePaste, остаётся только pasteboard write.

#### 6.2.1. Edge case — frontmost это наше приложение

Если до открытия меню frontmost было самим DrPaste (например HUD только что закрылся), `savedFrontmostApp` укажет на нас и paste произойдёт "в никуда". Защита — если `savedFrontmostApp.bundleIdentifier == Bundle.main.bundleIdentifier`, пропускаем activate и simulatePaste, оставляем только pasteboard write.

#### 6.3. Clear history как первый item в submenu

Илья просит визуально выделенный separator-with-label `═════ Clear history ═════`. NSMenu не имеет нативного "separator with title". Реализация:

- NSMenuItem с title `──── Clear history ────` (символы Box Drawings Heavy Horizontal `─` или `═`), action на `clearHistory`. Серый цвет через attributedTitle с muted foreground.
- Disabled когда history пустой.
- Сразу после него — `NSMenuItem.separator()` для отступа от items.

Альтернатива: использовать SF Symbol `trash` рядом с title для большей визуальной отделённости. Обсудим во время реализации.

#### 6.4. Settings… (заглушка)

Создать `SettingsWindow.swift` с минимальным SwiftUI Settings scene:

```swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("drpaste.hud.fontScale") var fontScale: Double = 1.0
    @State private var apiKey: String = ""
    @State private var model: String = "claude-sonnet-4-6"

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            providersTab.tabItem { Label("AI", systemImage: "sparkles") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 320)
    }
    ...
}
```

Минимум на PoC: General (font scale slider, hotkey display — read-only пока), AI (поле API key, сохраняет в providers.json), About (то же что в About panel).

Window открывается через `NSWindow` хостящий `NSHostingController(rootView: SettingsView())`. Не SwiftUI App `Settings { … }` scene, потому что у нас accessory-app не SwiftUI App, а AppKit.

#### 6.5. About DrPaste…

Полный About panel — не только copyright/version, но и **Acknowledgements** с inspirations и used libraries (в стиле Flycut, но короче). Это важно с двух сторон: уважение к open-source предшественникам, и юридическая прозрачность когда появятся библиотеки.

```swift
@objc private func showAbout() {
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: AppBrand.name,
        .applicationVersion: AppBrand.version,
        .credits: AppBrand.aboutCredits,
        .applicationIcon: AppBrand.nsIcon
    ])
}
```

Добавить в `AppBrand`:

```swift
static let version: String = "0.1.0"

static var aboutCredits: NSAttributedString {
    let body = NSMutableAttributedString()

    let tagline = NSAttributedString(string: "\(tagline)\n\n", attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.secondaryLabelColor
    ])
    body.append(tagline)

    body.append(NSAttributedString(string: """
    Copyright © 2026 iLya Os.
    Licensed under GNU GPL v3.0-or-later with attribution requirement.

    Source code: https://github.com/iLya-Os/DrPaste
    Support: https://github.com/iLya-Os/DrPaste/issues

    """))

    body.append(NSAttributedString(string: "Acknowledgements\n", attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
    ]))

    body.append(NSAttributedString(string: """

    DrPaste's design is inspired by Flycut, Maccy, Paste, and Raycast — \
    open clipboard utilities that paved the way for keyboard-first paste UX on macOS.

    Built on Apple's AppKit, SwiftUI, Core Image, Vision, and Carbon HIToolbox.

    Thanks to the open-source community for showing what's possible.
    """))

    // Когда появятся библиотеки в проекте — добавлять отдельным блоком:
    //
    // body.append(string: "\n\nDrPaste incorporates the following libraries, used with gratitude:\n")
    // body.append("  • swift-markdown by Apple (https://github.com/swiftlang/swift-markdown)\n")
    // body.append("  • KeyboardShortcuts by Sindre Sorhus (https://github.com/sindresorhus/KeyboardShortcuts)\n")
    // body.append("  • ...")

    return body
}
```

**Принципы About content:**

1. **Короче чем Flycut.** Flycut перечисляет ~15 библиотек включая legacy от Jumpcut от TigerLaunch — это правильно для долго живущего проекта со сложной историей, но для DrPaste на старте overkill. Короткий блок с inspirations + используемые frameworks.

2. **Inspirations**, не "this is fork of...". Мы не форк Flycut, мы новый проект с другой философией (press-and-hold gesture, не toggle menu). Перечисляем как влияние, не родословную.

3. **Используемые frameworks** — Apple's AppKit/SwiftUI/Core Image/Vision/Carbon. Технически это не нужно перечислять (system frameworks свободно используются любым macOS app), но это часть респекта и помогает разработчикам понять стек.

4. **Готовая структура для будущих библиотек** — закомментированный template `"DrPaste incorporates the following libraries, used with gratitude:"` со строкой на каждую библиотеку. Когда в Backlog #4 / #6 / #8 добавятся `swift-markdown`, `KeyboardShortcuts`, `Down` и другие — раскомментировать соответствующий блок.

5. **GitHub links plain text в credits.** NSAttributedString в About panel поддерживает clickable `NSLink` атрибуты — добавить через `.link: URL(...)` где есть URLs, чтобы кликабельно открывались в браузере.

**Альтернатива — отдельное About окно (богаче).** Когда в Backlog #8 появится Settings → About tab, можно сделать его более красивым: иконка побольше, формат как у SF Symbols app или Sketch (gradient header, кликабельные buttons вместо текстовых URL, версия с build number, "Made with ♥ in Sarasota" или подобный personal touch). Stock `NSApp.orderFrontStandardAboutPanel` для menu-bar About + custom view в Settings About tab — оба источника одинакового AppBrand.aboutCredits content, разные представления.

#### 6.6. Чистка существующих menu items

Сейчас в installStatusItem есть:
- "Open providers.json…" — переносится в Settings (вкладка AI)
- "Enable advanced gesture mode…" (в Limited Mode) — остаётся в основном меню, выше Settings

Структура с учётом mode:

```
DrPaste — Limited Mode             [disabled]
─────────────────────────────────
Enable advanced gesture mode…      [только в Limited]
─────────────────────────────────
Recent clipboard            ▶
─────────────────────────────────
Settings…
About DrPaste…
─────────────────────────────────
Quit DrPaste                  ⌘Q
```

### Bonus: статус-айтем live-обновление

NSMenuDelegate.menuNeedsUpdate срабатывает каждый раз когда меню открывается — submenu всегда актуальный. Не нужен timer или KVO на store. ClipboardStore @Published items не используется в меню напрямую, только лениво при открытии — efficient.

---

## Правка №7 (next iteration) — Type Slowly action + alternative commit styles

**Статус:** запланирована. Средняя правка ~100–150 строк + small architectural addition.

**Затрагивает:** новый `TypeSlowlyAction` в `Actions.swift`, новый `TypeSimulator.swift` (рядом с `PasteSimulator.swift`), `Actions.swift` protocol (расширение `apply` returning alternative commit style), `AppDelegate.commitHUD` (роутинг commit style → standard paste / type slowly), опционально Settings (Backlog #6) для configurability delay/jitter.

### Use case

Банковские формы, поля номера счёта/SWIFT/IBAN/credit card часто блокируют `paste` (JavaScript `oncontextmenu="return false"`, `onpaste="return false"`, или native iOS-style anti-paste на macOS Safari). То же бывает в:

- Корпоративных банк-клиентах
- Government / tax form порталах
- Старых ERP web-интерфейсах
- Некоторых password fields где принципиально хотят manual entry
- Игровых чатах с anti-cheat блокирующих paste

Type Slowly печатает text по одному символу через `CGEvent` с задержкой, что для приложения неотличимо от человеческого ввода — не попадает под `onpaste` event.

### Архитектурное расширение — Commit Style

В `ApplyOutcome` (см. Backlog #2 для базовой формы) добавляется четвёртый case:

```swift
enum ApplyOutcome {
    case preview(ClipboardItem)              // обычная transformation
    case failed(ClipboardItem, reason: String, recovery: RecoveryAction?)  // #2
    case sideEffect(description: String)     // Reveal / Open (#4)
    case alternativeCommit(ClipboardItem, commitStyle: CommitStyle)
}

enum CommitStyle {
    case standardPaste                       // default: write pb + simulate ⌘V
    case typeSlowly(delay: TimeInterval, jitter: Double)
    case typeFast                            // 50 ms, без jitter
    // в будущем: case typeWithoutShift (для caps-lock contexts), case rawPaste (без simulate)
}
```

В `AppDelegate.commitHUD()` после получения `.alternativeCommit(item, style)` — роутим в соответствующий simulator вместо `PasteSimulator.simulatePaste()`.

### TypeSimulator

```swift
enum TypeSimulator {
    /// Печатает строку символ за символом через CGEvent.
    /// Использует keyboardSetUnicodeString — работает для любых Unicode chars
    /// без необходимости вычислять keycode по character.
    static func typeSlowly(_ text: String,
                           baseDelay: TimeInterval = 0.2,
                           jitter: Double = 0.2,
                           onProgress: ((Int, Int) -> Void)? = nil,
                           cancellation: () -> Bool) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        let chars = Array(text)
        for (idx, ch) in chars.enumerated() {
            if cancellation() { return }

            // Обрабатываем спец-символы через настоящие keycodes:
            // newline → kVK_Return, tab → kVK_Tab
            switch ch {
            case "\n":
                postKeyEvent(source: source, keyCode: CGKeyCode(kVK_Return))
            case "\t":
                postKeyEvent(source: source, keyCode: CGKeyCode(kVK_Tab))
            default:
                postUnicodeChar(source: source, ch: ch)
            }

            onProgress?(idx + 1, chars.count)

            // jittered delay: baseDelay ± baseDelay*jitter, distributed uniformly
            let randomFactor = 1.0 + (Double.random(in: -jitter...jitter))
            let actualDelay = baseDelay * randomFactor
            try? await Task.sleep(nanoseconds: UInt64(actualDelay * 1_000_000_000))
        }
    }

    private static func postUnicodeChar(source: CGEventSource?, ch: Character) {
        let utf16 = Array(String(ch).utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: utf16.count,
                                       unicodeString: utf16)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func postKeyEvent(source: CGEventSource?, keyCode: CGKeyCode) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
```

`keyboardSetUnicodeString` — стандартный macOS способ синтезировать произвольный Unicode без mapping. Использует тот же подход что Karabiner и BetterTouchTool. Большинство input fields (включая web Forms через WebKit/Chromium) принимают это как реальный keystroke и не триггерят `onpaste`.

### TypeSlowlyAction

```swift
struct TypeSlowlyAction: ClipboardAction {
    let id = "type_slowly"
    let title = "Type Slowly (bypass paste block)"
    let isLocal = true

    func isApplicable(item: ClipboardItem, context: ContentContext) -> Bool {
        // Только для text/richText (typing image не имеет смысла).
        // Только для коротких строк — банковские номера/коды обычно ≤ 100 символов;
        // на длинных строках при 0.2s/char ждать 100+ секунд — не имеет смысла.
        guard context.contains(.plain) || context.contains(.richText) else { return false }
        guard let text = item.text else { return false }
        return text.count > 0 && text.count <= 500
    }

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        var copy = item
        copy.kind = .text
        copy.rtfBase64 = nil; copy.html = nil
        return .alternativeCommit(copy, commitStyle: .typeSlowly(delay: 0.2, jitter: 0.2))
    }
}
```

### Defaults и configurability

**Default delay:** 0.2 секунды per character. Обоснование:
- < 0.1s — некоторые anti-paste detection отлавливают как "слишком быстро для человека"
- 0.2s — комфортно, выглядит как уверенный typist (≈ 50 wpm для коротких строк)
- > 0.3s — раздражающе медленно для пользователя при длинных строках

**Default jitter:** ±20% (т.е. 0.16..0.24s). Имитирует переменный темп человеческого ввода. Без jitter паттерн регулярный — теоретически детектируем.

**Configurability через Settings** (Backlog #6):
- General → Type Slowly section:
  - Slider: Base delay 50 ms .. 500 ms
  - Toggle: Add natural jitter
  - Optional toggle: Show progress indicator during typing

### Progress indicator

Для строк > 30 символов typing занимает > 6 секунд — пользователь не понимает что происходит. Решение — transient overlay (другой от HUD, не nonactivating panel, а простой `NSPanel.statusBar` level с одной строкой):

```
Typing 12 / 47…  [████░░░░░░]   Esc to cancel
```

Появляется после первых 0.5s typing (чтобы не мелькать на коротких строках). Исчезает при completion или cancel. Глобальный `NSEvent.addGlobalMonitor(.keyDown)` слушает Esc — устанавливает cancellation flag.

### Limited Mode

Type Slowly **требует Accessibility** (как и standard paste simulation). В Limited Mode action всё равно регистрируется, но при commit возвращает `.failed(original, reason: "Type Slowly requires Accessibility permission", recovery: .openAccessibilitySettings)`. Это соответствует Backlog #2.

### Safety

- **Cancellation** через Esc — обязательно, чтобы пользователь мог прервать если ошибся с focus'ом.
- **Password fields detection** — теоретически можно через AX API определить что фокус в `AXSecureTextField` и предупредить ("This is a password field — make sure you intend to paste here"). Низкий приоритет, можно как Settings option.
- **Auto-cancel при потере focus** — если frontmost app сменился во время typing, прерываем. Защита от случайного typing'а пароля в чат.

---

## Правка №8 (next iteration) — Settings window + customizable action registry + import/export

**Статус:** запланирована. Большая архитектурная правка ~500–700 строк + новый Settings UI 200–300 строк. Превращает DrPaste из продукта с hardcoded набором actions в платформу для пользовательской конфигурации и community-распространяемых action packs.

**Затрагивает:** `Actions.swift` (полный rewrite от hardcoded к data-driven), новый `ActionDescriptor.swift`, новый `SettingsWindow.swift` с tabbed SwiftUI UI, `AIProvider.swift` (расширение под per-action provider + custom prompts), `AppDelegate` (Settings window lifecycle, hot-reload registry при изменениях), persistence layer для config.

### Целевая структура Settings window

```
┌─────────────────────────────────────────────────────────┐
│  ⚙ General │ ✨ AI │ 📋 Text │ 🌐 URL │ 🖼 Image │ ... │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  [active tab content]                                   │
│                                                         │
├─────────────────────────────────────────────────────────┤
│   Import…    Export…                          Done      │
└─────────────────────────────────────────────────────────┘
```

**Системные tabs (фиксированные):**

1. **General** — hotkey (через `KeyboardShortcuts` package), font scale slider, mode override (auto/force tap/force carbon), preferences типа auto-paste from menu.
2. **AI Providers** — список providers (Anthropic, OpenAI, Ollama, custom HTTP endpoint), API keys, models, base URLs. Add/remove providers.

**Content-type tabs (динамические, по списку semantic kinds):**

3. **Plain text** — список actions применимых к `.plain`
4. **Rich text** — actions для `.richText`
5. **URL** — для `.url`
6. **JSON** — для `.json`
7. **CSV / Table** — для `.table`
8. **Markdown** — для `.markdown`
9. **Code** — для `.code`
10. **Image** — для `.image`
11. **Files** — для `.files`

Содержимое каждого content-type tab — **playground с sample + Run-кнопками на каждом action**:

```
┌─ Plain text ────────────────────────────────────────────┐
│ Sample input:                                           │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Здравствуйте! how are you doing today?              │ │
│ │ My website is https://example.com/?utm_source=test  │ │
│ │ Контактный email: hello@example.com                 │ │
│ │ ETO PRIMER S RAZNOY RASKLADKOY.                     │ │
│ └─────────────────────────────────────────────────────┘ │
│ [Reset to default sample]                               │
│                                                         │
│ Result:                                                 │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ (output появляется здесь после нажатия Run)         │ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ Actions:                                                │
│ [✓] Paste as is                                  [Run]  │
│ [✓] Fix keyboard layout                          [Run]  │
│ [✓] UPPERCASE                                    [Run]  │
│ [✓] lowercase                                    [Run]  │
│ [✓] Title Case                                   [Run]  │
│ [✓] Trim whitespace                              [Run]  │
│ [✓] Sort lines                                   [Run]  │
│ [ ] Generate QR code              ← can disable  [Run]  │
│ ── Custom AI actions ────────────────────────────────── │
│ [✓] AI: summarize                       [edit]   [Run]  │
│ [✓] AI: translate RU↔EN                 [edit]   [Run]  │
│ [✓] AI: fix grammar                     [edit]   [Run]  │
│ [✓] AI: formal tone                     [edit]   [Run]  │
│ [+ Add custom AI action…]                               │
└─────────────────────────────────────────────────────────┘
```

**Поведение:**

- Sample input — editable text view (или image picker / file picker для image/files tab), может быть отредактирован пользователем. Сохраняется per-tab в Settings, при следующем открытии остаётся.
- "Reset to default sample" — возвращает bundled пример для этого content type.
- Result — read-only output preview, обновляется когда пользователь нажимает Run на любом action.
- **Run** — выполняет `action.apply(sampleItem, context)` и кладёт результат в Result pane. Не модифицирует pasteboard, не закрывает окно — это playground, изолированный от реального clipboard.
- Local actions выполняются мгновенно (~10 ms).
- AI actions — async со spinner в Run-кнопке. На failure (нет ключа / API error / malformed prompt) — показывается inline в Result pane как `.failed(reason: …)` (см. Backlog #2).
- Если действие меняет kind (например QR generation: text → image, OCR: image → text) — Result pane адаптирует preview под новый тип.

**Зачем это критично:**

1. **Discovery** — без Run пользователь видит только название action, но не понимает что он делает. Особенно важно для actions с непрозрачными названиями ("Slugify", "Strip tracking", "Flatten").
2. **Debugging AI prompts** — после редактирования custom AI action пользователь сразу видит работает ли prompt как ожидается, без необходимости копировать что-то в реальный clipboard.
3. **Sharing trust** — когда community распространяет action pack, пользователь может Run каждое action на стандартном sample до того как enable его в системе. "Безопасно посмотреть что делает".
4. **Tuning prompts** — итеративная разработка AI action: edit prompt → Run → видит результат → edit → Run → … без жонглирования clipboard'ом.

### Default samples

Каждый content type имеет bundled default sample, подобранный чтобы максимум applicable actions имели заметный эффект:

| Content type | Default sample (примерно) |
|---|---|
| **Plain text** | смесь русского и английского, mixed case, разная раскладка, URL with tracking, email, multiline |
| **Rich text** | bold/italic/links example с RTF и HTML representations |
| **URL** | `https://example.com/article?utm_source=newsletter&utm_medium=email&fbclid=abc123` |
| **JSON** | nested object с null values, array of objects, для теста pretty / flatten / extract keys |
| **CSV** | 3 колонки × 5 строк с headers, mixed types (numeric / string) |
| **Markdown** | примеры с headings, lists, code blocks, links, bold/italic |
| **Code** | short Swift/JS snippet с comments, нужный indent variation |
| **Image** | маленькая bundled PNG с распознаваемым текстом (для OCR demo) и QR кодом (для decode demo) |
| **Files** | список фейковых path-ов для демо paths/markdown links/SHA-256 на placeholder |

Все samples хранятся в `Sources/DrPaste/Resources/SettingsSamples/` как отдельные файлы (`plain.txt`, `url.txt`, `json.json`, ... + bundled samples.json с metadata). Грузятся через `Bundle.module` (правка совместима с уже существующим `.process("Resources")` config'ом).

### Реализация в SwiftUI

```swift
struct ContentTypeTab: View {
    let type: ContentTypeID
    @State private var sampleText: String
    @State private var sampleImage: NSImage?
    @State private var sampleFiles: [URL]
    @State private var result: ApplyOutcome? = nil
    @State private var runningActionID: String? = nil
    @ObservedObject var registry: ActionRegistry

    var body: some View {
        VStack(alignment: .leading) {
            SampleInputView(type: type, text: $sampleText, image: $sampleImage, files: $sampleFiles)
            Button("Reset to default sample") { resetSample() }

            Divider()

            ResultPaneView(outcome: result)

            Divider()

            ActionListView(
                actions: registry.descriptors(for: type),
                runningID: runningActionID,
                onToggle: { id, enabled in registry.setEnabled(id: id, enabled: enabled) },
                onEdit: { id in /* открыть AI editor sheet */ },
                onRun: { descriptor in runAction(descriptor) }
            )
        }
        .onAppear { sampleText = loadSavedSample(type) ?? loadDefaultSample(type) }
    }

    private func runAction(_ descriptor: ActionDescriptor) {
        guard let action = registry.resolve(descriptor: descriptor) else { return }
        let sampleItem = makeSampleItem()  // ClipboardItem из текущего sample
        let context = ContextDetector.detect(sampleItem)
        runningActionID = descriptor.id
        Task {
            let outcome = await action.apply(item: sampleItem, context: context)
            await MainActor.run {
                self.result = outcome
                self.runningActionID = nil
            }
        }
    }
}
```

Edit и Run кнопки рядом — Edit открывает modal sheet для редактирования AI prompt, Run выполняет action прямо сейчас.

### Особенности для разных типов

**Image tab** — sample это NSImage в preview pane, для OCR action Run меняет result pane на text (`Recognized text: "Hello world..."`). Для QR decode — текст из QR. Для image transformations (grayscale, rotate) — обновлённый image в result pane.

**Files tab** — sample это список fake path-ов, отображается как icon + filename. Run для actions типа "Copy paths as text" — кладёт строку в result text pane.

**Side-effect actions** (Reveal in Finder, Open URL) — в playground Run **не** выполняет side-effect (не открывает Finder каждый раз), а показывает в result pane что бы произошло: `This would reveal /Users/.../file.txt in Finder`. Кнопка "Actually run" в result pane для опционального real execution.

Это важная safety: пользователь нажал Run на "Open URL" — не должен внезапно открываться браузер на сэмпле URL. Только preview-of-effect.

Edit рядом с AI actions открывает inline editor (modal sheet) с полями:

```
Title:           AI: summarize
Provider:        Anthropic (Claude) ▼
Prompt template:
┌──────────────────────────────────────────────────────┐
│ Summarize the user's input in 1–3 sentences.         │
│ Reply with the summary only, no preamble.            │
└──────────────────────────────────────────────────────┘
Applies to:      [✓] Plain text  [✓] Rich text
                 [ ] URL  [ ] JSON  ...

Reset to default      Cancel      Save
```

"Add custom AI action…" открывает тот же editor с пустыми полями.

### Архитектурный сдвиг: ActionRegistry data-driven

**Сейчас:** ActionRegistry конструирует hardcoded список Swift-структур:
```swift
init() {
    self.actions = [IdentityAction(), LayoutRepairAction(), ...]
}
```

**После правки:**

```swift
struct ActionDescriptor: Codable, Identifiable {
    let id: String                          // unique key, например "builtin.uppercase" или "user.summarize-russian"
    let kind: ActionDescriptorKind          // .builtin / .ai
    var enabled: Bool
    var title: String                       // overridable для built-in (опционально)

    // Только для .ai:
    var promptTemplate: String?
    var providerID: String?                 // "anthropic" / "openai" / "ollama" / "custom-xyz"

    // На какие semantic types реагирует
    var contentTypes: Set<ContentTypeID>

    // Для built-in: id маппится на factory class в коде
    // Для AI: AIAction конструируется из этого descriptor
}

enum ActionDescriptorKind: String, Codable {
    case builtin, ai
}

final class ActionRegistry {
    private var descriptors: [ActionDescriptor]  // источник истины, сериализуется
    private var resolved: [ClipboardAction] = [] // вычисляется из descriptors

    func resolve(descriptor: ActionDescriptor) -> ClipboardAction? {
        switch descriptor.kind {
        case .builtin:
            return BuiltinActionFactory.make(id: descriptor.id, descriptor: descriptor)
        case .ai:
            guard let providerID = descriptor.providerID,
                  let prompt = descriptor.promptTemplate,
                  let provider = AIProviderRegistry.shared.provider(id: providerID) else {
                return nil
            }
            return AIAction(
                id: descriptor.id,
                title: descriptor.title,
                promptTemplate: prompt,
                provider: provider,
                applicableTypes: descriptor.contentTypes
            )
        }
    }

    func reload() { resolved = descriptors.compactMap(resolve) }
    func applicable(for item, context) -> [ClipboardAction] {
        resolved.filter { $0.isApplicable(item, context) && $0.isEnabledForContext(context) }
    }
}
```

**Built-in factory:**
```swift
enum BuiltinActionFactory {
    static func make(id: String, descriptor: ActionDescriptor) -> ClipboardAction? {
        switch id {
        case "builtin.identity":      return IdentityAction(descriptor: descriptor)
        case "builtin.uppercase":     return UppercaseAction(descriptor: descriptor)
        case "builtin.layout_repair": return LayoutRepairAction(descriptor: descriptor)
        // ... весь список
        default: return nil
        }
    }
}
```

### Persistence: actions.json

```
~/Library/Application Support/DrPaste/
  index.json                    — clipboard history (existing)
  providers.json                — AI provider configs (existing)
  actions.json                  — действующая конфигурация actions (новое)
  actions.default.json          — read-only встроенная default (новое)
  images/                       — clipboard images (existing)
```

Формат `actions.json`:

```json
{
  "version": 1,
  "actions": [
    {
      "id": "builtin.identity",
      "kind": "builtin",
      "enabled": true,
      "contentTypes": ["plain", "richText", "image", "files", "url", "json", "..."]
    },
    {
      "id": "builtin.json_pretty",
      "kind": "builtin",
      "enabled": true,
      "contentTypes": ["json"]
    },
    {
      "id": "user.summarize",
      "kind": "ai",
      "enabled": true,
      "title": "AI: summarize",
      "promptTemplate": "Summarize the user's input in 1–3 sentences. Reply with the summary only, no preamble.",
      "providerID": "anthropic",
      "contentTypes": ["plain", "richText"]
    },
    {
      "id": "user.rewrite-as-telegram",
      "kind": "ai",
      "enabled": true,
      "title": "Telegram message",
      "promptTemplate": "Rewrite the input as a casual Telegram message, no preamble.",
      "providerID": "anthropic",
      "contentTypes": ["plain"]
    }
  ]
}
```

При первом запуске копируется `actions.default.json` (bundled в Resources/) в `actions.json` если последнего нет. Дальше user редактирует только `actions.json`.

### Import / Export

**Export** — кнопка в Settings внизу. Открывает `NSSavePanel` с предложением default имени `drpaste-config-YYYY-MM-DD.json`. Сохраняет полный snapshot:

```json
{
  "version": 1,
  "exportedAt": "2026-05-25T14:23:00Z",
  "drpasteVersion": "0.1.0",
  "actions": [...],
  "providers": [...],          // без API keys (они sensitive)!
  "preferences": {
    "fontScale": 1.1,
    "hotkey": "⌥⌘V",
    "autoActivateMode": "auto"
  }
}
```

**Import** — кнопка / drag-and-drop файла в Settings. Парсится, валидируется, показывается preview ("This pack adds 12 actions: …"). Опции:
- Replace all — заменить существующую config полностью
- Merge — добавить новые actions с unique IDs, не трогать существующие
- Conflict resolution per-action (rename / skip / replace)

### Action packs sharing

Community может публиковать `.drpaste-actions.json` файлы. Пример:

```
markdown-master.drpaste-actions.json
  → +6 markdown-related AI actions: rewrite as headline, generate TOC,
    expand outline, convert to academic style, etc.

russian-bureaucrat.drpaste-actions.json
  → +8 AI actions specialized for Russian official documents:
    переписать казённо, проверить пунктуацию, перефразировать в деловой стиль, …

dev-helper.drpaste-actions.json
  → +15 actions for developers: explain code, find bug,
    rewrite as async, add type hints, etc.
```

В будущем — GitHub-based registry "drpaste-action-packs", DrPaste может тянуть curated packs по кнопке. Out of scope для PoC, но format ready.

### UI implementation notes

**SwiftUI Settings view** через `NSHostingController` (не SwiftUI App `Settings` scene — у нас accessory AppKit app).

**Динамический список tabs** генерируется из enum`ContentTypeID`:
```swift
enum ContentTypeID: String, CaseIterable, Codable {
    case plain, richText, url, json, table, markdown, code, image, files
    var displayName: String { ... }
    var symbol: String { ... }  // SF Symbol name
}
```

TabView в SwiftUI:
```swift
TabView {
    GeneralTab().tabItem { Label("General", systemImage: "gear") }
    AIProvidersTab().tabItem { Label("AI", systemImage: "sparkles") }
    ForEach(ContentTypeID.allCases) { type in
        ContentTypeTab(type: type).tabItem {
            Label(type.displayName, systemImage: type.symbol)
        }
    }
}
```

**Hot reload.** Когда пользователь меняет config — ActionRegistry.reload() вызывается асинхронно, HudState получает обновлённый список actions при следующем openHUD. Если HUD открыт прямо сейчас — `state.actions = registry.applicable(...)` пересчитывается реактивно.

### Зависимости

- **Backlog #2** (failure visibility) — для случаев когда custom AI prompt fails или provider не настроен
- **Backlog #4** (action expansion) — увеличивает количество actions до 75+, делает Settings особенно ценным (без него список не помещается на экран)
- **Backlog #6** (Settings menu item) — это правка реализует **полноценный** Settings, заменяющий stub из #6. То есть #8 either subsumes #6 либо #6 делается как заглушка до #8.

### Что не входит в эту правку

- **Hotkey rebinding UI** — отдельная работа через `sindresorhus/KeyboardShortcuts` package. В первом подходе hotkey показывается read-only.
- **Custom HTTP endpoint provider** — fields для base URL + headers. Базовый Anthropic / OpenAI / Ollama в первом подходе, custom — отдельной правкой.
- **GitHub action pack registry** — community sharing platform. Local import/export достаточно для v1.
- **Per-action UI customization** (цвет chip, icon override) — out of scope.
- **Action chains / pipelines** — например "OCR → translate" одной операцией. Сложная отдельная фича.

---

## Правка №9 (next iteration) — ⌥⌘C (Copy) и ⌥⌘X (Cut & Replace) hotkeys

**Статус:** запланирована. Средняя правка ~150–200 строк.

**Затрагивает:** `HotkeyEngine.swift` (HotkeyConfig расширяется на 3 keys, HotkeyEngineDelegate новые методы, оба engine регистрируют 3 hotkey), `PasteSimulator.swift` (новые `simulateCopy`, `simulateCut`), `AppDelegate` (новые delegate-обработчики, cut-and-replace flow).

### Философия

После освоения DrPaste пользователь автоматически ассоциирует `⌥⌘` с **любыми** clipboard операциями. Раз `⌥⌘V` = paste, то рука сама пойдёт на `⌥⌘C` для copy и `⌥⌘X` для cut. Если эти комбинации не перехватить — в одних приложениях они ничего не делают, в других делают что-то странное (TextEdit `⌥⌘C` = "Copy Style"). Перехватим и сделаем то, что **интуитивно ожидается**: copy / cut с участием DrPaste.

Это unified mental model: один модификатор `⌥⌘` для всех clipboard-жестов.

### Поведение

| Hotkey | Что делает |
|---|---|
| **`⌥⌘C`** | Simulated `⌘C` в frontmost. Selection попадает в pasteboard, ClipboardWatcher подхватит и добавит в историю. **HUD не открывается** — это one-shot операция. |
| **`⌥⌘X`** | Simulated `⌘X` в frontmost. Selection вырезается, попадает в pasteboard и добавляется в историю. Затем **открывается HUD** как при `⌥⌘V`. На commit выбранный item вставляется на место вырезанного. Это "swap": вырезал → выбрал из истории → вставил на то же место. |
| `⌥⌘V` | (как есть) Press-and-hold HUD для выбора и вставки. |

### Use cases

**`⌥⌘C` обычный copy.** Пользователь приучился к `⌥⌘V` для paste. Естественно нажать `⌥⌘C` для copy. Если приложение само переопределяет `⌥⌘C` (TextEdit Copy Style) — наш CGEventTap в Full Gesture Mode проглатывает событие и заменяет на чистый `⌘C`. В Limited Mode — Carbon hotkey стреляет, мы делаем simulated `⌘C`, но оригинальный `⌥⌘C` в приложении тоже сработает (Carbon не глотает). Конфликт минимальный потому что `⌥⌘C` редко имеет destructive action.

**`⌥⌘X` swap-paste.** Очень частый сценарий: у меня в поле текст "old value", я хочу заменить на ранее скопированное "new value". Без DrPaste: select all → ⌘V (или ⌘A → Delete → ⌘V). С DrPaste базовый: ⌘A → ⌥⌘V → выбрал new value → release. С Backlog #9: select all → `⌥⌘X` → "old value" в истории, HUD открыт → выбрал new value → release → "new value" на месте. Это **на одно нажатие меньше** и сохраняет "old value" в истории (т.е. можно undo через выбор обратно).

### Архитектурное расширение HotkeyEngine

**HotkeyConfig:**

```swift
struct HotkeyConfig {
    let pasteKeyCode: CGKeyCode       // V (был triggerKeyCode)
    let copyKeyCode: CGKeyCode        // C (новое)
    let cutKeyCode: CGKeyCode         // X (новое)
    let modifiers: CGEventFlags       // ⌥⌘ для всех трёх
}
```

**Delegate:**

```swift
enum SummonReason {
    case paste              // ⌥⌘V: открыть HUD, при commit — write+paste
    case cutAndReplace      // ⌥⌘X: simulated ⌘X → открыть HUD → при commit — write+paste на место вырезанного
}

protocol HotkeyEngineDelegate: AnyObject {
    func hotkeyEngineDidSummon(reason: SummonReason)      // ⌥⌘V / ⌥⌘X
    func hotkeyEngineDidQuickCopy()                        // ⌥⌘C: симулировать ⌘C, HUD не открывать
    func hotkeyEngineDidRelease()
    func hotkeyEngineDidNavigate(_ direction: NavDirection)
    func hotkeyEngineDidCancel()
    func hotkeyEngineDidRequestFontChange(_ change: FontChange)
}
```

**EventTapEngine.handle расширяется:**

```swift
if type == .keyDown && modsPresent && !hudIsActive {
    let kc = ...
    if kc == config.pasteKeyCode {
        hudIsActive = true
        delegate?.hotkeyEngineDidSummon(reason: .paste)
        return nil
    }
    if kc == config.cutKeyCode {
        hudIsActive = true
        delegate?.hotkeyEngineDidSummon(reason: .cutAndReplace)
        return nil
    }
    if kc == config.copyKeyCode {
        delegate?.hotkeyEngineDidQuickCopy()
        return nil
    }
}
```

**CarbonHotKeyEngine** регистрирует три hotkey через три вызова `RegisterEventHotKey` с разными `EventHotKeyID.id` (1 для paste, 2 для cut, 3 для copy). В callback различаем по `hkID.id`.

### AppDelegate flow

```swift
nonisolated func hotkeyEngineDidQuickCopy() {
    Task { @MainActor in
        // Simulated ⌘C в frontmost. Watcher автоматически подхватит и добавит в историю.
        // Можно опционально transient flash в menu bar icon как acknowledgement.
        PasteSimulator.simulateCopy()
    }
}

nonisolated func hotkeyEngineDidSummon(reason: SummonReason) {
    Task { @MainActor in
        if reason == .cutAndReplace {
            // 1. Simulated ⌘X: selection вырезается, попадает в pasteboard.
            PasteSimulator.simulateCut()
            // 2. Даём macOS успеть обработать cut и watcher подхватить новый pasteboard content.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.openHUD()
            }
        } else {
            self.openHUD()
        }
    }
}
```

### PasteSimulator расширение

```swift
enum PasteSimulator {
    static func simulatePaste() { /* как было */ }
    static func simulateCopy()  { postKeyboardShortcut(keyCode: kVK_ANSI_C) }
    static func simulateCut()   { postKeyboardShortcut(keyCode: kVK_ANSI_X) }

    private static func postKeyboardShortcut(keyCode: Int) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        cmdDown?.flags = .maskCommand
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: false)
        keyUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        let loc = CGEventTapLocation.cghidEventTap
        cmdDown?.post(tap: loc); keyDown?.post(tap: loc); keyUp?.post(tap: loc); cmdUp?.post(tap: loc)
    }
}
```

### Limited Mode (Carbon) специфика

Carbon `RegisterEventHotKey` не глотает события. Это значит:

- **`⌥⌘C`** в Limited Mode — наш hotkey сработает + оригинальный `⌥⌘C` в приложении тоже. В большинстве приложений `⌥⌘C` = ничего или "Copy Style" → дублирующий copy через нас не вредит, а часто даёт правильное поведение (просто copy вместо style copy).
- **`⌥⌘X`** в Limited Mode — наш hotkey + оригинальный `⌥⌘X` в приложении. `⌥⌘X` редко переопределён, обычно ничего не делает. Наш simulateCut срабатывает корректно.

Конфликты минимальны, но Limited Mode банеры можно расширить, упомянув что в Full Gesture Mode свопы работают чище.

### Дополнительный visual feedback для `⌥⌘C`

Поскольку `⌥⌘C` не открывает HUD, пользователю нужно подтверждение "сработало" — иначе он не знает скопировалось ли что-то. Опции:

1. **Никакого UI** — полагаемся на native pasteboard feedback (некоторые apps показывают tooltip "Copied!"). Минимальное вмешательство.
2. **Transient menu bar icon flash** — иконка status item на 200ms подсвечивается accent color. Тонко, не мешает.
3. **Mini HUD** — крошечный overlay "Copied: <snippet>" на 1.2 сек в углу экрана.

Рекомендую **вариант 2** (flash) — достаточно для feedback, не отвлекает, не требует focus management. Реализация через `statusItem.button?.appearsDisabled = true` на 200ms или контролируемое изменение image.

### Конфигурируемость в Settings (Backlog #8)

В General tab добавляются opt-out toggles:

- ☑ Enable `⌥⌘C` Quick Copy
- ☑ Enable `⌥⌘X` Cut & Replace
- ☑ Visual feedback on Quick Copy

Если пользователь предпочитает чтобы `⌥⌘C` работал как app default (например любит TextEdit Copy Style) — может отключить. По умолчанию обе включены.

### Edge cases

- **Empty selection.** Если ничего не выделено, `⌥⌘X` ничего не вырежет, watcher не получит новый item, история не пополнится. HUD откроется, но purpose "swap" будет неоднозначным — пользователь увидит обычный HUD как при `⌥⌘V`. Поведение не критично, оставляем.
- **Frontmost is DrPaste.** Если HUD только что закрылся и focus случайно на нашем приложении — `⌥⌘C` / `⌥⌘X` симулируем в наш же UI, что бесполезно. Защита: проверять что `NSWorkspace.shared.frontmostApplication.bundleIdentifier != Bundle.main.bundleIdentifier` перед simulate.
- **Race condition cut → watcher → HUD.** Между simulateCut и openHUD должно пройти достаточно времени чтобы (a) приложение обработало cut, (b) pasteboard.changeCount изменился, (c) watcher tick зацепил новое содержимое. Текущий watcher polls 0.5s — может не успеть до openHUD за 80 ms. Решение: при cutAndReplace принудительно вызвать `watcher.tick()` synchronous после задержки.

---

## Правка №10 (next iteration) — Звуковой фидбек (copy / paste / type)

**Статус:** запланирована. Средняя правка ~150–200 строк + 5 sound assets.

**Затрагивает:** новый `SoundFeedback.swift`, `AppDelegate` (вызовы из commit/quickCopy/cut), `PasteSimulator` (детекция success/failure через pasteboard.changeCount), `TypeSimulator` (type-tick на каждый символ), `Resources/Sounds/` (5 коротких aiff/m4a), Settings General tab (toggles per-sound).

### Принцип

Многие clipboard операции не имеют визуального feedback'а (особенно `⌥⌘C` Quick Copy в Backlog #9 — HUD не открывается, пользователь не знает сработало или нет). Звук — самый эффективный канал для мгновенного "сработало / не сработало", занимает 50–150 ms и не требует focus shift.

Также важно для **accessibility**: слабовидящие пользователи используют звук как primary feedback channel.

### Категории звуков

| Звук | Когда играть | Default | Tone |
|---|---|---|---|
| **copy-success** | Quick Copy (`⌥⌘C`) сработал — pasteboard.changeCount увеличился | on | тихий "tink", positive |
| **copy-failure** | Quick Copy — pasteboard не изменился (empty selection или app заблокировал) | on | короткий низкий "buzz", negative |
| **paste-success** | Commit из HUD (release / Enter / dbl-click / Recent menu item) сработал | on | мягкий "click", subtle positive |
| **paste-failure** | Action вернул `.failed` (AI без ключа, malformed input — после Backlog #2) | on | "buzz", same as copy-failure |
| **type-tick** | Каждый символ во время Type Slowly typing (Backlog #7) | on | очень тихий клик клавиши, типа печатной машинки |

Все звуки **короткие** (50–150 ms), низкая громкость, не отвлекают. Не sustained sounds — мгновенный transient.

### Source файлов

Для PoC используем bundled короткие aiff файлы в `Sources/DrPaste/Resources/Sounds/`:

- `copy-success.aiff` — kbd-like мягкий клик (можно начать с system `Tink.aiff` дублированного к нам в Resources, но переименованного для брендового контроля)
- `copy-failure.aiff` — короткий "tssk"
- `paste-success.aiff` — может совпадать с copy-success, либо разный (рекомендую разный — пользователь хочет различать copy от paste)
- `paste-failure.aiff` — совпадает с copy-failure
- `type-tick.aiff` — очень тихий keyboard tick, мс 30, ниже громкости всех остальных

Альтернатива (быстрый старт) — использовать system sounds через `NSSound(named:)`:

```swift
NSSound(named: "Tink")?.play()       // copy-success
NSSound(named: "Funk")?.play()       // failure
NSSound(named: "Pop")?.play()        // paste-success
NSSound(named: "Morse")?.play()      // type-tick (но слишком громко — нужно volume)
```

Это работает out-of-the-box без bundled assets, но звуки общеизвестные. Для брендирования заменить на свои aiff позже.

### Settings (Backlog #8 → General tab)

Раздельные toggles, default все включены:

```
Sound feedback
  ☑ Copy success
  ☑ Copy failure
  ☑ Paste success
  ☑ Paste failure
  ☑ Type Slowly tick
        Volume:  [─────●───] 60%
```

Volume — глобальный multiplier (0..100%, default 60%) применяется к всем звукам. Per-sound volume — overkill для PoC.

### Implementation

```swift
enum SoundCue: String {
    case copySuccess  = "copy-success"
    case copyFailure  = "copy-failure"
    case pasteSuccess = "paste-success"
    case pasteFailure = "paste-failure"
    case typeTick     = "type-tick"

    var defaultsKey: String { "drpaste.sound.\(rawValue)" }
}

enum SoundFeedback {
    private static var cache: [SoundCue: NSSound] = [:]

    static func play(_ cue: SoundCue) {
        // Проверяем toggle
        guard UserDefaults.standard.bool(forKey: cue.defaultsKey + ".enabled", default: true) else { return }
        let volume = Float(UserDefaults.standard.double(forKey: "drpaste.sound.volume", default: 0.6))

        let sound: NSSound?
        if let cached = cache[cue] {
            sound = cached.copy() as? NSSound   // copy чтобы не блокировать concurrent plays
        } else if let url = Bundle.module.url(forResource: cue.rawValue, withExtension: "aiff"),
                  let s = NSSound(contentsOf: url, byReference: false) {
            cache[cue] = s
            sound = s.copy() as? NSSound
        } else {
            // fallback на system sound по соответствию
            sound = NSSound(named: systemFallback(cue))
        }
        sound?.volume = volume
        sound?.play()
    }

    private static func systemFallback(_ cue: SoundCue) -> NSSound.Name {
        switch cue {
        case .copySuccess, .pasteSuccess: return NSSound.Name("Tink")
        case .copyFailure, .pasteFailure: return NSSound.Name("Funk")
        case .typeTick:                   return NSSound.Name("Morse")
        }
    }
}

// helper extension для UserDefaults default value
extension UserDefaults {
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        if object(forKey: key) == nil { return defaultValue }
        return bool(forKey: key)
    }
    func double(forKey key: String, default defaultValue: Double) -> Double {
        if object(forKey: key) == nil { return defaultValue }
        return double(forKey: key)
    }
}
```

### Где вызывать

**`⌥⌘C` Quick Copy (Backlog #9):**

```swift
nonisolated func hotkeyEngineDidQuickCopy() {
    Task { @MainActor in
        let countBefore = NSPasteboard.general.changeCount
        PasteSimulator.simulateCopy()
        // Дать macOS время обработать ⌘C
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let countAfter = NSPasteboard.general.changeCount
            if countAfter > countBefore {
                SoundFeedback.play(.copySuccess)
            } else {
                SoundFeedback.play(.copyFailure)   // ничего не скопировалось
            }
        }
    }
}
```

Это даёт **реальную детекцию** copy failure: если selection был пустой или приложение заблокировало `⌘C` — `pasteboard.changeCount` не изменится за 150 ms → играем failure звук.

**Paste commit (HUD release / Enter / Recent menu item):**

```swift
private func commitHUD() {
    // ... write to pasteboard, simulate ⌘V
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        PasteSimulator.simulatePaste()
        SoundFeedback.play(.pasteSuccess)
    }
}
```

**Paste failure (после Backlog #2):**

```swift
// в refreshPreview / commitHUD
if case .failed(_, let reason, _) = outcome {
    SoundFeedback.play(.pasteFailure)
}
```

**Type Slowly tick:**

```swift
// в TypeSimulator.typeSlowly loop
for (idx, ch) in chars.enumerated() {
    if cancellation() { return }
    postUnicodeChar(...)
    SoundFeedback.play(.typeTick)   // каждый символ
    try? await Task.sleep(...)
}
```

### Можно ли поймать paste failure?

Прямой ответ на твой вопрос — **частично, но точно нельзя**. Разбор:

**Что можно детектировать:**

1. **DrPaste не записал в pasteboard** — это полный наш контроль, всегда знаем. Это редкость (write всегда работает).
2. **simulatePaste не достучался до системы** — определимо через CGEventTapPostStatus, грубо. Edge case.
3. **Action перед commit вернул `.failed`** — Backlog #2 даёт нам это explicitly. Тогда commit не пытается paste'ить, играет paste-failure звук.

**Что нельзя надёжно детектировать:**

1. **Target field readonly / paste blocked by JavaScript** — мы посылаем ⌘V, приложение принимает event, дальше внутри приложения логика решает что делать. У нас нет канала обратной связи "paste был принят".
2. **Focus ушёл в другое поле в момент paste** — race condition, не отлавливаем.
3. **Vis JavaScript `onpaste="return false"`** — paste event приходит в браузер, JS возвращает false, текст не вставляется, но pasteboard остался — мы не различаем "вставилось" vs "не вставилось".

**Эвристика для better-than-nothing detection (можно добавить как opt-in advanced):**

Через AX API мы можем получить значение `kAXValueAttribute` у frontmost AXTextField/AXTextArea до и после paste с задержкой 100 ms. Если value не содержит наш text — paste не сработал.

```swift
// псевдокод
let beforeValue = getFrontmostTextFieldValue()
PasteSimulator.simulatePaste()
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    let afterValue = getFrontmostTextFieldValue()
    if (afterValue ?? "").contains(insertedText) {
        SoundFeedback.play(.pasteSuccess)
    } else {
        SoundFeedback.play(.pasteFailure)
    }
}
```

**Минусы этой эвристики:**

- AX API требует Accessibility (у нас уже есть в Full Mode)
- Не все frontmost фокусы являются AXTextField (image fields, canvas, non-Cocoa apps)
- Privacy: мы читаем содержимое поля — это sensitive
- Работает только для текстовых insertions, не для image/files paste
- Race condition с 150 ms задержкой может ошибиться

**Рекомендация:** в первой реализации играем `paste-success` всегда после commit (acknowledgement действия пользователя, не верификация результата). Опциональный "Smart paste verification" toggle в Settings → Advanced — exit-stage feature после стабилизации, не для v1.

### Volume calibration

Type tick особенно — должен быть **тише** других звуков. 30% от global volume в коде, не настройка. Иначе на длинной строке (60+ символов) превращается в раздражение.

Возможно добавить acceleration — первые 3 символа громче (чтобы пользователь заметил активацию режима), дальше fade до минимума. Out of scope для v1, идея на потом.

### Накопленные звуки во время быстрых операций

Если пользователь делает несколько `⌥⌘C` подряд за секунду — каждый раз играть звук может прозвучать как стрекот. Решение: throttle 200 ms (не играть тот же sound если предыдущий вызов был < 200 ms назад). Применить ко всем sounds кроме type-tick (там это часть UX).

---

## Дальнейшие пункты backlog'а

(будут добавляться по мере того как накапливаются идеи)
