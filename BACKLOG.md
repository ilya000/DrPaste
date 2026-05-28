# DrPaste — Backlog

Отложенные правки в порядке приоритета. Когда стабилизируется текущая база и начнётся следующая итерация — берём №1 первой.

---

## Следующая волна (накапливается)

### #12 — Action Editor «Applies to»: показывать ВСЕ типы контента + disabled state для неприменимых

**Статус:** запланирована. UX правка ~30 строк (расширить allTypes + computed applicable mask + disabled binding).

**Затрагивает:** `ActionEditor.swift` — `allTypes` array, `applicableTypesSection`, `inferApplicableTypes`.

**Контекст:** в screenshot — Edit Action для `builtin.image_strip_meta` (action работает с картинками). В секции **Applies to** видны: Plain text / Rich text / URL / JSON / Table / Markdown / Code / Files. **НЕТ Image и PDF.** При этом Plain text оказался по умолчанию checked — что бессмысленно: strip_meta не умеет работать с plain text.

Две проблемы:

1. **Отсутствуют типы Image, PDF** (и возможно Email) в списке checkbox'ов. `allTypes` определён неполно:
   ```swift
   private let allTypes: [SemanticKind] = [.text, .richText, .url, .json, .table, .markdown, .code, .files]
   ```
   Image / PDF / Email отсутствуют.

2. **Inapplicable типы** должны быть **disabled и unchecked**. Для image action — Plain text checkbox не должен быть кликабельным. Пользователь не может «применить» strip_meta к тексту — action.isApplicable вернёт false.

**Желаемое поведение:**

В Applies to показываются **ВСЕ** SemanticKind кроме `.unknown`:
- Plain text
- Rich text
- URL
- Email
- JSON
- Code
- Markdown
- Table
- Image
- PDF
- Files

Для каждого типа определяем — **applicable ли** этот action к этому типу:

- **Built-in mode**: вызываем `action.isApplicable(item: sample, context: ctx)` для sample каждого type. Если false → checkbox disabled + grayed.
- **Transformation mode**: engine.applicableSet (text engines — все text-based types; image engines — image only; и т.д.). Hardcoded по engine kind.
- **AI mode**: AI applicable ко всем text-based + richText. Image / Files — disabled (AI prompts работают с текстом). PDF — disabled (нужно extraction step).

**Implementation:**

```swift
private let allTypes: [SemanticKind] = [
    .text, .richText, .url, .email, .json, .code, .markdown, .table, .image, .pdf, .files
]

private func isTypeApplicable(_ kind: SemanticKind) -> Bool {
    switch self.kind {
    case .builtin:
        guard let action = registry.actions.first(where: { $0.id == builtinID })
        else { return false }
        let sample = SettingsSamples.sample(for: kind)
        let ctx = ContextDetector.detect(sample)
        return action.isApplicable(item: sample, context: ctx)

    case .transformation:
        // Text-based engines применимы к text/richText/markdown/code/table/url/json/email
        // Other engines — none
        return [.text, .richText, .markdown, .code, .table, .url, .email, .json].contains(kind)

    case .ai:
        // AI применимы к text-based contexts
        return [.text, .richText, .markdown, .code, .url, .email, .json, .table].contains(kind)
    }
}

// В applicableTypesSection
ForEach(allTypes, id: \.self) { type in
    let isApplicable = isTypeApplicable(type)
    Toggle(isOn: Binding(
        get: { applicableTypes.contains(type) },
        set: { isOn in
            guard isApplicable else { return }  // защита от программного toggling
            if isOn { applicableTypes.insert(type) }
            else { applicableTypes.remove(type) }
        }
    )) {
        Text(type.displayName)
            .font(.system(size: 12))
            .foregroundStyle(isApplicable ? .primary : .tertiary)
    }
    .toggleStyle(.checkbox)
    .disabled(!isApplicable)
}
```

**Visual treatment** disabled checkbox: macOS SwiftUI Toggle с `.disabled(true)` автоматически становится gray и uncheckable. Text label тоже dim (через `foregroundStyle(.tertiary)`).

**При Save** — фильтровать `applicableTypes` через isTypeApplicable (на случай если в config попал inapplicable type из-за legacy migration). Защита от ошибочных states.

**Pre-fill при open editor:**

`loadInitialState` для built-in — `inferApplicableTypes(builtinID:)` уже использует `isApplicable`. Расширить allTypes — теперь image strip_meta получит { .image } по умолчанию, не { .text }.

**Verification:** открыть Edit на strip_meta:
- Image checkbox **есть**, **enabled**, **checked**
- Plain text / Rich text / URL / JSON / etc — **disabled, grayed, unchecked** (юзер не может включить)
- Если попытаться clicked disabled — Toggle не отвечает (macOS native behavior)

Открыть Edit на UPPERCASE:
- Plain text / Rich text / Markdown / Code etc — enabled, checked (selected или нет)
- Image / PDF / Files — disabled, grayed, unchecked

Открыть Edit на translate (AI):
- Plain text / Rich text / Markdown / Code / URL / Email / Table / JSON — enabled
- Image / PDF / Files — disabled

**Принцип:** UI **показывает полный domain** (все типы), но **honors capability** (disabled неприменимые). Юзер сразу понимает что action может и не может, не теряется в усечённом списке.

---

### #11 — Settings action rows: consistent type-icon перед названием для всех типов

**Статус:** запланирована. UX правка ~30 строк (новый helper `iconForAction(_:) -> (name: String, color: Color)?` + использование в actionRow для built-ins).

**Затрагивает:** `SettingsWindow.swift` — actionRow (built-in) + customTransformationRow (уже OK) + customAIRow (уже OK).

**Контекст:** сейчас в Settings → Content tab → Actions list:
- **AI rows** (customAI) показывают provider badge (Claude / GPT / Gemini icon) перед title — OK
- **Transformation rows** (customTransformations) показывают engine icon (function / magnifyingglass / text.append / text.quote / line.horizontal.3.decrease) перед title — OK
- **Built-in rows** (плейн ClipboardAction) — НЕТ иконки. Просто drag handle + toggle + title.

Это **визуально неконсистентно** — юзер не видит сразу что за тип action'а перед ним. AI и transformation легко отличимы, built-in выглядит «голым».

После применения **#9 + #10** (seed AI и transformations как user data) — большинство actions будут customAI/customTransformation → автоматически получают иконку. Останутся только «real» built-ins:

- `identity` — Paste as is
- `paste_as_text`
- `rich_to_md`, `rich_to_html`, `rich_to_wiki`
- `layout_repair`
- `generate_qr`
- `image_*` (OCR, decode_qr, strip_metadata, resize, grayscale, rotate, invert)
- `files_*` (paths, names, md_links, bash_list, size, sha256, reveal)
- `type_slowly`

**Желаемое:** каждая built-in action row получает свою иконку (semantic SF Symbol).

**Mapping built-in id → SF Symbol:**

```swift
enum BuiltinActionIcons {
    static func iconName(for actionID: String) -> String {
        switch actionID {
        case "builtin.identity": return "doc.on.clipboard.fill"
        case "builtin.paste_as_text": return "text.alignleft"
        case "builtin.rich_to_md": return "doc.richtext"
        case "builtin.rich_to_html": return "chevron.left.forwardslash.chevron.right"
        case "builtin.rich_to_wiki": return "book.closed"
        case "builtin.layout_repair": return "globe"
        case "builtin.generate_qr": return "qrcode"
        case "builtin.image_ocr": return "text.viewfinder"
        case "builtin.image_decode_qr": return "qrcode.viewfinder"
        case "builtin.image_strip_metadata": return "eye.slash"
        case "builtin.image_resize_1920": return "arrow.up.left.and.down.right.magnifyingglass"
        case "builtin.image_compress_jpeg": return "rectangle.compress.vertical"
        case "builtin.image_grayscale": return "circle.lefthalf.filled"
        case "builtin.image_rotate_90": return "rotate.right"
        case "builtin.image_invert": return "circle.righthalf.filled"
        case "builtin.files_paths": return "doc.on.doc"
        case "builtin.files_names": return "doc.text"
        case "builtin.files_md_links": return "link"
        case "builtin.files_bash_list": return "terminal"
        case "builtin.files_size": return "ruler"
        case "builtin.files_sha256": return "number"
        case "builtin.files_reveal": return "folder"
        case "builtin.type_slowly": return "keyboard"
        default: return "gearshape"  // fallback для legacy built-ins до seed migration
        }
    }
}
```

**В actionRow добавить:**

```swift
HStack(spacing: 8) {
    // drag handle (как было)
    Image(systemName: isLocked ? "lock.fill" : "line.3.horizontal")
        ...
    // toggle (как было)
    Toggle("", isOn: enabledBinding(action.id)) ...

    // НОВОЕ: type-icon
    Image(systemName: BuiltinActionIcons.iconName(for: action.id))
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: 16)

    VStack(alignment: .leading, spacing: 1) {
        Text(displayTitle) ...
    }
    ...
}
```

Цвет — `.secondary` (subtle, не отвлекает). 16pt frame для visual alignment с провайдер/engine badges (которые тоже ~16pt).

**Visual consistency:** все три типа rows имеют icon в той же позиции (после toggle, перед title):
- AI row: `[badge with provider icon]` (orange/green/blue/etc circle)
- Transformation row: `[engine icon]` (function / magnifyingglass / text.append / etc) gray
- Built-in row: `[type icon]` (semantic SF Symbol) gray

**Цветовая differentiation:**

- AI rows — coloured badge (provider brand color)
- Transformation rows — accent color icon (consistent with engine concept)
- Built-in rows — gray icon (neutral, hardcoded behaviour)

Это даёт visual hint о типе action'а **с первого взгляда** в списке.

**Verification:** в Settings → Text tab после волны — список actions имеет иконки слева от каждого названия. Identity = clipboard icon, Paste as text = text alignment icon, UPPERCASE = case_change engine icon, summarize = Claude badge. Никаких «голых» rows.

---

### #10 — Архитектурно: built-in transformations seed'ятся как editable CustomTransformation, не hardcoded

**Статус:** запланирована. Продолжение принципа из #9 для transformation-style built-ins. Архитектурная правка ~200 строк (new engines + seed step + удаление hardcoded action структур).

**Затрагивает:** `CustomTransformation.swift` (новые engines), `Actions.swift` / `TextActions.swift` / `URLActions.swift` / `MoreActions.swift` (удалить те actions которые становятся seeded transformations), `Actions.swift` ActionRegistry seed.

**Контекст:** этот же принцип что #9 — **не фиксировать в коде то что является данными**. Сейчас множество built-in actions имеют логику которая ровно эквивалентна tranformation engines (regex_replace, find_replace, prepend, append, wrap, line_filter). Они закрыты, юзер не может их править. **Эффективно** их seed'ить как user data.

**Список built-ins которые могут быть transformations:**

С существующими engines:
- `builtin.trim` → `engine.regex_replace`, pattern `^\s+|\s+$`, replacement empty + flag multiline
- `builtin.url_strip_tracking` → `engine.regex_replace`, pattern `[?&](utm_[^=&]*|fbclid|gclid|ref|mc_eid)=[^&]*`, replacement empty
- `builtin.url_just_domain` → `engine.regex_replace`, pattern `^https?://([^/]+).*`, replacement `$1`
- `builtin.url_md_link` / `url_html_link` → `engine.wrap`, prefix/suffix
- `builtin.code_wrap` → `engine.wrap`, prefix ` ``` `, suffix ` ``` `
- `builtin.tabs_to_spaces` → `engine.find_replace`, find `\t`, replace `    `
- `builtin.spaces_to_tabs` → `engine.find_replace`, find `    `, replace `\t`
- `builtin.md_extract_headings` → `engine.line_filter`, pattern `^#+\s`, mode `keep`
- `builtin.md_extract_links` → `engine.line_filter` (или regex_replace для extraction)
- `builtin.slugify` — chain нескольких regex (need pipeline support? или single complex regex)

С НОВЫМИ engines которые надо добавить:

| Новый engine | Заменяет built-in | Описание |
|---|---|---|
| `engine.case_change` | uppercase, lowercase, title_case, sentence_case | param `case`: upper / lower / title / sentence |
| `engine.case_convert` | camelCase, snake_case, kebab_case | param `style`: camel / snake / kebab — для programmer naming |
| `engine.sort_lines` | sort_lines | param `direction`: asc / desc; `caseInsensitive` |
| `engine.unique_lines` | unique_lines | param `keepOrder`: bool |
| `engine.json_format` | json_pretty, json_minify, json_extract_keys, json_flatten, json_remove_nulls | param `operation`: pretty / minify / extractKeys / flatten / removeNulls |
| `engine.url_format` | url_encode, url_decode | param `mode`: encode / decode |
| `engine.base64` | base64_encode, base64_decode | param `mode`: encode / decode |
| `engine.html_entities` | (новая) HTML entity encode / decode | param `mode`: encode / decode |
| `engine.word_count` | word_count | возвращает text info — count, lines, chars |
| `engine.table_csv` | table_to_json, table_to_md | param `mode`: toJSON / toMD; `separator`: tab / comma / auto |
| `engine.table_transpose` | table_transpose | без параметров |
| `engine.md_to_plain` | md_to_plain | strip markdown markup |

**Что ОСТАЁТСЯ как real built-in actions** (нельзя выразить через transformations — нужны Swift API):

- `builtin.identity` — Paste as is, semantic anchor (всегда locked)
- `builtin.paste_as_text` — strip formatting через NSAttributedString
- `builtin.rich_to_md` — NSAttributedString → Markdown
- `builtin.rich_to_html` — NSAttributedString → HTML
- `builtin.rich_to_wiki` — NSAttributedString → Wiki
- `builtin.layout_repair` — char-by-char keyboard layout reverse lookup (специфическая логика, не regex)
- `builtin.generate_qr` — CoreImage QR generation (image output)
- `builtin.image_*` — Vision / CoreImage (OCR, decode QR, strip metadata, resize, grayscale, rotate, invert)
- `builtin.files_*` — FileManager + sandbox-aware (paths, names, md_links, bash_list, size, sha256, reveal)
- `builtin.type_slowly` — keyboard simulation (special commit style)

**Seed логика:**

В `ActionRegistry.init` после AI seed (#9) — transformation seed:

```swift
if config.seedTransformationsVersion < CurrentTransformationsSeedVersion {
    seedDefaultTransformations()
    config.seedTransformationsVersion = CurrentTransformationsSeedVersion
    config.save()
}

private func seedDefaultTransformations() {
    let defaults: [CustomTransformationDescriptor] = [
        CustomTransformationDescriptor(
            id: "user.trim",
            title: "Trim whitespace",
            engineID: "regex_replace",
            parameters: ["pattern": "^\\s+|\\s+$", "replacement": "", "caseInsensitive": "false"],
            applicableTypes: ["text", "markdown", "code"]
        ),
        CustomTransformationDescriptor(
            id: "user.uppercase",
            title: "UPPERCASE",
            engineID: "case_change",
            parameters: ["case": "upper"],
            applicableTypes: ["text"]
        ),
        // ... etc
    ]
    for d in defaults where !config.customTransformations.contains(where: { $0.id == d.id }) {
        config.customTransformations.append(d)
    }
}
```

**Удаление hardcoded structs:**

После seed — структуры типа `UppercaseAction`, `LowercaseAction`, `TrimWhitespaceAction`, `URLStripTrackingAction`, `JSONPrettyAction`, etc. — удаляются из codebase. Они больше не нужны.

**Hotkey migration:**

Существующие `actionHotkeys["builtin.uppercase"]` → переезжают на `actionHotkeys["user.uppercase"]` в migration step.

**Преимущества:**

1. **~50%+ built-ins становятся editable** — юзер может настроить trim regex pattern, добавить свои параметры в strip_tracking, изменить sort direction
2. **Discoverability** — открыв Edit на trim, юзер видит реальный regex pattern и понимает что происходит
3. **Меньше Swift кода** — десятки struct'ов с ClipboardAction conformance → удалены, заменены seeded data
4. **Customization without compile** — юзер сам делает варианты (например «trim only trailing whitespace») редактируя seeded transformations или клонируя их

**Что сохраняется:**

- Все default-enabled subset через CuratedDefaults.swift — обновить чтобы знал про user.* ids вместо builtin.*
- Sort order через actionOrder — id-based, migrate
- Sounds, applicable contexts, behaviour — без изменений для юзера

**Verification:** после migration в Settings → Text tab видим те же действия (UPPERCASE, Trim whitespace, Sort lines, и т.д.) но pencil edit открывает full Transformation editor — видны engine + params, можно править. Identity / paste-as-text / rich → md/html/wiki / image actions — остаются Built-in mode (real Swift hardcoded).

**Применять одной волной с #9** — чтобы обе архитектурные переработки шли вместе, единая migration step.

---

### #9 — Архитектурно: убрать factory `ai.*` actions, seed их как editable customAI на first launch

**Статус:** запланирована. **Replaces / supersedes #8** — более чистое решение. Архитектурная правка ~80 строк (DefaultAIActions removed, ActionRegistry seed-on-first-launch logic).

**Затрагивает:** `AIProvider.swift` (удалить `DefaultAIActions.make()`), `Actions.swift` (ActionRegistry.init добавить seed step), `main.swift` (убрать register для DefaultAIActions), `ActionConfig.swift` (опционально добавить version-tracked seeded flag).

**Контекст:** сейчас `DefaultAIActions.make()` создаёт hardcoded AIAction объекты с id `ai.summarize`, `ai.translate_es_en`, `ai.fix_grammar`, `ai.translate_es_en_rich`, `ai.fix_grammar_rich`, `ai.formal_tone` — и регистрирует их в `registry.actions` массиве напрямую. Они никогда не попадают в `config.customAI`, поэтому Edit открывается в Built-in mode, prompt locked.

**Архитектурный вопрос:** **зачем фиксировать AI action в коде?** AI action — это **prompt + provider**. Нет hardcoded logic за prompt'ом. Это user-facing данные, должны жить в config где user может править.

**Желаемое решение — seed default AI actions в customAI на first launch:**

1. Удалить `DefaultAIActions.make()` метод и его использование в `main.swift`.

2. В `ActionRegistry.init` после `ActionConfig.load()` добавить **seed step**:
   ```swift
   if config.seedVersion < CurrentSeedVersion {
       seedDefaultAIActions()
       config.seedVersion = CurrentSeedVersion
       config.save()
   }
   ```

3. `seedDefaultAIActions()` создаёт `CustomAIDescriptor` записи для каждого preset:
   ```swift
   private func seedDefaultAIActions() {
       let defaults: [CustomAIDescriptor] = [
           CustomAIDescriptor(
               id: "user.summarize",
               title: "summarize",
               promptTemplate: "Summarize the user's input in 1–3 sentences...",
               providerID: AIProviderRegistry.shared.config.defaultProviderID ?? "anthropic",
               applicableTypes: ["text", "richText", "markdown", "code"]
           ),
           CustomAIDescriptor(
               id: "user.translate",
               title: "translate",
               promptTemplate: "Translate the input to Spanish. If the user provides text in Spanish, translate to English instead. Reply with the translation only.",
               providerID: ..., applicableTypes: ["text", "richText", "markdown"]
           ),
           // ... аналогично для translate (rich), fix grammar, fix grammar (rich), formal tone
       ]
       for d in defaults where !config.customAI.contains(where: { $0.id == d.id }) {
           config.customAI.append(d)
       }
   }
   ```

4. **`seedVersion`** в ActionConfig — Int, инкрементируется когда мы добавляем новые default AI actions. Existing users получают новые presets при upgrade. Уже существующие не дублируются (проверка по id).

5. **Migration для existing 0.8.0 users:** при первой загрузке с новой версией — детектируется seedVersion = 0 → seed запускается → factory ai.* пресеты появляются в customAI как regular descriptors. Юзер видит их в Settings как обычные custom AI actions, может править prompt/provider/applicable.

6. **Удалить из ContentTypeTab applicableActions filter:** `!$0.id.hasPrefix("user.")` остаётся (они в customAI). Pencil edit на customAI → open в AI mode (текущий путь .editAI). Никаких branchings на `ai.*` prefix — он больше не существует.

7. **Hotkey IDs:** существующие per-action hotkeys для `ai.summarize` etc. — обнулятся при migration. **Migrate hotkeys:** если есть `actionHotkeys["ai.summarize"]`, перенести на `actionHotkeys["user.summarize"]` (один-к-одному mapping). Это автоматически в migration step.

**Преимущества:**

1. **Прозрачно для юзера** — все AI actions одинаковые, все editable, никаких «факторий с заблокированным prompt».
2. **Архитектурно чисто** — DefaultAIActions.make() perpetually hardcoded магия не нужна. Все AI actions — данные в config.
3. **Юзер может удалить дефолтные** — если не нужен `summarize` или `formal_tone`, просто delete из Settings. Не залочены в коде.
4. **Юзер может изменить prompt** — сразу, не через workaround.
5. **Provider override per-action** — уже работает через customAI.providerID, теперь применяется и к defaults.

**Что #8 решал workaround'но → теперь решено архитектурно.**

**Verification:** после migration в Settings → Text tab видны те же AI actions (summarize, translate, fix grammar, formal tone, и т.д.) — но pencil edit открывает full AI editor с prompt template editable, Provider picker, Templates menu. Никаких «Mode locked» / «Built-in handler» labels. Можно freely менять.

---

### #8 — Edit AI factory preset: открывать в AI mode (editable prompt), не в Built-in mode

**УСТАРЕЛО — заменено на #9.** Оставлено для истории на случай если #9 окажется too disruptive и потребуется fallback workaround.

**Статус:** запланирована. UX правка ~50 строк (детекция `ai.*` prefix + branching в ActionEditor context).

**Затрагивает:** `SettingsWindow.swift` (ContentTypeTab actionRow pencil click → context routing), `ActionEditor.swift` (новый mode `.editFactoryAI` или routing edit through .editAI с factory descriptor).

**Контекст:** в screenshot — юзер открыл `ai.translate_es_en_rich` (factory preset с готовым prompt'ом «Translate to Spanish ↔ English»). Edit dialog открылся в режиме **Built-in** — locked handler `ai.translate_es_en_rich`, нет prompt editor'а. Юзер может только rename / hotkey / applicable types — НО **не может изменить prompt** на «Translate to French ↔ English» под свой workflow.

**Это неестественно** — AI action by definition имеет prompt template как core. Если пользователь видит AI action, он ожидает что может посмотреть и поправить prompt. Иначе factory presets — closed black boxes.

**Корень архитектурно:** factory AI actions создаются через `DefaultAIActions.make()` и регистрируются в `actions[]` массиве с id `ai.translate_*`, `ai.summarize`, etc. Они НЕ в `config.customAI`. Когда юзер клик'ает pencil → `editorContext = .editBuiltin(...)` → редактор в built-in mode → prompt locked (built-in handlers по определению hardcoded logic).

**Желаемое поведение:**

При pencil click на action где id начинается с `ai.` (factory AI preset):
- Открывать ActionEditor в **AI mode** (не Built-in)
- Pre-fill prompt template из factory action's `promptTemplate` (через ((`AIAction`)`)
- Pre-fill provider из action's `providerID` (или default)
- Pre-fill applicable types из action's `applicableTypes`
- Title editable как обычно

**Save behavior:**

При Save юзер фактически создаёт user-level customAI override:
- Если юзер ничего не изменил из {prompt, provider, applicableTypes} vs factory → save идёт через customTitles + actionHotkeys (тот же flow что built-in override)
- Если изменил prompt / provider / applicable types → создать `CustomAIDescriptor` в `customAI` с id `ai.translate_es_en_rich.user` (или другой scheme) который **shadowing'ует** factory preset

Альтернативный простой подход: **factory AI actions при первом edit'е автоматически клонируются в customAI** (with id, например, `user.<factoryID>.<random>`), и в HUD больше не показываются с factory id — только user version. Factory id остаётся в коде как fallback, но если есть user override — он используется.

**Ещё проще — "Fork to customize" pattern:**

Если юзер начинает менять prompt/provider в Edit dialog для factory AI:
- Save создаёт NEW CustomAIDescriptor в customAI (id `user.<uuid>`)
- Factory preset остаётся как был
- Юзер получает свою копию которую можно freely менять
- В Settings list — обе видны: factory original + user copy

В UI editor показать кнопку **«Reset to default prompt»** рядом с prompt editor (как Reset to default title) — для случая когда юзер хочет вернуть factory text.

**Решение для волны:** второй подход — **branch on `ai.*` prefix** в pencil-click handler:

```swift
Button {
    if action.id.hasPrefix("ai.") {
        // Factory AI preset → open in AI mode pre-filled from action
        let aiAction = action as? AIAction
        let descriptor = CustomAIDescriptor(
            id: action.id,    // keep factory id для consistency
            title: registry.displayTitle(forActionID: action.id, defaultTitle: action.title),
            promptTemplate: aiAction?.promptTemplate ?? "",
            providerID: aiAction?.providerID ?? AIProviderRegistry.shared.config.defaultProviderID ?? "anthropic",
            applicableTypes: Array(aiAction?.applicableTypes.map { $0.rawValue } ?? []),
            enabled: true
        )
        editorContext = .editAI(descriptor)
    } else {
        editorContext = .editBuiltin(
            actionID: action.id,
            defaultTitle: action.title,
            description: BuiltinActionMetadata.descriptions[action.id] ?? ""
        )
    }
} label: {
    Image(systemName: "pencil")
}
```

**При Save AI action с id начинающимся с `ai.`** — registry.upsertCustomAI(descriptor). При rebuildCustomAI замечает override id и **дедупликация** — user version shadowing'ует factory version в actions list.

Альтернативно: добавить `factoryAIOverrides: [String: CustomAIDescriptor]` отдельно в ActionConfig — где key = factory id, value = override.

**Verification:** после правки клик pencil на `ai.translate_es_en_rich` → видим Title + Prompt template editor + Provider picker + Templates menu + Applicable types. Меняем prompt на «Translate to French ↔ English». Save. В HUD действие теперь использует новый prompt.

---

### #7 — Rich Text preview formatting (HUD + Settings) — повторный фикс

**Статус:** запланирована. Bug — критичный для UX rich text actions. ~80 строк (NSViewRepresentable wrapper для NSTextView).

**Затрагивает:** `HUD.swift` (richTextView + ImagePreview wrapper), `SettingsWindow.swift` (ResultPane.preview rich branch).

**Контекст:** в 0.8.0 был «фикс» через `AttributedString(ns, including: \.swiftUI)` — но **не работает**. Bold / italic / inline code / colors **по-прежнему не видны** в preview.

**Корни проблемы:**

1. **`AttributedString(NSAttributedString, including: \.swiftUI)` — lossy конверсия.** SwiftUI's `AttributedString` поддерживает limited subset attributes. Семейство шрифтов, font traits (bold/italic), background colors часто **теряются** при конверсии через `\.swiftUI` scope. Это known issue в SwiftUI Text rendering.

2. **`.font(.system(size: sz(12)))` modifier поверх `Text(attr)` — overrides attr fonts.** В HUD.swift:
   ```swift
   Text(attr).font(.system(size: sz(12)))
   ```
   `.font()` modifier APPLIES TO ENTIRE Text. Если у attr внутри есть bold/italic fonts — они **затираются** этим modifier'ом. Это объясняет почему всё рендерится одним plain шрифтом.

**Правильное решение — NSViewRepresentable wrapper для NSTextView:**

NSTextView **нативно** рендерит NSAttributedString со всеми attributes (bold, italic, links, colors, font sizes, alignment, lists). Это самый верный способ показать rich content.

**Implementation:**

Новый файл `RichTextPreview.swift`:

```swift
import SwiftUI
import AppKit

struct RichTextPreview: NSViewRepresentable {
    let attributedString: NSAttributedString
    var fontScale: CGFloat = 1.0

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainer?.lineFragmentPadding = 6
        textView.textContainerInset = NSSize(width: 0, height: 6)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Применяем font scale умножением existing font sizes
        let scaled = NSMutableAttributedString(attributedString: attributedString)
        if fontScale != 1.0 {
            scaled.enumerateAttribute(.font, in: NSRange(location: 0, length: scaled.length)) { value, range, _ in
                if let f = value as? NSFont {
                    let scaledFont = NSFont(descriptor: f.fontDescriptor,
                                            size: f.pointSize * fontScale) ?? f
                    scaled.addAttribute(.font, value: scaledFont, range: range)
                }
            }
        }
        textView.textStorage?.setAttributedString(scaled)
    }
}
```

**В HUD.swift** заменить:

```swift
@ViewBuilder
private func richTextView(_ item: ClipboardItem) -> some View {
    if let attr = loadNSAttributedString(item) {
        RichTextPreview(attributedString: attr, fontScale: state.fontScale)
    } else {
        Text(item.previewText ?? "").font(.system(size: sz(12)))
    }
}

private func loadNSAttributedString(_ item: ClipboardItem) -> NSAttributedString? {
    if let rel = item.representations["public.rtf"],
       let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)) {
        return try? NSAttributedString(data: data,
                                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                                        documentAttributes: nil)
    }
    if let rel = item.representations["public.html"],
       let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)) {
        return try? NSAttributedString(data: data,
                                        options: [.documentType: NSAttributedString.DocumentType.html,
                                                  .characterEncoding: String.Encoding.utf8.rawValue],
                                        documentAttributes: nil)
    }
    return nil
}
```

**В SettingsWindow.swift** заменить `loadRichAttributedString` + использование:

```swift
} else if item.semantic == .richText,
          let nsAttr = loadRichNSAttributedString(item) {
    RichTextPreview(attributedString: nsAttr, fontScale: 1.0)
} else {
    ...
}

private func loadRichNSAttributedString(_ item: ClipboardItem) -> NSAttributedString? {
    // как loadNSAttributedString из HUD
}
```

**Удалить старые helpers:** `makeAttributedString`/`loadRichAttributedString` (которые возвращают `AttributedString`) — больше не нужны.

**Verification:**

После применения проверить на rich-sample.rtf что:
- "Welcome to DrPaste" — крупный bold (h1)
- "press-and-hold" — bold inline
- "жестами" → "gestures" (после правки #4 русский был убран) — italic
- "code" — monospaced
- ссылка `github.com/ilya000/DrPaste` — синяя underlined
- маркированный список с bullets

Все должны рендериться визуально как rich text. **Без подмены plain text.**

---

### #6 — Type Slowly: убрать формулировки про обход / bypass / banking / anti-cheat

**Статус:** запланирована. Tiny text правка ~10 строк в нескольких файлах. Compliance / трактовка как malware.

**Затрагивает:** `BuiltinActionEditor.swift` (BuiltinActionMetadata.descriptions), `TypeSimulator.swift` (comments), `README.md`, `SKILL.md`, `BACKLOG.md` (historical entries).

**Контекст:** сейчас в нескольких местах есть формулировки типа:
- "Types the text character-by-character via key events — **bypasses paste blockers** (banking forms, anti-cheat)."
- "**Банковские формы**, поля номера счёта/SWIFT/IBAN/credit card часто блокируют paste..."
- "Игровых чатах с **anti-cheat блокирующих paste**"

Эти фразы могут быть интерпретированы (Apple notarization review, App Store, security scanner'ы, корпоративные blocklists) как **вредоносное ПО**: «обход защиты», «обход банковских блокировок», «обход анти-чита» — это паттерны фразеологии malware.

**Замена на нейтральные формулировки:**

| Старая | Новая |
|---|---|
| "Types the text character-by-character via key events — bypasses paste blockers (banking forms, anti-cheat)" | "Types the text character-by-character — useful where regular paste isn't supported or you prefer simulated typing" |
| "Use case: банковские формы, anti-cheat" | "Use case: input fields that prefer typed entry; demos / screen recordings; legacy forms" |
| "bypass paste-block" | "type instead of paste" / "simulated typing" |

**Конкретные места которые надо переписать:**

1. **`BuiltinActionEditor.swift`** — `BuiltinActionMetadata.descriptions["builtin.type_slowly"]`:

   Старое: `"Types the text character-by-character via key events — bypasses paste blockers (banking forms, anti-cheat)."`

   Новое: `"Types the text character-by-character with a small delay between keys. Useful for input fields that don't accept paste, demos, or screen recordings."`

2. **`TypeSimulator.swift`** — header comment с use case'ом. Убрать упоминание banking / anti-cheat. Оставить нейтральное: «simulates typing for fields that don't accept paste or prefer typed input».

3. **`README.md`** — если есть упоминание use case'ов Type Slowly, заменить на нейтральные.

4. **`SKILL.md`** — если есть, заменить.

5. **`BACKLOG.md`** — historical entries в правках #7 (Type Slowly). Эти entries — описание планирования, но текст с «банковские формы» лучше тоже переписать на нейтральный для consistency. Можно либо удалить detail про use cases, либо переписать.

**Принцип формулировок впредь:**

- НЕ говорить про «обход», «bypass», «защиту»
- НЕ называть конкретные «защищённые» контексты (banking, financial, anti-cheat, DRM, security software)
- Говорить нейтрально: «simulated typing», «character-by-character input», «when paste isn't available», «for typed-entry workflows»
- Use cases: demos, screen recordings, legacy systems, accessibility, forms that prefer typed entry — все эти формулировки neutral

**Action — пройти grep'ом по `bypass|banking|anti-cheat|paste block|onpaste`** и переписать каждое вхождение. Сейчас 5 файлов:
- `BACKLOG.md`
- `Sources/DrPaste/BuiltinActionEditor.swift`
- `README.md`
- `Sources/DrPaste/TypeSimulator.swift`
- `SKILL.md`

---

### #5 — AI Provider: принудительный test connection перед Save

**Статус:** запланирована. UX правка ~30 строк (ProviderEditor — disabled Save до прохождения test).

**Затрагивает:** `SettingsWindow.swift` → `ProviderEditor` — Save button disabled до успешного test, либо Save сам запускает test и блокирует если fail.

**Контекст:** сейчас ProviderEditor имеет отдельную кнопку "Test connection" + кнопку Save. Пользователь может Save без теста → сохранит broken config → потом в HUD AI actions молча returning `.failed` (или ругаются на 401/404). Юзер думает что всё настроено, на самом деле нет.

**Желаемое поведение:**

При нажатии Save:
1. Если test ещё не запускался ИЛИ последний test не успешный → **запустить test автоматически**
2. Показать progress индикатор «Testing connection…»
3. **Только если test успешный** → сохранить config + Keychain key, закрыть editor
4. Если fail → показать error в editor (как сейчас при ручном Test) + кнопка остаётся доступной для повторной попытки (изменил key/model → попробовал снова)

**Edge cases:**

- **Pure metadata change** (например только displayName, без изменения key/model/baseURL): test не нужен, save проходит без test. Условие: если ничего из {apiKey, model, baseURL} не изменилось vs существующая запись → skip test.
- **Local providers без auth** (Ollama, LM Studio, llama.cpp): test connection пытается достучаться до baseURL. Если local сервис не запущен — test fail. Юзер сначала запускает Ollama, потом сохраняет. Reasonable.
- **Network temporarily unavailable**: test fail → юзер не может сохранить даже валидный config. Mitigation: добавить «Save without testing» опцию в footer? Или fall-through через advanced ⌥-Click? Достаточно: при network error в error message подсказать «check your connection and try again» — юзер либо чинит сеть, либо ждёт.
- **Long-running test**: cap timeout 10 секунд. Если timeout — fail с понятной error.

**Implementation skeleton:**

```swift
@State private var testPassed: Bool = false
@State private var dirty: Bool = false   // были ли изменены auth-relevant поля

// На onChange любого auth-поля: dirty = true, testPassed = false

Button("Save") {
    if dirty || testPassed == false {
        runTestThenSaveIfPassed()
    } else {
        commitSave()
    }
}
.disabled(testing)
```

```swift
private func runTestThenSaveIfPassed() {
    testing = true
    testResult = nil
    Task { @MainActor in
        // save key + provider temporarily для test
        let keyForTest = apiKey
        let providerForTest = provider
        if !keyForTest.isEmpty {
            APIKeyStorage.save(keyForTest, for: providerForTest.id)
        }
        AIProviderRegistry.shared.upsert(providerForTest)
        let result = await AIProviderRegistry.shared.testConnection(providerID: providerForTest.id)
        testing = false
        switch result {
        case .success(let msg):
            testResult = "✓ \(msg)"
            testPassed = true
            // Финальный save и закрываем editor
            onClose(ProviderEditorResult(config: providerForTest,
                                          apiKey: keyForTest.isEmpty ? nil : keyForTest))
        case .failure(let e):
            testResult = "✗ \(errorMessage(e))"
            testPassed = false
            // НЕ закрываем editor — юзер чинит и пробует снова
        }
    }
}
```

**Manual "Test connection" кнопка остаётся** — для случаев когда юзер хочет проверить без save. Просто Save теперь тоже тестит.

**UI копи:**

Save button label меняется в зависимости от состояния:
- Default: `Save`
- Во время testing: `Testing…` + ProgressView
- Если test passed previously и dirty=false: `Save` (instant)

Tooltip на Save: «Tests the connection before saving to prevent broken configs.»

**Принцип:** broken AI config — silent footgun. Лучше блокировать Save чем потом удивлять пользователя при использовании.

---

### #4 — Type Slowly: автостоп при любой пользовательской активности

**Статус:** запланирована. Безопасность UX правка ~50 строк (TypeSimulator + observers).

**Затрагивает:** `TypeSimulator.swift` — добавить cancellation observers; `main.swift` — pass cancellation handle при запуске.

**Контекст:** Type Slowly печатает текст посимвольно с задержкой 0.2s. Если у юзера в середине типа:
- Сменился focus (случайно кликнул в другое окно / поле) — продолжаем печатать в неверном месте, может попасть в чат / другое поле / адресную строку
- Нажал любую клавишу — конфликт с simulated typing, может получиться мешанина
- Случайно переключил workspace через Mission Control — typing продолжается в новом контексте

Это **dangerous**: представь — typing пароль в банк, юзер случайно switch'нул на Slack, и наш typing допечатывает пароль в чат.

**Желаемое поведение:**

Type Slowly **немедленно прекращается** при ЛЮБОМ из событий:

1. **Key press** (кроме самих synthesized events от нас — фильтр через `DrPasteSyntheticMarker`)
2. **Mouse click** (любая кнопка)
3. **Window focus change** — переключился frontmost app
4. **Application activation** — другая app стала active
5. **Workspace / space switch** — Mission Control gesture

**Implementation skeleton:**

В `TypeSimulator.typeSlowly`:

```swift
final class TypingSession {
    var cancelled: Bool = false
    var monitors: [Any] = []
    let originalFrontmostPID: pid_t
    let started: Date

    init() {
        self.originalFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        self.started = Date()
    }
}

static func typeSlowly(_ text: String, baseDelay: TimeInterval, jitter: Double) async {
    let session = TypingSession()
    installMonitors(session)
    defer { removeMonitors(session) }

    for ch in text {
        if session.cancelled {
            NSLog("DrPaste: Type Slowly cancelled mid-stream")
            return
        }
        await postUnicodeChar(ch)
        let delay = baseDelay * (1 + Double.random(in: -jitter...jitter))
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

private static func installMonitors(_ session: TypingSession) {
    // 1. Global key monitor (любой key press, кроме наших synthetic)
    let keyMon = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
        // Если event не наш — cancel
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) != DrPasteSyntheticMarker {
            session.cancelled = true
        }
    }
    if let m = keyMon { session.monitors.append(m) }

    // 2. Mouse clicks
    let mouseMon = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
        session.cancelled = true
    }
    if let m = mouseMon { session.monitors.append(m) }

    // 3. Frontmost app change
    let appObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil, queue: .main
    ) { note in
        let newPID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
            .processIdentifier ?? 0
        if newPID != session.originalFrontmostPID {
            session.cancelled = true
        }
    }
    session.monitors.append(appObserver)

    // 4. Space/workspace change (опционально)
    let spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification,
        object: nil, queue: .main
    ) { _ in session.cancelled = true }
    session.monitors.append(spaceObserver)
}

private static func removeMonitors(_ session: TypingSession) {
    for monitor in session.monitors {
        if let workspaceObserver = monitor as? NSObjectProtocol {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        } else {
            NSEvent.removeMonitor(monitor)
        }
    }
}
```

**Feedback при cancel:**
- Sound feedback: `pasteFailure` cue (короткий buzz) — даёт audio signal что typing прервался
- Optional: показать transient banner "Type Slowly cancelled — focus changed" 2 сек в menu bar? Возможно overkill, sound достаточно

**Edge cases:**

1. **NSEvent global monitor требует AX permission.** В Limited Mode без AX мы и так не запускаем Type Slowly (TypeSlowlyAction возвращает `.failed` с recovery `.openAccessibilitySettings`). Так что эта проверка уже есть.

2. **Synthesized events filtration.** Наши собственные posted CGEvents помечены `DrPasteSyntheticMarker` (от правки #16). Global monitor можно отфильтровать через `event.cgEvent?.getIntegerValueField(.eventSourceUserData)`.

3. **Mouse moves НЕ ловим.** Только clicks. Move через trackpad — это естественное поведение во время typing'а, нельзя cancel'ить.

4. **Modifier keys.** Если юзер просто держит Shift / Cmd без key down — не cancel'им. Только `.keyDown` events (буквы/цифры/etc).

5. **First few ms grace period?** Юзер нажал ⌥⌘V → выбрал action → release. В момент release он может всё ещё держать ⌥⌘ — это вызовет flagsChanged events, не keyDown. Так что не должно срабатывать. Но если будет ложно — добавить grace period 100 ms после старта.

**Default behavior — ON.** Это safety feature, не optional. Без неё Type Slowly опасен.

---

### #3 — HUD footer: показывать текущий zoom в процентах

**Статус:** запланирована. Маленькая UI правка ~5 строк (форматирование hint в footer).

**Затрагивает:** `HUD.swift` — `footer` view, hint строка `⌘+/-`.

**Контекст:** при использовании `⌘+`/`⌘-`/`⌘0` для font scaling в HUD сейчас не видно текущий уровень — пользователь зуммит наугад. После нескольких нажатий не помнит сколько шагов было.

**UX:**

В footer rightmost hint (где сейчас `⌘+/-  zoom`) добавить процент текущего fontScale:

```
... ⌘+/-  zoom 100%
... ⌘+/-  zoom 130%   (после нескольких ⌘+)
... ⌘+/-  zoom 70%    (после нескольких ⌘-)
```

`fontScale` хранится в `HudState.fontScale` (от 0.7 до 1.6). Процент = `Int(fontScale * 100)`.

**Implementation:**

Заменить hint на `keyHint("⌘+/-", "zoom \(Int(state.fontScale * 100))%")` — реактивно через @Published.

Опционально: при `fontScale == 1.0` показывать без процентов (`zoom`), при отклонении — с процентами. Это убирает шум на default. Но возможно явный `100%` лучше — visual consistency, никаких mode jumps.

**Решение:** всегда показывать процент — пользователь сразу видит текущее значение, не надо догадываться когда `zoom` vs `zoom 100%`.

### #2 — ⌥⌘S Append Copy: session-based reset логика

**Статус:** запланирована. Поправка к существующей реализации #12 (0.8.0) — добавить session tracking чтобы избежать surprise со старым clipboard содержимым.

**Затрагивает:** `main.swift` — `hotkeyEngineDidAppendCopy()` + state tracking (`lastAppendCopyTime`, `lastDrPasteHotkeyTime`).

**Проблема в текущей реализации:** при первом нажатии ⌥⌘S мы append'им к **whatever is in clipboard** — даже если там лежит что-то старое, не имеющее отношения к текущей задаче пользователя. Это surprise: «там остатки того чего я не ожидал».

**Желаемое поведение:**

**Первое нажатие** `⌥⌘S` (см. определение «первое» ниже):
1. Сохранить текущий clipboard в history (через watcher.forceTick — он сам подхватит)
2. Очистить clipboard
3. Симулировать ⌘C → захватить selection в чистый clipboard
4. Это новая «accumulator session»

**Последующие нажатия** `⌥⌘S` (в той же session):
1. Симулировать ⌘C → захватить selection
2. Объединить с previous accumulator content (текущая логика)

**Что считается «первым нажатием»** (т.е. начало новой session):
- Прошло **≥ 5 минут** с последнего DrPaste hotkey (любого — ⌥⌘V/C/X/S или per-action)
- ИЛИ пользователь использовал любой DrPaste hotkey **кроме** ⌥⌘S (т.е. была другая операция, accumulator session должна сброситься)

**State в AppDelegate:**

```swift
private var lastAppendCopyTime: Date? = nil
private var lastDrPasteAction: DrPasteAction = .none

enum DrPasteAction {
    case none
    case appendCopy
    case other     // paste / cut / copy / per-action hotkey
}
```

**Logic in `hotkeyEngineDidAppendCopy`:**

```swift
let isNewSession: Bool = {
    // Если предыдущее DrPaste-действие было НЕ appendCopy → новая session
    if lastDrPasteAction != .appendCopy { return true }
    // Если прошло > 5 минут → новая session
    if let last = lastAppendCopyTime,
       Date().timeIntervalSince(last) > 300 { return true }
    return false
}()

if isNewSession {
    // 1. Save old clipboard to history
    watcher.forceTick()    // подхватит текущий clipboard если изменился
    // 2. Clear pasteboard
    NSPasteboard.general.clearContents()
    // 3. Simulate ⌘C → fresh capture
    PasteSimulator.simulateCopy()
    // ... wait for changeCount, play sound
} else {
    // Append к существующему (текущая логика)
    ...
}

lastAppendCopyTime = Date()
lastDrPasteAction = .appendCopy
```

**Также нужно tracking всех остальных hotkey'ев чтобы помечать `lastDrPasteAction = .other`:**

- `hotkeyEngineDidSummon(reason: .paste)` → `.other`
- `hotkeyEngineDidSummon(reason: .cutAndReplace)` → `.other`
- `hotkeyEngineDidQuickCopy()` → `.other`
- `actionHotkeyDidFire` (per-action hotkey) → `.other`

**State обнуляется при restart** — session это про in-app workflow, не нужна persistence через launches.

**Hardcoded константы (без Settings UI):**
- Timeout 5 минут — фиксированный
- Любой не-`⌥⌘S` DrPaste hotkey сбрасывает session — фиксированно

**UX feedback:** при first press (new session) играть `copySuccess` звук как обычно — пользователю не нужно знать что это «new session». Internal logic.

### #1 — Welcome window: предупреждение об отсутствии Accessibility доступа

**Статус:** запланирована. Маленькая UI правка ~50 строк (новая секция в `WelcomeView` + deep link helper).

**Затрагивает:** `WelcomeWindow.swift` — добавить conditional warning section, проверка `AXIsProcessTrusted()`, deep link на System Settings → Privacy & Security → Accessibility, кнопка «Restart DrPaste».

**Контекст:** сейчас DrPaste detect'ит AX и автоматически fallback'ится на Limited Mode (Carbon hotkeys). Welcome window не упоминает об этом. Пользователь может не понимать почему не работают gesture features.

**UX:**

В `WelcomeView` добавить условную секцию (показывается если `AXIsProcessTrusted() == false`):

```
┌─────────────────────────────────────────────────────────────┐
│ ⚠ Limited Mode — Accessibility access not granted           │
│                                                             │
│ DrPaste needs Accessibility permission to:                  │
│  • Detect ⌥⌘V press-and-hold gesture (release to paste)     │
│  • Intercept keyboard navigation inside the HUD             │
│  • Simulate paste into the frontmost app                    │
│                                                             │
│ Without it, the app runs in Limited Mode — open HUD with    │
│ ⌥⌘V, press Enter to paste (no press-and-hold).              │
│                                                             │
│ To enable full Gesture Mode:                                │
│  1. Open System Settings → Privacy & Security →             │
│     Accessibility                                           │
│  2. Find DrPaste in the list and turn the toggle ON         │
│  3. Restart DrPaste                                         │
│                                                             │
│   [Open Accessibility Settings…]    [Restart DrPaste]       │
└─────────────────────────────────────────────────────────────┘
```

Выделено accent color (orange / yellow tint), чтобы привлекать внимание.

**Implementation:**

```swift
private var hasAXAccess: Bool { AXIsProcessTrusted() }

@ViewBuilder
private var axWarningSection: some View {
    if !hasAXAccess {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Limited Mode — Accessibility access not granted")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("DrPaste needs Accessibility permission to detect press-and-hold gestures, intercept HUD keyboard navigation, and simulate paste...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            // 3 numbered steps
            HStack {
                Button("Open Accessibility Settings…") { openAXSettings() }
                Button("Restart DrPaste") { restartApp() }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
    }
}

private func openAXSettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
}

private func restartApp() {
    let exePath = Bundle.main.executablePath ?? Bundle.main.bundleURL.path
    let process = Process()
    process.executableURL = URL(fileURLWithPath: exePath)
    try? process.run()
    NSApp.terminate(nil)
}
```

Deep link `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` — стандартный URL для прямого открытия Privacy Accessibility tab. Работает на macOS 13+.

Restart использует существующий метод из `AppDelegate.restartApp()` — нужно либо вызывать через NotificationCenter, либо сделать публичный helper.

**Размещение:** между header и description, как первая секция чтобы пользователь сразу видел проблему.

**Полл AX trust:** после restart показ welcome заново. Также в AppDelegate уже есть `startAXMonitor()` который polls каждые 3 секунды — если grant'нули в реальном времени, warning section reactively обновится (через `@State private var hasAXAccess: Bool` + observer).

---

## Итерация 4 — для 0.7.0+ (discussion items)

### Discussion #1 — Action keyboard shortcuts (⌘1, ⌘2, … в HUD)

**Идея:** в HUD пользователь нажимает ⌘1 для запуска первого action из списка, ⌘2 — второй, и так далее. Quick-trigger без navigate стрелками.

**Открытые вопросы:**

1. **Что считать «первым»?** Идущий первым в filtered list (с учётом search и action order)? Или фиксированный slot — например ⌘1 всегда «Paste as is», ⌘2 — «Paste as text»? Фиксированные slots дают muscle memory, dynamic — гибкость.
2. **Как избежать конфликта с системными ⌘1-⌘9?** В macOS ⌘1-⌘9 часто перехватываются apps (tab switching в Safari, workspaces). Поскольку HUD активен и EventTap intercept'ит — мы можем глотать ⌘1-⌘9 пока HUD открыт. Безопасно.
3. **Только цифры 1-9 или больше?** ⌘0 свободен (уже использован для font reset). ⌘1-⌘9 даёт 9 quick slots — достаточно. ⌥⌘1-⌥⌘9 — extra 9 slots для редко используемых.
4. **Какой commit style?** ⌘N immediately commit's (как release) или просто выделяет action и нужен ещё release/Enter? Думаю — immediate commit (это весь смысл shortcut'а).
5. **Пинить actions к slots?** Пользователь может пометить «UPPERCASE → ⌘5» в Settings. Иначе слоты автоматически следуют action order.

**Pricing complexity:**
- Dynamic slots (следуют order): простая правка ~30 строк
- Pinned slots (per-action assignment): UI + persistence ~80 строк
- Both: ~100 строк + Settings UI для assignment

Жду решения по этим вопросам.

### Discussion #2 — Per-app provider override

**Идея:** в зависимости от frontmost app использовать разный AI provider.

Например:
- Когда копируешь из work-приложений (Outlook, Slack, Teams, banking sites) → AI запросы идут в **local Ollama** (privacy).
- Когда личное (Notes, Safari personal browsing) → Claude (качество).
- При работе с кодом (Xcode, VS Code) → GPT-5 (хорош для кода).

**Open questions:**

1. **Bundle ID matching:** по точному bundle ID (`com.apple.mail`)? Или есть категории (work / personal / dev)? Bundle ID точнее, но требует enum'а от пользователя. Категории — гибче, но heuristic'и хрупки.
2. **Какой источник bundle ID?** Сам `item.sourceBundleID` (где **скопировано**). Не frontmost при apply (это HUD).
3. **Override on rich vs plain?** Например для rich text всегда Claude (лучше форматирование), для plain — фигуральный default.
4. **Per-action override?** Может быть проще: каждый action имеет optional `providerOverrideForApps: [bundleID: providerID]`. Сложнее, но точечно.
5. **UI complexity:** где это настраивать? В Settings → AI → «Per-app routing» с таблицей `bundleID + provider`?
6. **Defaults:** при первой настройке какой mapping предложить? Возможно «Mail / Slack / Teams → local» как defaults?

**Альтернативный подход — content-based routing вместо app-based:**

Вместо bundle ID — детектить **признаки secrets в content**:
- Соответствует patterns API key / token / SSN / credit card → local
- Иначе — cloud default

Это privacy-first, не зависит от app. Может быть проще как fallback или вообще лучше.

Жду обсуждения.

### Discussion #3 — Hotkey rebinding alternative (твоя идея)

Ты упомянул что у тебя «немного другая но похожая идея». Спросить пользователя позже:
- Что за идея?
- Если не hotkey rebinding (⌥⌘V на любую комбу) — что вместо?
- Возможно chord-based shortcuts? Sequence triggers? Mode switch?

Записываю слот для обсуждения когда вернёшься к этому.

---

## Итерация 3 — для 0.4.0

### Правка №1 (iteration 3) — ⌥⌘X UX: option "start cursor on second item"

**Статус:** запланирована. Маленькая правка ~10 строк (toggle в Settings + условие в openHUD).

**Контекст:** обсуждалось 2026-05-26. По дефолту cursor встаёт на just-cut item (это native — release без navigation = no-op, как undo). Некоторые пользователи могут предпочесть auto-skip на второй item — пусть будет toggle.

**В Settings → General → HUD section:**

```
Cut & Replace (⌥⌘X)
  ☐ Start cursor on second item (skip just-cut)
```

Default off (native behavior). Когда on — `openHUD()` для `cutAndReplace` reason устанавливает `itemIndex = 1` если `items.count > 1`.

Принцип `native + choice`.

---

## Версия 0.3.0 — applied 2026-05-26

**Применено** (волна iteration 2, часть 2):

- #4 — Multi-provider AI Registry: новый `AIProviderRegistry` singleton + `ConfiguredProvider` codable + 10 provider kinds (Anthropic, OpenAI, Gemini, Grok, Mistral, DeepSeek, Ollama, LM Studio, llama.cpp, Custom). Unified `OpenAICompatibleProvider` для OpenAI-схожих API, `AnthropicProvider` и `GeminiProvider` со своими схемами. Миграция `providers.json` v1→v2. Settings AI tab перевёрстан с list of providers + per-provider edit sheet + Test connection.
- #4 — Keychain `APIKeyStorage` через `kSecClassGenericPassword` с поддержкой `kSecAttrSynchronizable` (включается в #11 iCloud sync позже).
- #9 — `RichTextHelpers.swift`: `attributedStringToMarkdown`, `markdownToAttributedString` (native `NSAttributedString(markdown:)`), `attributedStringToHTML`. AI `preserveRichFormatting` через MD round-trip — `translate (rich)` и `fix grammar (rich)` сохраняют bold/italic/headings/links. `Rich → HTML` engine.
- #10 — `attributedStringToWiki` (MediaWiki синтаксис) + `Rich → Wiki markup` engine. Default translate prompt теперь Spanish ↔ English (вместо RU ↔ EN).
- #8 partial — Provider badge в HUD action chips: `[Claude]` оранжевый, `[GPT]` зелёный, `[Gemini]` синий, `[Ollama]` серый, etc. + `Paste as text` engine (clean + trim комбо).

**HUD bug fixes (по результатам тестинга 0.2.0):**

- HUD corner radius клипал начало строк в preview pane — добавлены internal `.padding(.horizontal, 6)` для всех semantic types content.
- Content meta row (word count / image size / etc.) перенесена из-под header **в правую колонку content area, прямо над preview pane** — семантически правильное место.

**Отложено до 0.4.0** (большой UI refactor + engine architecture):

- #5 — Settings content tabs: 2-колоночная вёрстка + drag-reorder + Paste as is locked
- #6 — Unified Action Editor sheet (built-in и AI используют один и тот же sheet)
- #7 — Action Engine architecture — algorithm как переменный компонент, `CustomActionDescriptor` с `engineID`
- #8 — Curated default-enabled subset + PalettePicker для остальных engines

---

## Версия 0.2.0 — applied 2026-05-26

**Применено** (волна iteration 2):

- #1 — `ilya000` GitHub handle, убран /issues link
- #2 — Custom About window (`AboutWindow.swift`, 560×500, NSWindowController + SwiftUI)
- #3 — Settings → General → "Launch DrPaste on login" placeholder (disabled, coming soon)
- #11 — Settings → General → iCloud sync placeholder + "Include API keys via iCloud Keychain" sub-toggle (disabled, coming soon)
- #12 — HudPanel.applyRoundedCorners в layoutIfNeeded + setFrame + recursive subview layers, `cornerCurve = .continuous`
- #13 — Thumbnail (600 pt max) для image clipboard items в PreviewSynthesizer.imageRelative + image metadata (width/height/fileSize/format) в ClipboardItem + SwiftUI Image with frame constraints в HUD ImagePreview
- #14 — Backspace в HUD → `hotkeyEngineDidDeleteFocused` (в EventTap + GlobalMonitor + local key monitor для Limited Mode), store.remove + cursor reposition + `delete` sound cue (system fallback "Bottle"). Без undo (сознательное решение). Footer legend обновлён: `⌫ delete`
- #15 — Компактный header в одну строку (icon 16pt · name · count · source · engine · ×), Close button SF Symbol `xmark.circle.fill` (always visible, mouse-route safety net), Content meta row с lazy async compute через `ContentMetaCache` (новый файл, in-memory cache, budget time 50 ms, для большого text — sampling-based approximation)
- #16 — `PasteSimulator.postShortcut` теперь приподнимает физический ⌥ перед synthetic ⌘X/⌘V/⌘C (правильный modifier state) + все наши synthetic events помечены `DrPasteSyntheticMarker` (`.eventSourceUserData`), EventTap фильтрует свои события (разрыв recursion). `pollClipboardChangeThenOpenHUD` — event-driven verification cut с timeout 250 ms (вместо fixed 80 ms heuristic). HUD visibility verification через 80 ms с retry.

**Отложено до 0.3.0** (большая архитектурная волна — engine architecture + multi-provider AI + Settings refactor):

- #4 — Multi-provider AI: cloud (OpenAI, Gemini, Grok, Mistral, DeepSeek) + local (Ollama, LM Studio, llama.cpp, custom) + Keychain
- #5 — Settings content tabs: 2-колоночная вёрстка + drag-reorder + Paste as is locked
- #6 — Unified Action Editor sheet (built-in и AI используют один и тот же sheet)
- #7 — Action Engine dropdown — algorithm как переменный компонент, `CustomActionDescriptor` с `engineID`
- #8 — Curated default actions + palette для остальных + provider-aware naming (`[Claude]` badge)
- #9 — Rich Text: real RTF sample + rich-preserving Result pane + MD round-trip AI translate/fix
- #10 — Полная курация default-наборов по всем content tabs + Wiki markup engine + Spanish как default translate target

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

---

# Итерация 2

Правки накапливаются здесь и применяются волной после обсуждения. Нумерация независимая от итерации 1.

---

## Правка №1 (iteration 2) — About window: корректный GitHub handle, убрать несуществующий /issues

**Статус:** запланирована. Маленькая правка, ~10 строк.

**Затрагивает:** `AppBrand.swift` (`aboutCredits` NSAttributedString), опционально `BACKLOG.md` / `README.md` если в них встречаются те же ссылки.

### Проблема

В About окне сейчас:

```
Source code: https://github.com/iLya-Os/DrPaste
Support: https://github.com/iLya-Os/DrPaste/issues
```

Две ошибки:

1. **Неправильный handle.** Мой GitHub username — `ilya000` (а не `iLya-Os`, который я указал в copyright/license — это nickname для авторских ярлыков, не GitHub login).
2. **Раздела Issues нет.** Репозиторий не имеет включённого Issues tab, ссылка ведёт в никуда.

### Что меняем

В `AppBrand.aboutCredits`:

```swift
// БЫЛО:
body.append(NSAttributedString(string: """
Copyright © 2026 iLya Os.
Licensed under GNU GPL v3.0-or-later with attribution requirement.

Source code: https://github.com/iLya-Os/DrPaste
Support: https://github.com/iLya-Os/DrPaste/issues

"""))

// СТАЛО:
body.append(NSAttributedString(string: """
Copyright © 2026 iLya Os.
Licensed under GNU GPL v3.0-or-later with attribution requirement.

Source code: https://github.com/ilya000/DrPaste

"""))
```

Изменения:
- `iLya-Os` → `ilya000` в URL
- Строка с `Support: …/issues` удаляется целиком

Copyright строка остаётся `iLya Os` (это nickname для атрибуции, не GitHub login — два разных идентификатора, оба корректны).

### Проверить заодно

При применении правки прогрепать репозиторий на `iLya-Os` и `/issues` — если те же ссылки встречаются в `README.md`, `LICENSE`, `BACKLOG.md` или комментариях в коде, поправить там же одной волной. Особенно важно в `README.md` (увидят первым посетители репо).

### Что не меняется

- Copyright `iLya Os` остаётся как есть — это authoring nickname.
- License-секция `Licensed under GNU GPL v3.0-or-later with attribution requirement.` — без изменений.
- Acknowledgements block (Flycut/Maccy/Paste/Raycast, AppKit/SwiftUI/Core Image/Vision/Carbon) — без изменений.

### Когда появится Issues

Если/когда я открою Issues tab — добавим обратно отдельной правкой. Сейчас лучше не показывать broken link, чем "пусть будет".

---

## Правка №2 (iteration 2) — Custom About window: шире, с воздухом и полями

**Статус:** запланирована. Средняя правка, ~120–180 строк (новый файл `AboutWindow.swift` + точка вызова в `main.swift`).

**Затрагивает:** новый `AboutWindow.swift` (NSWindowController + SwiftUI hosting), `main.swift` (`showAbout()` теперь открывает наше окно вместо `NSApp.orderFrontStandardAboutPanel`), `AppBrand.swift` (структурированные поля для About вместо одной NSAttributedString, чтобы было удобнее верстать в SwiftUI).

### Проблема

Сейчас About открывается через `NSApp.orderFrontStandardAboutPanel(options:)`. У Apple-овской панели **фиксированная ширина** (~360–380 pt) и **зажатые поля** — текст идёт впритык к границам окна, многострочные credits переносятся узкой колонкой, читается как сжатый паспорт. Acknowledgements block с inspirations и frameworks внутри стандартной панели выглядит «куцо» и не передаёт качество продукта.

`orderFrontStandardAboutPanel` НЕ позволяет:
- задать ширину окна
- задать padding/insets вокруг credits
- управлять выравниванием
- использовать богатый layout (иконка слева большая, текст справа структурированный)

Опции которые есть (`.credits`, `.applicationIcon`, `.applicationName`, `.applicationVersion`) — только контент, не верстка.

### Решение — собственное About окно

Простое NSWindow с фиксированным размером и SwiftUI content. Не часть Settings (та правка отдельная — Backlog #8 итерации 1, уже сделана), а самостоятельное модальное-style окно как у Sketch / Linear / Raycast — компактное, но с воздухом.

### Целевая верстка

```
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│                                                                │
│     ┌──────┐    DrPaste                                        │
│     │  Dr  │    Press-and-hold clipboard, designed as the      │
│     │      │    natural extension of the Paste gesture.        │
│     └──────┘    Version 0.1.0                                  │
│                                                                │
│    ──────────────────────────────────────────────────────      │
│                                                                │
│    Copyright © 2026 iLya Os.                                   │
│    Licensed under GNU GPL v3.0-or-later                        │
│    with attribution requirement.                               │
│                                                                │
│    Source code:  github.com/ilya000/DrPaste                    │
│                                                                │
│    ──────────────────────────────────────────────────────      │
│                                                                │
│    Acknowledgements                                            │
│                                                                │
│    DrPaste's design is inspired by Flycut, Maccy, Paste,       │
│    and Raycast — open clipboard utilities that paved the way   │
│    for keyboard-first paste UX on macOS.                       │
│                                                                │
│    Built on Apple's AppKit, SwiftUI, Core Image, Vision,       │
│    and Carbon HIToolbox.                                       │
│                                                                │
│    Thanks to the open-source community.                        │
│                                                                │
│                                                                │
└────────────────────────────────────────────────────────────────┘
        (фиксированная ширина 560 pt, высота ~ 500 pt)
```

Ключевые параметры:

- **Ширина окна:** 560 pt (против ~370 у standard panel) — комфортно читается строка ≈ 65 символов.
- **Высота:** ~500 pt, фиксированная (не resizable).
- **Внутренний padding:** 32 pt со всех сторон (стандартный «комфортный» SwiftUI inset).
- **Иконка:** 96×96 pt слева, выровнена по верху первого текстового блока.
- **Заголовок DrPaste:** SF Pro Display 24 pt semibold.
- **Tagline под заголовком:** secondaryLabelColor, 12 pt regular.
- **Version:** tertiaryLabelColor, 11 pt monospaced — снизу tagline.
- **Divider'ы:** standard `Divider()` SwiftUI, между секциями ровно по 24 pt сверху/снизу.
- **Раздел Acknowledgements:** заголовок 13 pt semibold, текст 12 pt regular с line spacing 4 pt для воздуха.
- **GitHub link:** clickable, accentColor, открывается через `NSWorkspace.shared.open(...)`.
- **Фон:** default `Color(NSColor.windowBackgroundColor)` — система сама даст white/dark в зависимости от appearance. Окно НЕ vibrant/HUD-style — это standard window.

### Поведение окна

- **Window style:** `[.titled, .closable]` — без resize, без minimize, без zoom (одинокая красная кнопка, как у настоящего About).
- **Title bar:** `titlebarAppearsTransparent = true`, `titleVisibility = .hidden` — title bar становится «слитым» с фоном, остаётся только закрывашка слева.
- **Movable:** да, `isMovableByWindowBackground = true` — можно таскать за любое место.
- **Center on first show:** да. На повторных открытиях — на позиции последнего открытия (window restoration через `NSWindowController` дефолтно).
- **Single instance:** второй вызов showAbout приносит существующее окно вперёд (`makeKeyAndOrderFront`), а не открывает второе.
- **Closable Esc:** добавить keyDown handler — Esc закрывает окно.

### Реализация

**`AboutWindow.swift`:**

```swift
import SwiftUI
import AppKit

final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        let hosting = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 560, height: 500))
        window.center()
        window.title = "About \(AppBrand.name)"
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        if window?.isVisible == false || window == nil {
            window?.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header: icon + title + tagline + version
            HStack(alignment: .top, spacing: 20) {
                Image(nsImage: AppBrand.nsIcon)
                    .resizable()
                    .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppBrand.name)
                        .font(.system(size: 24, weight: .semibold, design: .default))
                    Text(AppBrand.tagline)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Version \(AppBrand.version)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }

            Divider().padding(.vertical, 24)

            // Copyright + license + source
            VStack(alignment: .leading, spacing: 8) {
                Text("Copyright © 2026 iLya Os.")
                Text("Licensed under GNU GPL v3.0-or-later with attribution requirement.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("Source code:")
                        .foregroundStyle(.secondary)
                    Link("github.com/ilya000/DrPaste",
                         destination: URL(string: "https://github.com/ilya000/DrPaste")!)
                }
                .padding(.top, 4)
            }
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 24)

            // Acknowledgements
            VStack(alignment: .leading, spacing: 12) {
                Text("Acknowledgements")
                    .font(.system(size: 13, weight: .semibold))

                Text("DrPaste's design is inspired by Flycut, Maccy, Paste, and Raycast — open clipboard utilities that paved the way for keyboard-first paste UX on macOS.")
                    .foregroundStyle(.secondary)

                Text("Built on Apple's AppKit, SwiftUI, Core Image, Vision, and Carbon HIToolbox.")
                    .foregroundStyle(.secondary)

                Text("Thanks to the open-source community.")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(width: 560, height: 500, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
```

**`AppBrand.swift` — добавить `tagline`:**

```swift
static let tagline = "Press-and-hold clipboard, designed as the natural extension of the Paste gesture."
```

(можно немного отполировать — это draft)

**`main.swift.showAbout()`:**

```swift
// БЫЛО:
@objc private func showAbout() {
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: AppBrand.name,
        .applicationVersion: AppBrand.version,
        .credits: AppBrand.aboutCredits,
        .applicationIcon: AppBrand.nsIcon
    ])
}

// СТАЛО:
@objc private func showAbout() {
    AboutWindowController.shared.show()
}
```

`AppBrand.aboutCredits` остаётся для совместимости / возможного будущего использования, но из showAbout больше не дергается.

### Что не делается в этой правке

- **Богатая визуализация инструментов** (логотипы Apple frameworks, badges Flycut/Maccy/Paste/Raycast) — это превратится в дизайн-проект сам по себе. Текст plain, чистый — этого достаточно.
- **Анимация появления** (fade-in/scale) — стандартное NSWindow открытие.
- **Build number в version** — пока только `0.1.0`, без build. Когда появится CI с автоматическим build counter — добавим `Version 0.1.0 (build 42)`.
- **Localization** — текст на английском, как и весь UI пока. Локализация — отдельная правка после v1.
- **Embedded license text** — кнопка «View License» открывающая GPL текст. Излишне, license file есть в репо и в LICENSE рядом с executable.

### Зависимости

- Опирается на правку №1 итерации 2 (`ilya000` handle, убрать /issues) — финальные строки About должны быть уже исправленными. Логично применять обе правки одной волной.
- Не имеет дальнейших зависимостей в итерации 2.

### Размер изменений

- Новый файл `AboutWindow.swift`: ~120 строк
- `AppBrand.swift`: +3 строки (tagline) + правки в aboutCredits (правка №1)
- `main.swift`: 1 строка изменена в showAbout
- Build & run: должно компилироваться без warnings

---

## Правка №3 (iteration 2) — Settings → General: Launch DrPaste on login (placeholder)

**Статус:** запланирована. Маленькая правка, ~15 строк.

**Затрагивает:** `SettingsWindow.swift` (General tab — добавить Toggle в существующий section).

### Что добавляем

В Settings → General tab, в верхней части, новая Toggle-строка:

```
☐ Launch DrPaste on login        (disabled — coming soon)
```

### Почему серым

Полноценная реализация требует регистрации Login Item через `SMAppService.mainApp.register()` (macOS 13+), отдельный helper executable не нужен с современным API, но всё равно надо:

1. Подписать app codesign'ом (login items без подписи macOS блокирует на 14/15)
2. Добавить usage description ключ в Info.plist
3. Зарегистрировать observer на изменения статуса (`SMAppService.Status`)
4. Корректно обрабатывать пользовательский revoke через System Settings → Login Items

Для DrPaste-as-SwiftPM-executable без подписи это пока не работает без танцев. Поэтому **UI ставим сейчас** (чтобы пользователь видел что фича в планах и не искал её в других местах), а **функционал — отдельной правкой** когда дойдём до code signing / distribution flow.

### Реализация

В `SettingsWindow.swift` в General tab (внутри VStack настроек):

```swift
Toggle("Launch DrPaste on login", isOn: .constant(false))
    .disabled(true)
    .help("Coming soon — will be available once DrPaste ships signed.")
```

`isOn: .constant(false)` — пока не bind'имся к реальному state, всегда false.
`.disabled(true)` — серый, не кликабельный.
`.help(...)` — tooltip при hover, объясняющий почему серый.

### Опционально — visual hint что это placeholder

Чтобы пользователь не подумал что приложение «забыло» включить toggle, можно добавить inline subtle подпись:

```swift
HStack {
    Toggle("Launch DrPaste on login", isOn: .constant(false))
        .disabled(true)
    Text("(coming soon)")
        .font(.caption)
        .foregroundStyle(.tertiary)
}
```

«(coming soon)» в тёртичной серой 11 pt — даёт явный сигнал «это не баг, это план».

### Когда переходить к реальной реализации

Отдельной правкой когда:
- DrPaste получит code signing (Developer ID Application или Apple Distribution)
- Появится распространяемый `.app` bundle (сейчас raw executable)

Тогда правка станет: импорт `ServiceManagement`, реальный binding к `SMAppService.mainApp.status`, register/unregister handlers, error handling для `SMAppServiceErrorDomain` cases.

### Расширение этой правки в будущем

Аналогично «(coming soon)» placeholder'ы могут появиться для других ещё не реализованных pref'ов:

- Hotkey rebinding UI (требует `sindresorhus/KeyboardShortcuts` package)
- Cloud sync via iCloud (требует CloudKit setup)
- Update channel (stable / beta) — требует Sparkle integration

Договоримся: placeholder-toggle всегда disabled + помечен «(coming soon)», чтобы roadmap был виден в самом продукте, а не только в README.

---

## Правка №4 (iteration 2) — Multi-provider AI: cloud + local providers в Settings

**Статус:** запланирована. Большая правка ~350–500 строк (расширение `AIProvider.swift` + новый UI в `SettingsWindow.swift` → AI tab + миграция формата `providers.json`).

**Затрагивает:** `AIProvider.swift` (новый `AIProviderRegistry`, протокол + реализации для всех провайдеров, унифицированный chat/completions API), `SettingsWindow.swift` (AI Providers tab — полная пересборка), `Actions.swift` (`AIAction` берёт provider по ID из registry вместо одного hardcoded), `ActionConfig.swift` (CustomAIDescriptor.providerID уже есть — больше не hardcoded "anthropic"), новый `providers.json` schema с миграцией.

### Цель

Сейчас в DrPaste hardcoded один провайдер — `AnthropicProvider`. Пользователь хочет (а) выбирать между cloud-провайдерами по предпочтению и цене, (б) использовать **локальные модели** (Ollama, LM Studio) — это privacy critical: clipboard содержит sensitive данные (пароли, ключи, личные документы), некоторые пользователи принципиально не хотят чтобы они уходили в облако.

После правки: пользователь может одновременно иметь сконфигурированные несколько провайдеров и в каждом custom AI action указывать какой использовать.

### Поддерживаемые провайдеры (production-минимум)

**Cloud:**

| Provider | API | Authentication | Models |
|---|---|---|---|
| **Anthropic** ✓ (есть) | `https://api.anthropic.com/v1/messages` | `x-api-key` header | claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5 |
| **OpenAI** | `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer` | gpt-5, gpt-5-mini, gpt-4.1, gpt-4o |
| **Google Gemini** | `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` | `?key={apiKey}` query param | gemini-2.5-pro, gemini-2.5-flash, gemini-2.0-flash |
| **xAI Grok** | `https://api.x.ai/v1/chat/completions` | `Authorization: Bearer` | grok-4, grok-3 |
| **Mistral** | `https://api.mistral.ai/v1/chat/completions` | `Authorization: Bearer` | mistral-large, codestral |
| **DeepSeek** | `https://api.deepseek.com/chat/completions` | `Authorization: Bearer` | deepseek-chat, deepseek-reasoner |

**Local:**

| Provider | API | Authentication | Default URL |
|---|---|---|---|
| **Ollama** | OpenAI-compatible на `/v1/chat/completions` | нет | `http://localhost:11434` |
| **LM Studio** | OpenAI-compatible | нет (по умолчанию) | `http://localhost:1234` |
| **llama.cpp server** | OpenAI-compatible | нет | `http://localhost:8080` |

**Generic custom:**

| Provider | API | |
|---|---|---|
| **Custom OpenAI-compatible** | OpenAI-compatible на user-specified base URL + optional Bearer token | для прочих local runners или enterprise-proxy endpoints |

### Архитектурный сдвиг — Registry

```swift
// AIProvider.swift

protocol AIProvider {
    var id: String { get }
    var displayName: String { get }
    var requiresAPIKey: Bool { get }
    var requiresBaseURL: Bool { get }      // true для Ollama / custom
    var availableModels: [String] { get }  // hint для UI dropdown (можно расширять)
    var defaultModel: String { get }

    func complete(prompt: String, system: String?, model: String) async throws -> String
}

enum AIProviderError: Error {
    case missingAPIKey
    case missingBaseURL
    case modelUnavailable(String)
    case http(status: Int, body: String)
    case decodingFailed(String)
    case networkUnreachable
    case rateLimited(retryAfter: TimeInterval?)
}

final class AIProviderRegistry: ObservableObject {
    static let shared = AIProviderRegistry()
    @Published private(set) var configured: [ConfiguredProvider] = []
    @Published var defaultProviderID: String?

    func provider(id: String) -> AIProvider? { ... }
    func configure(_ config: ProviderConfig) { ... }
    func remove(id: String) { ... }
    func test(id: String) async -> Result<String, AIProviderError> { ... }
}

struct ProviderConfig: Codable, Identifiable {
    var id: String                  // например "openai" / "ollama" / "custom-1"
    var kind: ProviderKind          // .anthropic / .openai / .gemini / .grok / .mistral / .deepseek / .ollama / .lmstudio / .llamaCpp / .custom
    var displayName: String         // overridable, default по kind
    var apiKey: String?             // nil для local
    var baseURL: String?            // только для local / custom
    var model: String               // выбранная модель
    var enabled: Bool
}
```

### Implementation реализаций

**Common OpenAI-compatible client** — Ollama, LM Studio, llama.cpp, OpenAI, Grok, Mistral, DeepSeek, custom — все используют один HTTP-клиент со схемой `POST /v1/chat/completions` с body `{"model": "...", "messages": [...], ...}`. Различия только в:
- base URL
- Authorization header (Bearer vs none)
- response shape (минимальные различия в `choices[0].message.content`)

Реализуем `OpenAICompatibleProvider` с параметрами baseURL / authHeader / defaultModel, и оборачиваем им большинство провайдеров.

**Anthropic** уже отдельная реализация — `/v1/messages` со своей схемой `messages` и `system`. Остаётся.

**Gemini** — отдельная реализация (`/v1beta/models/{model}:generateContent` с другим body shape — `contents` вместо `messages`). Отдельный класс.

```swift
final class AnthropicProvider: AIProvider { ... }  // existing
final class OpenAICompatibleProvider: AIProvider { ... }  // unified для большинства
final class GeminiProvider: AIProvider { ... }  // отдельный
```

`OpenAICompatibleProvider` конфигурируется при создании:

```swift
extension OpenAICompatibleProvider {
    static func openAI(apiKey: String, model: String) -> Self { ... }
    static func grok(apiKey: String, model: String) -> Self { ... }
    static func mistral(apiKey: String, model: String) -> Self { ... }
    static func deepseek(apiKey: String, model: String) -> Self { ... }
    static func ollama(baseURL: String, model: String) -> Self { ... }
    static func lmStudio(baseURL: String, model: String) -> Self { ... }
    static func llamaCpp(baseURL: String, model: String) -> Self { ... }
    static func custom(baseURL: String, apiKey: String?, model: String) -> Self { ... }
}
```

### UI — Settings → AI Providers tab

```
┌─ AI Providers ──────────────────────────────────────────────┐
│                                                             │
│ Default provider: [Anthropic Claude ▼]                      │
│ Used for all custom AI actions unless overridden per action.│
│                                                             │
│ ─────────────────────────────────────────────────────────   │
│                                                             │
│ Cloud providers                                             │
│                                                             │
│  Anthropic Claude              ●  configured       [Edit]   │
│  OpenAI GPT                    ○  not configured   [Setup]  │
│  Google Gemini                 ○  not configured   [Setup]  │
│  xAI Grok                      ○  not configured   [Setup]  │
│  Mistral                       ○  not configured   [Setup]  │
│  DeepSeek                      ○  not configured   [Setup]  │
│                                                             │
│ Local providers                                             │
│                                                             │
│  Ollama                        ●  configured       [Edit]   │
│  LM Studio                     ○  not configured   [Setup]  │
│  llama.cpp server              ○  not configured   [Setup]  │
│                                                             │
│ Custom                                                      │
│                                                             │
│  [+ Add custom OpenAI-compatible endpoint…]                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Click [Edit] / [Setup]** — модальное sheet с полями:

Для cloud-провайдера (Anthropic / OpenAI / Gemini / Grok / Mistral / DeepSeek):

```
┌─ OpenAI ────────────────────────────────────────────────────┐
│                                                             │
│ API Key:    [ sk-...___________________________ ]  [👁]     │
│             Get one at platform.openai.com/api-keys         │
│                                                             │
│ Model:      [ gpt-5-mini  ▼ ]                               │
│             Custom: [____________________]                  │
│                                                             │
│ [Test connection]    ●  Connected (gpt-5-mini, 245 ms)      │
│                                                             │
│                            [Cancel]    [Save]               │
└─────────────────────────────────────────────────────────────┘
```

Для local-провайдера (Ollama / LM Studio / llama.cpp):

```
┌─ Ollama ────────────────────────────────────────────────────┐
│                                                             │
│ Base URL:   [ http://localhost:11434                ]       │
│             [Detect running instance]                       │
│                                                             │
│ Model:      [ llama3.2:latest        ▼ ]                    │
│             ↻ Refresh list from server                      │
│                                                             │
│ [Test connection]    ●  Connected — 12 models available     │
│                                                             │
│                            [Cancel]    [Save]               │
└─────────────────────────────────────────────────────────────┘
```

Особенности local UI:

- **«Detect running instance»** — Bonjour scan / port probe на стандартные порты (11434 Ollama, 1234 LM Studio, 8080 llama.cpp). Если найдено — заполняет Base URL автоматически.
- **«Refresh model list from server»** — Ollama имеет endpoint `GET /api/tags` со списком установленных моделей, LM Studio имеет `GET /v1/models`, llama.cpp пока тоже OpenAI-compatible `/v1/models`. Заполняет dropdown реально установленными моделями.
- **API key hidden behind 👁 toggle** — стандартный pattern для password fields. Хранится через SecureField в SwiftUI.

Для custom OpenAI-compatible:

```
┌─ Custom OpenAI-compatible endpoint ─────────────────────────┐
│                                                             │
│ Display name: [ My company proxy            ]               │
│                                                             │
│ Base URL:     [ https://ai-proxy.acme.com/v1     ]          │
│                                                             │
│ API Key:      [ ___________________________ ]  [👁]         │
│               (leave empty if no auth required)             │
│                                                             │
│ Model:        [ acme-llama-70b                   ]          │
│                                                             │
│ [Test connection]                                           │
│                                                             │
│                            [Cancel]    [Save]               │
└─────────────────────────────────────────────────────────────┘
```

### Test connection

Каждый sheet имеет **[Test connection]** кнопку:

```swift
func test(_ provider: AIProvider) async -> Result<String, AIProviderError> {
    let start = Date()
    do {
        let _ = try await provider.complete(
            prompt: "Reply with the single word OK.",
            system: nil,
            model: provider.defaultModel
        )
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        return .success("Connected (\(elapsed) ms)")
    } catch {
        return .failure(mapToProviderError(error))
    }
}
```

При успехе — зелёная лампочка + время отклика. При failure — внятная error message:
- `missingAPIKey` → «API key required»
- `http(401)` → «Invalid API key»
- `http(404)` → «Endpoint not found — check base URL»
- `networkUnreachable` → «Could not reach server»
- `modelUnavailable` → «Model "..." not available on this provider»
- `rateLimited(retryAfter: t)` → «Rate limited (retry in \(t) s)»

Это критически важно — без Test пользователь не понимает почему AI action возвращает `.failed`.

### Per-action provider override

В custom AI action editor (Backlog #8 итерации 1 уже сделан) есть поле «Provider:». Сейчас оно показывает только `anthropic`. После правки:

```
Provider:  [Default (Anthropic Claude) ▼]
           ├─ Default (Anthropic Claude)
           ├─ Anthropic Claude
           ├─ OpenAI GPT
           ├─ Ollama (llama3.2:latest)
           └─ ...
```

«Default» использует `AIProviderRegistry.shared.defaultProviderID`. Конкретный provider — overrides default. Если выбранный provider удалён — fallback на default + warning в action list.

### Privacy nudge

Когда пользователь конфигурирует cloud-провайдер и в action queue есть actions помеченные `.privacySensitive = true` (TODO будущий tag для actions работающих с password fields, IBAN, credit cards) — UI показывает inline notice:

```
ⓘ "Translate" will send clipboard content to Anthropic Claude API.
  For private content, configure a local provider (Ollama, LM Studio).
```

Не блокирующий, информационный. Хорошо для education.

### Миграция `providers.json`

**Старый формат:**
```json
{
  "anthropic": {
    "apiKey": "sk-...",
    "model": "claude-sonnet-4-6"
  }
}
```

**Новый формат:**
```json
{
  "version": 2,
  "defaultProviderID": "anthropic",
  "providers": [
    {
      "id": "anthropic",
      "kind": "anthropic",
      "displayName": "Anthropic Claude",
      "apiKey": "sk-...",
      "model": "claude-sonnet-4-6",
      "enabled": true
    },
    {
      "id": "ollama",
      "kind": "ollama",
      "displayName": "Ollama",
      "baseURL": "http://localhost:11434",
      "model": "llama3.2:latest",
      "enabled": true
    }
  ]
}
```

Миграция: при load если `version` отсутствует — это v1, читаем старый формат, оборачиваем в один `ProviderConfig{kind: .anthropic}`, сохраняем как v2. Прозрачно для пользователя.

### Keychain vs plain text для API keys

Текущая реализация хранит API key в plain text JSON в Application Support. Это **не идеально** для security. Правка опционально включает **переход на macOS Keychain**:

```swift
import Security

enum APIKeyStorage {
    static func save(_ key: String, for providerID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ilya000.DrPaste.provider",
            kSecAttrAccount as String: providerID,
            kSecValueData as String: key.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(for providerID: String) -> String? {
        var item: AnyObject?
        let query: [String: Any] = [ ... kSecMatchLimitOne, kSecReturnData: true]
        SecItemCopyMatching(query as CFDictionary, &item)
        return (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }
}
```

В `ProviderConfig` хранится только `id` ключа в keychain, не сам ключ. Export config теперь не содержит ключей (что и так было в плане Backlog #8 итерации 1 — «API keys в export НЕ включаются»).

**Решение:** да, переходим на Keychain в этой же правке. Это естественный момент пока меняем формат providers.json.

### Что не входит

- **Streaming responses** — все провайдеры поддерживают streaming через SSE, но текущая HUD-архитектура показывает only final result. Streaming можно добавить отдельной правкой когда HUD получит «typing» preview.
- **Multi-modal** (vision models — image input для GPT-4o/Claude/Gemini) — пока только text in / text out. Для image actions OCR делается локально через Vision (Backlog #3 итерации 1, уже есть).
- **Embeddings / RAG** — не нужно для clipboard transformations.
- **Function calling / tools** — не нужно.
- **Cost tracking / token counters** — out of scope для v1. Полезно, но отдельной правкой.

### Зависимости

- Опирается на **Backlog #8 итерации 1** (уже сделан — Settings UI, `ActionConfig.customAI[].providerID` уже есть в data model). Правка эта расширяет существующий хук.
- Опирается на **Backlog #2 итерации 1** (Visible failures, уже сделан) — для отображения provider config errors.

### Размер изменений

- `AIProvider.swift`: +250 строк (новые провайдеры, registry)
- `SettingsWindow.swift` → AI Providers tab: +200 строк (новый список + sheet editors)
- `Actions.swift`: ~10 строк (AIAction берёт provider по ID из registry)
- Новый `APIKeyStorage.swift`: ~40 строк
- Миграция `providers.json` v1 → v2: ~30 строк в `AIProvider.swift`

Итого: ~530 строк.

---

## Правка №5 (iteration 2) — Settings content tabs: 2-колоночная вёрстка + drag-reorder + rename actions

**Статус:** запланирована. Большая правка ~300–400 строк (вёрстка + drag state machine + rename UX + persistence для порядка и переименований).

**Затрагивает:** `SettingsWindow.swift` (полная пересборка `ContentTypeTab` view), `ActionConfig.swift` (новые поля `actionOrder`, `customTitles` в config), `ActionRegistry` (учитывать пользовательский порядок при отдаче applicable actions), `Actions.swift` (мелкая правка `title` getter — overridable из config).

### Проблема

Сейчас в каждом content-type tab (Plain text / URL / Image / …) **три блока друг под другом по вертикали**:

```
┌─ Plain text ────────────────────────┐
│ Sample input:                       │  <- ~120 pt высоты
│ [ textarea ]                        │
│ [Reset to default sample]           │
│                                     │
│ Result:                             │  <- ~120 pt высоты
│ [ output preview ]                  │
│                                     │
│ Actions:                            │  <- 200+ pt, скроллится
│ ☑ Paste as is                [Run] │
│ ☑ Fix keyboard layout        [Run] │
│ ☑ UPPERCASE                  [Run] │
│ ... (15–20 actions per type)        │
└─────────────────────────────────────┘
```

Проблема: Actions list занимает существенно больше места чем Sample + Result, окно становится узким и длинным, скроллится. При этом Sample и Result часто компактные (одна строка URL, одно слово в результате) — впустую тратят horizontal space.

### Новая 2-колоночная вёрстка

```
┌─ Plain text ───────────────────────────────────────────────────────┐
│ ┌─ Sample input ────────────────┐  ┌─ Actions ───────────────────┐ │
│ │ [ textarea ~ 200 pt high ]    │  │ ⋮⋮ ☑ Paste as is    [Run]  │ │  <- "Paste as is" locked (no drag handle / no rename)
│ │                               │  │ ⋮⋮ ☑ Fix layout 🖉 [Run]   │ │  <- ⋮⋮ = drag handle, 🖉 = rename button
│ │                               │  │ ⋮⋮ ☑ UPPERCASE  🖉 [Run]   │ │
│ │ [Reset to default sample]     │  │ ⋮⋮ ☑ lowercase  🖉 [Run]   │ │
│ └───────────────────────────────┘  │ ⋮⋮ ☑ Title Case 🖉 [Run]   │ │
│                                    │ ⋮⋮ ☑ Trim       🖉 [Run]   │ │
│ ┌─ Result ──────────────────────┐  │ ⋮⋮ ☑ Sort lines 🖉 [Run]   │ │
│ │ [ output preview ~ 200 pt ]   │  │ ⋮⋮ ☑ Slugify    🖉 [Run]   │ │
│ │                               │  │ ─ Custom AI ──────────────  │ │
│ │                               │  │ ⋮⋮ ☑ Summarize 🖉🛠 [Run]  │ │  <- 🛠 = edit prompt (для AI)
│ │ (Run any action ...)          │  │ ⋮⋮ ☑ Translate 🖉🛠 [Run]  │ │
│ └───────────────────────────────┘  │ ⋮⋮ ☑ Fix grammar 🖉🛠[Run] │ │
│                                    │ [+ Add custom AI action…]   │ │
│                                    └─────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

Левая колонка: **Sample input** сверху, **Result** снизу. Каждый блок ~ 200 pt высоты, у обоих textarea editable / read-only соответственно. Между ними отступ 16 pt.

Правая колонка: **Actions list**, scrollable, занимает всю высоту правой колонки.

Минимальная ширина окна Settings увеличивается до ~ 880 pt (440 + 440 с paddings). Это норма для tabbed Settings — большинство Apple-приложений и так используют 700–900 pt.

### Drag-to-reorder

Пользователь хватает action за **drag handle** (⋮⋮ — две вертикальные точки, иконка `arrow.up.and.down.and.arrow.left.and.right` либо `line.3.horizontal` слева от toggle) и перетаскивает выше / ниже в списке.

**Правила:**

1. **«Paste as is» (identity action) заблокирован.** Всегда первый, не имеет drag handle, не имеет rename button. Это semantic anchor: «вот оригинал без модификаций». Если пользователь хочет другую default-первую — пусть будет, но identity должен быть identity.

2. **Built-in actions можно тасовать между собой и между AI.** Никакой жёсткой сегрегации built-in / AI. Пользователь может поставить «AI: summarize» вторым, а «UPPERCASE» — куда-то в конец.

3. **Heading «─ Custom AI ──» удаляется.** В новой версии нет визуальной сегрегации — AI actions просто помечаются маленьким значком ✨ слева от названия, чтобы пользователь видел тип. Тип-фильтрация делается уже при первой настройке, не каждый раз в списке.

4. **Drag indicator при перетаскивании** — пустая строка-плейсхолдер с подсвеченной линией показывает куда будет вставлено. Стандартный SwiftUI `.onDrag` / `.onDrop` или AppKit-обёртка через `NSItemProvider`.

5. **Cross-content-type drag не нужен.** Action в Plain text tab нельзя перетащить в URL tab. Это разные filtered lists одной registry; порядок per content type.

### Rename action

Каждый action (кроме Paste as is) имеет **🖉 (pencil) кнопку** между toggle и [Run]. Клик — inline editable:

```
⋮⋮ ☑ [ Fix keyboard layout___________ ]  ✓ ✗   [Run]
        ⓘ default: Fix keyboard layout
```

- Поле становится TextField, текст auto-selected (полностью выделен) для быстрого набора нового
- ✓ Save / ✗ Cancel под полем (или Enter/Esc)
- **Под полем — серая 11 pt подпись с дефолтным названием** — критично для UX, как ты и просил. Пользователь не теряется: видит и что переименовывает (default name), и что вводит (новое title).

**После save** в списке отображается custom title, а на hover — tooltip с дефолтным:

```
⋮⋮ ☑ My Layout Fix  🖉 [Run]
      ↓ hover
      ┌─────────────────────────────┐
      │ Default: Fix keyboard layout │
      │ ID: builtin.layout_repair    │
      └─────────────────────────────┘
```

ID показывается в tooltip — это помогает при export/import и при разборе конфигов вручную.

**Reset to default** — если custom title задан, рядом с pencil появляется маленький ↺ (counterclockwise.arrow) который сбрасывает на default. Когда title == default — этой кнопки нет.

### Что вижу при клике мышью на action

Ты пишешь «при клике мышью должно быть видно дефолтное название» — есть две интерпретации:

**(А) Простой клик по строке** (не на Run/rename/toggle/handle) — раскрывает inline-detail row с full information:

```
⋮⋮ ☑ My Layout Fix                                      [Run]
  ┌──────────────────────────────────────────────────────┐
  │ Default name: Fix keyboard layout                    │
  │ ID:           builtin.layout_repair                  │
  │ Type:         Built-in (local)                       │
  │ Applies to:   Plain text                             │
  │ Description:  Detects wrong keyboard layout and      │
  │               corrects RU↔EN mishits.                │
  │ [Reset to default name]                              │
  └──────────────────────────────────────────────────────┘
```

Повторный клик / клик на другую строку сворачивает.

**(B) Один глобальный info pane снизу справа** — выделенный action показывает свои метаданные в фиксированной зоне. Меньше visual jumps.

Думаю — **вариант А (раскрывающийся inline)** лучше для одного активного UI элемента (rename), но **B менее визуально шумный**. Решим при реализации.

### Action metadata storage

В `ActionConfig`:

```swift
struct ActionConfig: Codable {
    var version: Int = 1
    var enabledFlags: [String: Bool] = [:]

    /// Пользовательский порядок per content type.
    /// Key — ContentTypeID rawValue ("plain", "url", "image", …)
    /// Value — массив action.id в нужном порядке.
    /// Если ключа нет — используется default order (как зарегистрировано в registry).
    /// Если action есть в registry но нет в массиве — добавляется в конец (новый).
    var actionOrder: [String: [String]] = [:]

    /// Custom titles per action ID.
    /// Если ключа нет — используется action.title (default).
    var customTitles: [String: String] = [:]

    var customAI: [CustomAIDescriptor] = []
    var preferences: ActionConfigPreferences = ActionConfigPreferences()
}
```

`ActionRegistry.applicable(for:context:)` теперь:

```swift
func applicable(for item: ClipboardItem, context: ContentContext) -> [ClipboardAction] {
    let typeKey = primaryContentType(context).rawValue   // например "plain"
    let savedOrder = config.actionOrder[typeKey] ?? []
    let allApplicable = actions.filter { isEnabled($0.id) && $0.isApplicable(item: item, context: context) }
    return reorder(allApplicable, by: savedOrder)
}

func displayTitle(for actionID: String, default defaultTitle: String) -> String {
    config.customTitles[actionID] ?? defaultTitle
}
```

В HUD при рендере action title — используем `registry.displayTitle(for: action.id, default: action.title)`. Это гарантирует что переименование видно и в Settings playground, и в реальном HUD.

### Drag-reorder реализация

SwiftUI поддерживает `.onMove(perform:)` для List/ForEach начиная с macOS 11. Но `.onMove` работает в edit mode List'а — для нашего custom-styled списка нужен ручной D&D через `.onDrag { NSItemProvider(...) }` и `.onDrop(of: ..., delegate: ...)`. Стандартный паттерн, ~80 строк кода с custom drop delegate чтобы было плавно.

Для блокировки Paste as is — `.onMove` обработчик проверяет `.first` индекс:

```swift
.onMove { source, destination in
    var newOrder = currentOrder
    let pasteAsIsIdx = newOrder.firstIndex(of: "builtin.identity")
    newOrder.move(fromOffsets: source, toOffset: destination)
    // Если Paste as is сместилось — откатываем
    if newOrder.firstIndex(of: "builtin.identity") != pasteAsIsIdx {
        return  // отказ от перемещения
    }
    config.actionOrder[currentTypeKey] = newOrder
}
```

Альтернатива — `.onDrag { … }` возвращает nil для identity (нельзя начать drag) + `.onDrop` отвергает drops в позицию 0. Чище визуально.

### Edge cases

- **Reset all** в Settings (общая кнопка где-то снизу): сбрасывает `actionOrder` и `customTitles` к пустым словарям. Подтверждение через alert.
- **Import config с другим набором actions** — если incoming config упоминает action.id которого нет в нашем registry — id молча игнорируется (forward compatibility). Если у нас есть action.id которого нет в incoming actionOrder[type] — добавляется в конец (default position).
- **Переименование в пустую строку** — отвергается, восстанавливается предыдущее имя. Минимум 1 символ.
- **Дубликаты имён** — разрешены. Пользователь может назвать два action одинаково; различаются по id под капотом. Не ломает функционал.

### UI размеры и motion

- Settings минимальная ширина: 880 pt (raise с текущих ~620).
- Settings высота: 600 pt минимум, resizable.
- Левая колонка: flexible width, min 360, ideal 440.
- Правая колонка: flexible width, min 360, ideal 440.
- Drag animation: 0.2 s ease-out, легкий tilt 2° на dragged row.
- Inline rename appearing: 0.15 s ease-in-out, textfield автофокус + selectAll().

### Что не входит

- **Группировка / categories actions** (свои фолдеры) — out of scope. Если у пользователя 30 actions в одном tab — линейный список + scroll. Категоризация может прийти позже как opt-in.
- **Keyboard shortcuts per action** — назначить ⌘1, ⌘2, … на отдельные actions для quick-trigger в HUD без navigate. Хорошая идея, но отдельная правка.
- **Action search/filter** — текстовый фильтр сверху списка. Полезно когда actions станет много, но не сейчас.
- **Color/icon customization** — out of scope. Иконки автоматические по action kind / content type.

### Зависимости

- Опирается на **Backlog #8 итерации 1** (Settings + ActionConfig — уже сделан). Эта правка расширяет существующее.
- Не имеет других зависимостей в итерации 2.

### Размер изменений

- `SettingsWindow.swift` → ContentTypeTab: ~250 строк (новый layout + drag delegate + rename inline editor)
- `ActionConfig.swift`: +20 строк (actionOrder, customTitles fields)
- `Actions.swift` / ActionRegistry: ~30 строк (displayTitle, reordered applicable)
- HUD.swift: ~5 строк (использовать displayTitle вместо action.title)

Итого: ~305 строк.

---

## Правка №6 (iteration 2) — Единый Action Editor (отменяет inline rename из правки №5)

**Статус:** запланирована. Заменяет UX-часть правки №5 (inline editable title) на единый модальный sheet. Архитектурно — упрощение, ~150 строк (одно UI место вместо двух).

**Затрагивает:** `SettingsWindow.swift` (новый `ActionEditorSheet` view, удаление inline rename UI, удаление отдельного `AIActionEditor` если был), `ActionConfig.swift` (без изменений data model — поля те же).

### Что не так с правкой №5

В правке №5 я предложил **inline rename** через pencil-кнопку (TextField прямо в строке списка) и **отдельный full editor** для AI actions. Это два разных места для редактирования одного и того же концепта — «настройки конкретного action'а». Несимметрично и плодит UX-стили.

Твоё наблюдение правильное: **edit built-in action и edit custom AI action — это один и тот же диалог**, просто для built-in часть полей read-only / hidden. Делаем единый editor.

### Единый Action Editor sheet

Один SwiftUI sheet `ActionEditorSheet`, открывается из кнопки [Edit] (вместо отдельного 🖉 pencil + отдельного «edit» для AI). Иконка кнопки — `pencil` SF Symbol, label «Edit».

```
┌─ Edit action ──────────────────────────────────────────────┐
│                                                            │
│  Title              [ Fix keyboard layout         ]        │
│                     Default: Fix keyboard layout           │
│                     [↺ Reset to default]                   │
│                                                            │
│  ─────────────────────────────────────────────────────     │
│                                                            │
│  Type               Built-in (local)                       │
│  ID                 builtin.layout_repair                  │
│  Applies to         Plain text, Mixed-script text          │
│  Description        Detects wrong keyboard layout (e.g.    │
│                     RU↔EN mishits) and corrects it.        │
│                                                            │
│  ─────────────────────────────────────────────────────     │
│                                                            │
│  ☑ Enabled                                                 │
│                                                            │
│                                  [Cancel]    [Save]        │
└────────────────────────────────────────────────────────────┘
```

Для AI action — тот же sheet, но дополнительные поля становятся видимыми и editable:

```
┌─ Edit action ──────────────────────────────────────────────┐
│                                                            │
│  Title              [ AI: summarize                 ]      │
│                     Default: AI: summarize                 │
│                     [↺ Reset to default]                   │
│                                                            │
│  ─────────────────────────────────────────────────────     │
│                                                            │
│  Type               AI (cloud)                             │
│  ID                 user.summarize                         │
│                                                            │
│  Provider           [ Anthropic Claude ▼ ]                 │
│                     Override default for this action only. │
│                                                            │
│  Model              [ Use provider default ▼ ]             │
│                     (или sonnet-4-6 / haiku-4-5 / ...)     │
│                                                            │
│  Prompt template                                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Summarize the user's input in 1–3 sentences.         │  │
│  │ Reply with the summary only, no preamble.            │  │
│  │                                                      │  │
│  │ {INPUT} is replaced with clipboard content.          │  │
│  └──────────────────────────────────────────────────────┘  │
│  Variables: {INPUT}, {SOURCE_APP}, {SEMANTIC_KIND}         │
│                                                            │
│  Applies to                                                │
│   [✓] Plain text   [✓] Rich text   [ ] URL   [ ] JSON      │
│   [ ] Code         [ ] Markdown    [ ] Table  [ ] Files    │
│                                                            │
│  ─────────────────────────────────────────────────────     │
│                                                            │
│  ☑ Enabled                                                 │
│                                                            │
│  [🗑 Delete action]            [Cancel]    [Save]          │
└────────────────────────────────────────────────────────────┘
```

### Различия built-in / AI в одном sheet

Поля показываются всегда **в одном и том же visual layout**, но для built-in:

| Поле | Built-in action | Custom AI action |
|---|---|---|
| **Title** | editable | editable |
| **Default name + Reset** | да (если customTitle ≠ default) | да |
| **Type** | read-only label "Built-in (local)" | read-only "AI (cloud)" / "AI (local)" |
| **ID** | read-only label | read-only label |
| **Applies to** | read-only label (фиксировано в коде) | editable checkboxes |
| **Description** | read-only label из bundled metadata | optional editable note |
| **Provider** | скрыто | editable dropdown |
| **Model** | скрыто | editable dropdown |
| **Prompt template** | скрыто | editable multiline textarea |
| **Delete action** | скрыто (built-in нельзя удалить, только disable) | red destructive button |
| **Enabled** | toggle | toggle |

Условный рендеринг через `if action.isAIAction { ... }`. Поля группируются в SwiftUI `Section`'ах с заголовками для визуальной структуры, но layout единообразный для обоих типов.

### «Add custom AI action…»

Этот же sheet открывается с пустыми полями + изменённым title окна → «New AI action». Тип фиксирован как AI (toggle между built-in и AI создать невозможно — built-ins создаются только в коде). После [Save] — добавляется новый `CustomAIDescriptor` в `ActionConfig.customAI`.

### Bundled metadata для built-in actions

Для красивого «Description» поля нужны заранее заготовленные описания всех built-in actions. Делаем bundled JSON:

```
Sources/DrPaste/Resources/Actions/builtin-metadata.json
```

```json
{
  "builtin.layout_repair": {
    "description": "Detects wrong keyboard layout (e.g. RU↔EN mishits) and corrects it.",
    "appliesTo": ["plain", "layoutWrong", "mixedScript"]
  },
  "builtin.uppercase": {
    "description": "Converts all letters to UPPERCASE.",
    "appliesTo": ["plain"]
  },
  "builtin.trim": {
    "description": "Trims whitespace at the start and end of each line.",
    "appliesTo": ["plain"]
  },
  "builtin.json_pretty": {
    "description": "Reformats JSON with 2-space indentation.",
    "appliesTo": ["json"]
  },
  ...
}
```

`ActionRegistry.metadata(for: actionID)` загружает этот JSON и отдаёт `ActionMetadata{description, appliesTo}`. Если для конкретного action.id нет записи — Description пустая, Applies to — вычисляется через `action.isApplicable` пробежавшись по sample items каждого ContentTypeID.

Готовая metadata.json — это документация продукта внутри продукта. Заодно даст материал для будущего README/website без отдельного maintenance.

### Удаляется из правки №5

- Inline TextField rename в строке списка (был после клика на 🖉) — **отменяется**, заменяется на этот sheet.
- Отдельный «Edit prompt» (🛠) для AI — **отменяется**, тот же sheet редактирует и title, и prompt.
- Маленькая «default» подпись 11 pt под inline title — **переносится** в этот sheet (поле «Default: ...» под Title input).

### Остаётся из правки №5

- Drag handle ⋮⋮ для reorder — без изменений.
- «Paste as is» (identity) заблокирован для drag и для open editor (или editor показывает только enabled toggle с readonly остальным).
- ↺ Reset to default — теперь внутри editor sheet, не в строке списка.
- Persistence (`actionOrder`, `customTitles` в ActionConfig) — без изменений.
- Tooltip на hover в строке списка (Default + ID) — остаётся.
- Inline-detail row на клик по строке (вариант А из правки №5) — **отменяется в пользу editor sheet**. Клик мышью по строке (не на elements внутри) → открывает editor sheet. Один путь к metadata вместо двух.

### Изменённая строка списка (после правки №6)

```
⋮⋮ ☑ My Layout Fix                              [Edit]  [Run]
```

Колонки:
- `⋮⋮` — drag handle (24 pt wide)
- `☑` — enable toggle (24 pt wide)
- Custom title — flexible width
- `[Edit]` — pencil-icon button открывающий sheet (32 pt)
- `[Run]` — text button (60 pt)

Для AI action в начале title добавляется ✨ иконка (15 pt) — единственный визуальный маркер типа в списке (вся подробная информация — в editor sheet).

Для «Paste as is»:

```
   ☑ Paste as is                                          [Run]
```

Нет drag handle, нет Edit (или Edit показывает только enabled toggle с всеми остальными полями read-only — обсудим). По умолчанию — без Edit вообще, чтобы максимально подчеркнуть «это semantic anchor, его не настраивают».

### Преимущества единого editor

1. **Один UI place** — пользователь учит один pattern.
2. **Дискаверабильность всех metadata** — даже для built-in видна description + ID + applies to.
3. **Симметрия** — built-in и AI выглядят как разновидности одной концепции «action», а не два разных продукта.
4. **Простота кода** — одна view вместо двух (rename inline + AI sheet).
5. **Готовность к будущим типам** — если появятся не-AI custom actions (например shell script action, JavaScript transformation), они тоже открываются в этом же editor с подходящими полями.

### UI implementation

```swift
struct ActionEditorSheet: View {
    @Binding var draft: ActionEditorDraft
    let isNewAIAction: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?  // только для AI; для built-in nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title section (always)
            titleSection
            Divider()
            // Metadata section (always — но содержимое условное)
            metadataSection
            // AI-specific (только если isAI)
            if draft.isAI {
                Divider()
                aiSection
            }
            Divider()
            // Enabled toggle (always)
            Toggle("Enabled", isOn: $draft.enabled)

            Spacer()

            // Buttons row
            HStack {
                if let onDelete {
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete action", systemImage: "trash")
                    }
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.escape)
                Button("Save", action: onSave)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520, height: draft.isAI ? 620 : 380)
    }
}
```

`ActionEditorDraft` — POD struct с editable полями. На Save применяется к `ActionConfig` через registry. На Cancel — отбрасывается.

### Что не входит

- **Live preview во время редактирования prompt** — было бы круто, но требует Run-кнопки внутри editor + интеграции с playground sample. Можно добавить отдельной правкой когда станет очевидно нужно. Пока пользователь сохраняет → возвращается в Settings tab → жмёт Run.
- **Diff с дефолтным prompt'ом** — visual подсветка изменений vs bundled default. Хорошо для сложных AI actions, но overkill для v1.
- **Multi-action bulk edit** — выбрать несколько → переименовать pattern'ом или enable/disable. Out of scope.

### Зависимости

- Заменяет UX-часть правки №5 (inline rename), но не отменяет drag-reorder из правки №5. Применять обе правки нужно одной волной — иначе придётся выкидывать недоделанный inline-rename.
- Опирается на правку №4 (multi-provider AI) — dropdown Provider в AI section должен показывать список из `AIProviderRegistry.configured`. Если правка №4 не применена — fallback на список из одного «Anthropic Claude».
- Опирается на **Backlog #8 итерации 1** (Settings + AI editor — уже был, тут refactor в единый sheet).

### Размер изменений

- `SettingsWindow.swift`: ~200 строк новых (`ActionEditorSheet`), но удаляется ~80 строк inline rename и ~120 строк отдельного AIActionEditor. **Net: ~0 строк, упрощение**.
- `Resources/Actions/builtin-metadata.json`: новый файл, ~30 entries × 3 строки = ~90 строк JSON.
- `ActionRegistry`: +20 строк (loading metadata.json, metadata(for:) method).
- `Actions.swift`: без изменений в основной логике.

Итого: +110 строк (но с одновременным удалением ~200 строк из правки №5 что не успели применить).

---

## Правка №7 (iteration 2) — Action Engine dropdown: алгоритм как переменный компонент action'а

**Статус:** запланирована. Развивает правку №6. Архитектурно важное обобщение, ~200 строк (но переформатирует backend модель).

**Затрагивает:** `ActionConfig.swift` (`CustomAIDescriptor` → `CustomActionDescriptor` с полем `engineID`), `Actions.swift` (новый `ActionEngine` слой между descriptor и runtime), `SettingsWindow.swift` (ActionEditorSheet получает Engine dropdown сверху, остальные поля становятся engine-зависимыми), bundled `engines.json` (registry available engines).

### Идея

В правке №6 у нас два класса actions:

- **Built-in** — hardcoded Swift struct, нельзя создать ещё один такой же. Можно только enable/disable + переименовать.
- **AI** — user-creatable, в editor показывает prompt + provider + model.

Это асимметрия. Пользователь может хотеть две версии «UPPERCASE» с разными именами и разными `Applies to` (например «UPPERCASE for English only» и «UPPERCASE for any text»). Или две регулярки с разными pattern'ами. Сейчас это невозможно — built-in единственный.

**Новая модель:**

Любой пользовательский action имеет поле **«Engine»** — выпадающий список заранее реализованных алгоритмов (engines). Engine определяет:
1. Какой код выполняется при apply
2. Какие параметры показываются в editor (`schema` — engine знает свои поля)

Engine — это **plugin point архитектуры**. Built-in actions становятся «factory presets» — это descriptors с уже выбранным engine и заполненными параметрами. Пользователь может создать сколько угодно собственных action'ов, выбирая engine и заполняя его параметры.

### Engine dropdown в editor

В sheet ActionEditorSheet **первым полем после Title** добавляется dropdown:

```
┌─ Edit action ───────────────────────────────────────────────┐
│                                                             │
│  Title       [ My UPPERCASE for emphasis            ]       │
│              Default: UPPERCASE                             │
│                                                             │
│  Engine      [ Text: UPPERCASE                    ▼ ]       │
│              ┌─────────────────────────────────────┐        │
│              │ AI                                  │        │
│              │   ✨ AI prompt                       │        │
│              │ ─────────────────────────────       │        │
│              │ Text                                │        │
│              │   Aa UPPERCASE                      │        │
│              │   aa lowercase                      │        │
│              │   Aa Title Case                     │        │
│              │   Aa Sentence case                  │        │
│              │   _ snake_case                      │        │
│              │   - kebab-case                      │        │
│              │   ⌨ Fix keyboard layout              │        │
│              │   ⤓ Trim whitespace                  │        │
│              │   ⇅ Sort lines                       │        │
│              │   ⊝ Unique lines                     │        │
│              │   🔍 Regex replace                   │        │
│              │   Σ Word/char count                  │        │
│              │ ─────────────────────────────       │        │
│              │ URL                                 │        │
│              │   ✂ Strip tracking params           │        │
│              │   🌐 Just domain                     │        │
│              │   🖼 Generate QR code                │        │
│              │ ─────────────────────────────       │        │
│              │ JSON                                │        │
│              │   { } Pretty-print                  │        │
│              │   { } Minify                        │        │
│              │   { } Extract keys                  │        │
│              │   { } Flatten                       │        │
│              │ ─────────────────────────────       │        │
│              │ Table                               │        │
│              │   ⇆ Transpose                       │        │
│              │   {} CSV → JSON                     │        │
│              │   |  CSV → Markdown table           │        │
│              │ ─────────────────────────────       │        │
│              │ Image (local, CoreImage/Vision)     │        │
│              │   👁 OCR (extract text)              │        │
│              │   ▦ Decode QR                       │        │
│              │   ⚪ Grayscale                       │        │
│              │   ↻ Rotate 90°                      │        │
│              │   ⊖ Invert                          │        │
│              │ ─────────────────────────────       │        │
│              │ Side-effects                        │        │
│              │   📁 Reveal in Finder                │        │
│              │   🌐 Open in browser                 │        │
│              └─────────────────────────────────────┘        │
│                                                             │
│  ─────────────────────────────────────────────────────      │
│                                                             │
│  [Engine-specific parameters appear here]                   │
│                                                             │
│  ─────────────────────────────────────────────────────      │
│                                                             │
│  Applies to                                                 │
│  [✓] Plain text   [ ] Rich text   [ ] URL    ...            │
│                                                             │
│  ☑ Enabled                                                  │
│                                                             │
│  [🗑 Delete]                       [Cancel]    [Save]       │
└─────────────────────────────────────────────────────────────┘
```

Engine dropdown сгруппирован по категориям (Text / URL / JSON / Table / Image / AI / Side-effects). Категории — для navigation; визуально разделены `Divider`-ами или `Picker`-стилевыми Group'ами.

### Engine-specific parameters

В зависимости от выбранного engine — разные поля под dropdown:

**Engine = AI prompt:**

```
Provider         [ Anthropic Claude         ▼ ]
Model            [ Use provider default     ▼ ]
Prompt template  ┌────────────────────────────────┐
                 │ Summarize the user's input...  │
                 │                                │
                 └────────────────────────────────┘
Variables: {INPUT}, {SOURCE_APP}, {SEMANTIC_KIND}
```

**Engine = Regex replace:**

```
Pattern          [ \s+                           ]
Replacement      [ <space>                       ]
☑ Case sensitive
☑ Multi-line
```

**Engine = UPPERCASE / lowercase / Title Case / etc:**

```
(no parameters — algorithm has no settings)
```

**Engine = Strip tracking params (URL):**

```
Tracking parameters to strip (one per line, regex allowed):
┌────────────────────────────────┐
│ utm_*                          │
│ fbclid                         │
│ gclid                          │
│ ref                            │
└────────────────────────────────┘
☑ Use built-in list as starting point
```

**Engine = Reveal in Finder:** no parameters.

**Engine = OCR:**

```
Languages        [ Auto-detect              ▼ ]
                 [ en, ru, sr, ...              ]
☑ Recognize handwriting
```

**Engine = CSV → JSON:**

```
Separator        ⦿ Tab   ○ Comma   ○ Auto-detect
First row is headers  ☑
```

Каждый engine описывает свой `ParameterSchema` — список полей с типами (Text, Toggle, Picker, Multiline, …). Sheet рендерит UI по schema автоматически.

### Архитектура — Engine slot

```swift
// Engine — это logical алгоритм. Не зависит от пользовательских настроек.
struct ActionEngine: Identifiable, Codable {
    let id: String                          // "engine.uppercase", "engine.ai_prompt", "engine.regex"
    let category: EngineCategory            // .text / .url / .json / .table / .image / .ai / .sideEffect
    let displayName: String                 // "UPPERCASE" / "AI prompt" / "Regex replace"
    let iconName: String                    // SF Symbol name
    let parameterSchema: [EngineParameter]  // list of fields editor показывает
    let defaultApplicableTypes: [SemanticKind]
    let isAIBased: Bool                     // true → требует provider
}

enum EngineCategory: String, Codable, CaseIterable {
    case ai, text, url, json, table, markdown, code, image, files, sideEffect
}

struct EngineParameter: Codable, Identifiable {
    let id: String                          // ключ в `parameters` dict
    let displayName: String
    let kind: EngineParameterKind           // .text / .multiline / .toggle / .picker / .number / .stringList
    let defaultValue: AnyCodable?
    let pickerOptions: [String]?            // только для .picker
}

// CustomActionDescriptor — теперь полностью обобщён
struct CustomActionDescriptor: Codable, Identifiable, Equatable {
    var id: String                          // "user.<slug>" или "builtin.<name>" для presets
    var engineID: String                    // обязательно
    var title: String
    var enabled: Bool = true
    var applicableTypes: [String]
    var parameters: [String: AnyCodable]    // engine-specific values
    var isPreset: Bool                      // true для built-in defaults — нельзя удалить (только disable)
}

// ActionConfig — заменяет customAI на customActions
struct ActionConfig: Codable {
    var version: Int = 2
    var enabledFlags: [String: Bool] = [:]
    var customActions: [CustomActionDescriptor] = []   // <-- было customAI
    var actionOrder: [String: [String]] = [:]
    var customTitles: [String: String] = [:]
    var preferences: ActionConfigPreferences = ActionConfigPreferences()
}
```

### Runtime resolution

```swift
final class ActionRegistry {
    let engines: [String: ActionEngine]     // bundled + future user-defined

    func resolve(descriptor: CustomActionDescriptor) -> ClipboardAction? {
        guard let engine = engines[descriptor.engineID] else { return nil }
        return EngineRuntime.make(engine: engine, descriptor: descriptor)
    }
}

enum EngineRuntime {
    static func make(engine: ActionEngine, descriptor: CustomActionDescriptor) -> ClipboardAction {
        switch engine.id {
        case "engine.uppercase":
            return UppercaseEngineAction(descriptor: descriptor)
        case "engine.regex":
            return RegexReplaceEngineAction(descriptor: descriptor)
        case "engine.ai_prompt":
            return AIPromptEngineAction(descriptor: descriptor, provider: resolveProvider(descriptor))
        case "engine.json_pretty":
            return JSONPrettyEngineAction(descriptor: descriptor)
        // ... etc
        default:
            return nil
        }
    }
}
```

Идея: **engine.id → factory class** (как в правке №8 итерации 1 уже было для builtins, но теперь обобщено на все).

### Migration ActionConfig v1 → v2

`customAI: [CustomAIDescriptor]` сейчас → `customActions: [CustomActionDescriptor]` с `engineID: "engine.ai_prompt"`.

Все built-in actions которые сейчас hardcoded в ActionRegistry.init — конвертируются в `customActions[]` с `isPreset: true`. При первом запуске v2 происходит auto-migration:

```swift
if config.version < 2 {
    config.customActions = bundledPresets() + config.customAI.map { aiDescToPresetDesc($0) }
    config.version = 2
    config.save()
}
```

`bundledPresets()` возвращает дефолтный набор descriptors с пометкой `isPreset: true` — это «factory defaults», встроенный набор действий который пользователь видит при первом открытии Settings. Их нельзя delete (кнопка скрыта), но можно disable, переименовать, поменять Applies to, и **forked** — кнопка «Duplicate to customize…» создаёт копию с `isPreset: false` которую можно править свободно.

### Кнопка [Duplicate to customize…]

В editor sheet для presets вместо [Delete] кнопки — **[⎘ Duplicate to customize…]**. Создаёт новый descriptor с тем же engine, скопированными параметрами, новым id (`user.<slug>`), `isPreset = false`. Открывается editor для нового descriptor'а — пользователь меняет что хочет → Save.

Это решает кейс «хочу UPPERCASE только для коротких строк» — duplicates стандартный UPPERCASE engine и в Applies to снимает галочки кроме «Plain text», добавляет regex filter pre-condition (если будет такой param), Save.

### Sheet для built-in preset (read-only поведение)

Для preset descriptor'а — Title editable, Engine dropdown **disabled** (нельзя сменить engine у preset'а — это сломало бы factory default), parameters editable (если engine их имеет), Applies to editable, кнопка [Duplicate to customize…] вместо [Delete].

Для user descriptor (`isPreset: false`) — все поля editable, Engine dropdown editable (можно сменить engine — параметры reset'ятся к defaults нового engine), [Delete] показывается.

### Преимущества обобщения

1. **Симметрия built-in / custom**: оба — `CustomActionDescriptor` с разными engine. Нет «двух классов гражданства».
2. **N инстансов одного engine**: пользователь делает 5 разных Regex replace action'ов под разные задачи. До этого Regex был бы single hardcoded action.
3. **Будущие engines добавляются единообразно**: новый engine = новая запись в `engines.json` + factory case в EngineRuntime. Никаких трогать UI, ActionConfig, Settings — sheet рендерится автоматически по `parameterSchema`.
4. **Action packs становятся семантическими**: вместо «pack даёт 5 hardcoded actions» — «pack даёт 5 descriptors над bundled engines». Импорт чужого pack'а безопаснее (используются только known engines, никакой arbitrary code execution).
5. **Engine = единственное место attack surface для безопасности**. Если когда-нибудь добавим engine.shell или engine.javascript — это будут single hot spots для sandbox review.

### Будущие engines (не входят в текущую правку, но архитектура подготовлена)

| Engine | Категория | Параметры | Когда добавим |
|---|---|---|---|
| engine.shell_command | scripting | command template, timeout, working dir | после стабилизации (security review) |
| engine.javascript | scripting | JS source, sandboxed JSContext | --//-- |
| engine.applescript | scripting | AppleScript source | --//-- |
| engine.http_post | network | URL, headers, body template | для webhook integrations |
| engine.python (PythonKit) | scripting | Python source | overkill — вряд ли |

### UI implementation notes

**Engine dropdown** — `Picker` или `Menu` с group structure. SwiftUI `Picker(selection:) { Section(...) { ... } }` поддерживает grouping. Если визуально не устроит — заменим на custom popover.

**Engine-specific parameters рендер** — switch по schema:

```swift
ForEach(engine.parameterSchema) { param in
    switch param.kind {
    case .text:
        TextField(param.displayName, text: binding(for: param))
    case .multiline:
        TextEditor(text: binding(for: param)).frame(minHeight: 80)
    case .toggle:
        Toggle(param.displayName, isOn: toggleBinding(for: param))
    case .picker:
        Picker(param.displayName, selection: binding(for: param)) {
            ForEach(param.pickerOptions ?? [], id: \.self) { Text($0) }
        }
    case .stringList:
        MultilineListEditor(items: binding(for: param))
    case .number:
        TextField(param.displayName, value: binding(for: param), formatter: NumberFormatter())
    }
}
```

### Что не входит в текущую правку

- **Engine для shell / JS / AppleScript** — security review нужен отдельно (см. таблицу выше).
- **Pipeline engines** (один action = chain нескольких engines) — отдельная архитектурная правка позже.
- **Engine marketplace / sharing** — community может публиковать `.drpaste-actions.json` с собственными descriptors используя bundled engines (правка №4 итерации 1 готова к этому). Custom engines (со своим Swift кодом) — потребовали бы plugin loading, out of scope.
- **Parameter validation** — кроме «не пустое для required» сложной валидации не делаем (например regex syntax check). Если engine вернёт error из apply — это .failed outcome (правка №2 итерации 1).

### Зависимости

- **Сильно завязана на правку №6** (единый editor sheet). Engine dropdown — это просто дополнительное поле в этом sheet'е.
- **Связана с правкой №5** (drag-reorder, customTitles) — те же data structures, без конфликтов.
- Применяем все три правки (№5, №6, №7) **одной волной** — они описывают одну переработку Settings + action model.

### Размер изменений

- `Actions.swift` / новый `Engines.swift`: ~150 строк (Engine struct, ParameterSchema, factory)
- `ActionConfig.swift`: ~80 строк (CustomActionDescriptor + migration v1→v2)
- `SettingsWindow.swift` → ActionEditorSheet: +120 строк (Engine dropdown, dynamic parameter rendering)
- `Resources/Actions/engines.json`: новый файл, ~30 engines × 8 строк = ~240 строк JSON
- Bundled presets in `Resources/Actions/presets.json`: ~30 entries × 6 строк = ~180 строк JSON

Итого: ~770 строк (включая JSON). Чистого Swift кода ~350.

---

## Правка №8 (iteration 2) — Curated default actions + palette для остальных + provider-aware naming

**Статус:** запланирована. Уточняет правки №5/6/7 (особенно #7 — там я нарисовал все engines в списке action'ов, что засоряет). UX cleanup, ~150 строк + правка bundled presets.

**Затрагивает:** `Resources/Actions/presets.json` (curate default set), `Resources/Actions/engines.json` (исправления отдельных engines), `SettingsWindow.swift` (новый PalettePicker sheet, кнопка «+ Add more actions…» внизу списка, badge провайдера для AI actions), `Actions.swift` (новый `PasteAsTextEngine` объединяющий clean+trim).

### Что не так

Сейчас (после правок №5/6/7) в `Plain text` tab показывается **~15 actions сразу**: Paste as is, Fix keyboard layout, UPPERCASE, lowercase, Title Case, Sentence case, camelCase, snake_case, kebab-case, Trim whitespace, Sort lines, Unique lines, Slugify, Base64 encode/decode, URL encode/decode, Word count, Wrap in code block, плюс AI actions. **Слишком много для скана глазами.**

Плюс проблемы конкретных actions:

1. **«Fix keyboard layout»** — название непрозрачное. Я (автор) сам забываю что это делает. Кейс: набрал `eytkflcrjt` думая что в EN-раскладке, оказалось RU; action детектирует и переводит обратно. Полезное, но для **повседневного** flow редко срабатывает — должно быть в palette, не в default списке.

2. **«Trim whitespace»** — отдельное использование почти не нужно; реально хочется trim **в комплекте с очисткой форматирования**. Объединяем с CleanFormatting в один **«Paste as text»** engine.

3. **Title Case / Sentence case / camelCase / snake_case / kebab-case** — слишком специальные, ниша. Не должны жить в default списке. В palette → пользователь явно добавляет если нужно.

4. **URL encode / URL decode** — семантически принадлежат **URL tab**, не Plain text. Перенести.

5. **«Wrap in code block»** — без escaping спецсимволов (`\` `"` `'`) — половинчатое решение. Либо доработать (escape для bash / JSON / Swift), либо унести в Code tab. Делаем обе вещи: переносим в Code tab и **дробим на несколько engines**:
   - `engine.escape_shell` — для shell strings
   - `engine.escape_json` — для JSON string literals
   - `engine.escape_swift` — для Swift string literals
   - `engine.wrap_md_code` — оборачивает в Markdown code block с escape backticks (это собственно «обернуть для документации»)

6. **AI actions с префиксом «AI:»** — теряется информация какой provider используется. «AI: summarize» одинаково может быть Claude / GPT / Ollama. Вместо префикса AI — **badge с именем провайдера**: «Claude: summarize», «GPT-5: summarize», «Ollama: summarize». Это сразу видно cloud vs local.

### Curated default set per content type

**Plain text** (default visible):

```
   Paste as text                       (clean formatting + trim)
   Paste as is                          (identity, всегда первый, locked)
✨ Claude: summarize                    (AI provider in badge)
✨ Claude: translate
✨ Claude: fix grammar
   UPPERCASE
   lowercase
   Sort lines
   Unique lines
   Word / char count
   ★ Generate QR code
[+ Add more actions…]                    palette button at bottom
```

Default visible ≈ 10 actions. Чисто визуально умещается без скролла на 600 pt окне.

**Что переезжает в palette:**

- Fix keyboard layout (всё ещё useful, но opt-in)
- Title Case / Sentence case
- camelCase / snake_case / kebab-case
- Trim whitespace отдельно (не нужен — есть в Paste as text)
- Clean formatting отдельно (не нужен — есть в Paste as text)
- Slugify
- Base64 encode / decode
- HTML entities encode / decode

**URL tab** (default visible):

```
   Paste as is
   Strip tracking parameters
   Just domain
   ★ Generate QR code
✨ Claude: explain link
   URL encode
   URL decode
[+ Add more actions…]
```

URL encode/decode переехали сюда из Plain text.

**Code tab** (default visible):

```
   Paste as is
   Paste as text
   Wrap in Markdown code block          (with backtick escape)
   Tabs → 4 spaces
   4 spaces → tab
   Escape for shell string
   Escape for JSON string
✨ Claude: explain code
✨ Claude: fix bugs
[+ Add more actions…]
```

«Wrap in code block» стал **«Wrap in Markdown code block»** — название однозначное, плюс действительно эскейпит ``` ` ``` внутри content (заменяет на ```` `` ````).

**JSON tab** (default visible):

```
   Paste as is
   Pretty-print
   Minify
   Extract keys
✨ Claude: explain JSON structure
[+ Add more actions…]
```

«Flatten» / «Remove nulls» / «CSV from JSON» — в palette.

**Table tab, Markdown tab, Rich text tab, Image tab, Files tab** — аналогично, по 4–6 default + остальное в palette.

### Palette picker UI

Клик на **[+ Add more actions…]** открывает sheet:

```
┌─ Add action to Plain text ─────────────────────────────────┐
│                                                            │
│ Search [                                            🔍 ]   │
│                                                            │
│ ─ AI (configured providers) ─────────────────────────      │
│   ✨ + New AI action with Claude                            │
│   ✨ + New AI action with GPT-5                             │
│   ✨ + New AI action with Ollama (local)                    │
│   ✨ + New AI action with Custom provider                   │
│                                                            │
│ ─ Text engines (39 available) ──────────────────────       │
│   ⌨ Fix keyboard layout                                    │
│        Detects mistyped text in wrong layout and corrects. │
│        e.g. "eytkflcrjt" → "немного" or vice versa.        │
│   Aa Title Case                                            │
│        "hello world" → "Hello World"                       │
│   Aa Sentence case                                         │
│   _  snake_case                                            │
│   -  kebab-case                                            │
│   Aa camelCase                                             │
│   ✂  Trim whitespace                                       │
│   🧹 Clean formatting only (no trim)                       │
│   🐌 Slugify                                               │
│   ⛓  Base64 encode                                          │
│   ⛓  Base64 decode                                          │
│   ↔  HTML entities encode / decode                          │
│   🔍 Regex replace                                         │
│   ... (still в группе)                                     │
│                                                            │
│ ─ Side-effects ─────────────────────────────────────       │
│   📁 Reveal file in Finder (for files content)              │
│   🌐 Open URL in browser                                   │
│                                                            │
│                                  [Cancel]   [Add]          │
└────────────────────────────────────────────────────────────┘
```

Группировка:
- **AI с providers** — отдельный block сверху, каждая запись = create new AI action с конкретным provider preset'ом. Скрывает factory presets вроде «Claude: summarize» — их пользователь уже видит в default list, тут он создаёт **свои** AI actions.
- **Engines** сгруппированы по категории (Text / URL / JSON / Code / Image / Table / Markdown).
- Каждая запись engine — заголовок + краткое описание + (optional) пример («`hello world` → `Hello World`»). Помогает помнить что делает action.
- Search bar сверху — фильтрует по title или описанию. Live, мгновенно.
- Серым показываются engines уже добавленные в этот content tab (можно добавить второй экземпляр, но визуальный hint «уже есть один»).

Клик **[Add]** на выбранный engine → создаёт descriptor с `isPreset: false`, default applicableTypes = текущий content tab, открывает ActionEditorSheet (правка №6) для настройки → Save → action появляется в списке.

### Provider-aware naming для AI actions

Сейчас (после правки №6/7) AI action в списке отображается как:

```
⋮⋮ ☑ ✨ AI: summarize         [Edit] [Run]
```

Префикс «AI:» — generic, не несёт информации.

Меняем на provider badge:

```
⋮⋮ ☑ [Claude] summarize         [Edit] [Run]
⋮⋮ ☑ [GPT-5] translate          [Edit] [Run]
⋮⋮ ☑ [Ollama] fix grammar       [Edit] [Run]
⋮⋮ ☑ [Custom] explain           [Edit] [Run]
```

Badge — небольшая капсула слева от названия, цветная (по провайдеру):
- Claude — оранжевая (Anthropic accent)
- GPT — зелёная (OpenAI accent)
- Gemini — синяя (Google accent)
- Grok — чёрная
- Mistral — фиолетовая
- DeepSeek — индиго
- Ollama / LM Studio / llama.cpp / Custom — серая (local — нейтральный)

Текст внутри badge — 10 pt monospaced, capsule background с альфа 0.15 от accent цвета. Само action title — нормального стиля.

Когда provider не настроен (action ссылается на unconfigured provider после export/import) — badge становится красной «[?]» и при hover показывает «Provider not configured».

Default factory presets (bundled) ссылаются на **«Default provider»**, не на конкретный — badge показывает **[AI]** до конфигурации, после конфигурации первого provider'а — обновляется на конкретный.

### `PasteAsTextEngine`

Новый engine объединяющий два самых частых текстовых operation'а:

```swift
struct PasteAsTextEngine: Engine {
    static let id = "engine.paste_as_text"

    func apply(item: ClipboardItem, params: [String: AnyCodable]) -> ApplyOutcome {
        // 1. Снять форматирование — превратить в plain text используя
        //    приоритетный representation (UTF-8 plain) либо fallback
        //    через NSAttributedString.string
        let plain = item.plainText() ?? ""
        // 2. Trim whitespace — leading/trailing spaces, tabs, blank lines
        let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        // 3. Параметры (default включены):
        let collapseInnerWhitespace = params.bool("collapseInner", default: false)
        let normalizeQuotes = params.bool("normalizeQuotes", default: false)
        var result = trimmed
        if collapseInnerWhitespace {
            result = result.replacingMultipleSpacesWithSingle()
        }
        if normalizeQuotes {
            result = result.replacingSmartQuotesWithStraight()
        }
        return .preview(makeTextItem(result, from: item))
    }
}
```

Параметры в editor sheet:

```
Engine: Paste as text

Strip formatting  ☑ (always on)
Trim whitespace   ☑ (always on)
Collapse inner whitespace  ☐  ("a   b" → "a b")
Normalize quotes  ☐         ("smart" → "straight")
```

Первые две операции hardcoded и недоступны для отключения (это суть «paste as text»). Остальные две — опциональные параметры.

Это самый частый use case: пришла строка из Word/Slack/Notion с inline форматированием и trailing newline — пользователь хочет чистый текст без артефактов. Сейчас это требует выбора 2-х actions подряд (Clean formatting → Trim whitespace) либо ручного запуска одного с надеждой на второй.

### Удалить из списка default presets

После curation:

- `Clean formatting` (был CleanFormattingAction) — удалить, его функция в Paste as text. Engine остаётся в `engines.json` для возможности использовать отдельно через palette.
- `Trim whitespace` отдельный — то же. Engine остаётся в palette.
- `Fix keyboard layout` — преcет остаётся, но `isPreset: true` + `enabled: false` по дефолту. Пользователь явно enable'ит если нужно. Или добавляет через palette.
- `Title Case` / `Sentence case` / `camelCase` / `snake_case` / `kebab-case` — то же, presets есть, но `enabled: false` по дефолту.
- `Slugify`, `Base64 encode/decode`, `HTML entities` — то же, в palette.

`presets.json` обновляется. `enabled: false` для перенесённых — корректный default, не удаляем descriptor (иначе пользователь не увидит их через palette).

Migration: при загрузке v2 → v3 (новая subversion ConfigVersion) — список default-visible enables перечитывается из bundled `presets.json`, **существующие user-enabled / renamed sostояния** не трогаются. То есть если пользователь успел enable'ить Title Case в v2 — он остаётся enabled в v3.

### Provider badge implementation

В SwiftUI:

```swift
struct ProviderBadge: View {
    let providerKind: ProviderKind?  // nil → "AI" generic
    var body: some View {
        let (label, color) = labelAndColor()
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    private func labelAndColor() -> (String, Color) {
        guard let kind = providerKind else { return ("AI", .gray) }
        switch kind {
        case .anthropic: return ("Claude", .orange)
        case .openai:    return ("GPT", .green)
        case .gemini:    return ("Gemini", .blue)
        case .grok:      return ("Grok", .black)
        case .mistral:   return ("Mistral", .purple)
        case .deepseek:  return ("DeepSeek", .indigo)
        case .ollama, .lmstudio, .llamaCpp, .custom:
            return (kind.displayName, .gray)
        }
    }
}
```

Совместимо с light/dark — color через semantic colors.

### Что не входит

- **Reordering palette items** — отдельная задача. Сейчас порядок в palette — фиксированный (alphabetical внутри категории).
- **Pinned palette** — закрепить часто используемые в верху palette. Нужно после статистики использования, но не в первой реализации.
- **Per-action stats** («использовался 47 раз за последние 30 дней») — было бы хорошо для curation, но сначала собираем `enabledFlags` user-input'ом, статистика позже.
- **Smart suggestions** на основе clipboard content — например при копировании JSON предлагать добавить «JSON pretty» если его нет в enabled. AI feature, отдельная правка.

### Зависимости

- Применяется одной волной с правками №5/№6/№7 (это уточнения той же переработки Settings).
- Опирается на правку №4 (multi-provider AI) — provider badge показывает имена из `AIProviderRegistry`. Без неё все AI actions становятся «[Claude]» по умолчанию.

### Размер изменений

- `Resources/Actions/presets.json`: правка ~30 default-enabled flags (большая часть presets перестают быть default-enabled).
- `Resources/Actions/engines.json`: +3 engine (escape_shell, escape_json, escape_swift) + переименование wrap_md_code + добавление PasteAsTextEngine.
- `Actions.swift` / Engines.swift: +60 строк (PasteAsTextEngine, EscapeShellEngine, EscapeJSONEngine, EscapeSwiftEngine).
- `SettingsWindow.swift`: +120 строк (PalettePicker sheet, search filter, «+ Add more actions…» button, ProviderBadge view).
- `ActionConfig.swift`: +10 строк (config version bump v2 → v3, partial migration).

Итого: ~190 Swift + ~60 строк JSON.

---

## Правка №9 (iteration 2) — Rich Text tab: настоящий rich sample, rich-preserving Result, curated set

**Статус:** запланирована. Уточняет правку №8 для Rich text специфически + добавляет архитектурный pattern «rich-aware AI action». ~200 строк (включая bundled RTF sample, Result pane rich render, MD round-trip для AI).

**Затрагивает:** `ActionConfig.swift` (SettingsSamples — rich sample как RTF, не markdown-в-плейне), `Resources/SettingsSamples/rich-sample.rtf` (новый файл), `SettingsWindow.swift` (Result pane для rich text — рендерит AttributedString через `Text(AttributedString)`), `Actions.swift` / `Engines.swift` (новый `engine.rich_to_html`, новый flag `preserveRichFormatting` в `engine.ai_prompt`), `RichTextHelpers.swift` (новый — NSAttributedString ↔ Markdown round-trip).

### Что не так

**Sample input — фейк:**

Сейчас sample для Rich text — это:

```swift
case .richText:
    text = "Some **rich** text with *italic* and a [link](https://example.com)"
```

Это **plain text с markdown markers**, не настоящий rich text. У `ClipboardItem` пустой `representations` и нет `public.rtf`, поэтому `RichTextToMarkdownAction` (читающий через `representations["public.rtf"]`) не сработает — действие просто покажет original, как бы намекая что «нечего конвертировать». Это сбивает с толку: для пользователя «rich text» это **bold, italic, links, colors** — а ему показывают markdown-исходник. Несоответствие между Tab названием и Tab содержимым.

**Result pane — text-only:**

Result pane сейчас рендерит `previewText` через `Text(...)`. Если action возвращает rich item (с RTF representation) — formatting теряется в превью, пользователь не видит сохранилось ли оно.

**Список actions перегружен:**

Сейчас в Rich text tab видны все actions применимые к `.richText` context: Paste as is, Clean formatting, Trim, UPPERCASE, lowercase, Rich → Markdown, плюс все AI actions, плюс Generate QR (потому что richText содержит plain text representation). 10+ позиций.

Реально полезных в rich text — 5–6: те что **сохраняют форматирование** или **намеренно убирают его целиком**.

### Curated default set для Rich text

```
   Paste as is                       (полная сохранность форматирования)
   Paste as text                     (целенаправленно убрать форматирование)
   Rich → Markdown                   (преобразовать в MD markup)
   Rich → HTML                       (преобразовать в HTML)
✨ [Claude] translate (rich)         (перевести, сохранив форматирование)
✨ [Claude] fix grammar (rich)       (исправить, сохранив форматирование)
[+ Add more actions…]
```

6 actions. Каждое имеет понятную причину быть в default списке:

- **Paste as is** — semantic anchor, всегда первый.
- **Paste as text** — самый частый кейс «вставить без артефактов оригинала».
- **Rich → Markdown** — для документации, GitHub README, технических заметок.
- **Rich → HTML** — для email, web-form WYSIWYG, для копипасты в HTML editor.
- **Claude translate / fix grammar** — AI actions с **сохранением форматирования**. Это и есть основное «суперсила» rich text mode.

Что **в palette** (не в default):

- Strip styles, keep structure (убрать цвета/шрифты, оставить bold/italic/links/headings)
- Convert to plain text (это уже есть в Paste as text но опционально)
- Apply specific font / change font size
- Convert color theme (light → dark or vice versa)
- Extract links list
- Word count (с учётом structure)

### Настоящий Rich sample

Bundled файл `Sources/DrPaste/Resources/SettingsSamples/rich-sample.rtf`:

Содержимое (как text для напоминания о структуре, реальный RTF будет binary):

```
Welcome to DrPaste

DrPaste — это press-and-hold clipboard manager для macOS, дизайн которого
вдохновлён жестами, а не панелями. Зажми ⌥⌘V и держи — появится HUD со
всей историей и доступными actions.

Что есть в этом примере:

  • Заголовок и подзаголовки (h1, h2)
  • Bold выделение и italic emphasis
  • Гиперссылка: https://github.com/ilya000/DrPaste
  • Inline `code` оформление моноширинным шрифтом
  • Список с маркерами и нумерацией

  1. Press and hold ⌥⌘V
  2. Navigate with arrow keys
  3. Release to paste

Цветовой акцент: этот текст выделен accent color чтобы продемонстрировать
что Rich text может нести стилистическую информацию которая теряется при
plain paste.
```

В RTF файле этот текст выглядит так:
- «Welcome to DrPaste» — h1 (24 pt semibold)
- «DrPaste — это press-and-hold...» — body (13 pt regular), с inline **bold** на «press-and-hold» и *italic* на «жестами»
- «Что есть в этом примере:» — h2 (15 pt semibold)
- Список — bullet list с indent
- «`code`» — inline monospaced (Menlo 12 pt) background light grey
- Numbered list 1/2/3
- Link «https://github.com/ilya000/DrPaste» — синий accent + underline
- Последний параграф — accent color (semantic — будет адаптироваться к light/dark)

RTF файл создаётся один раз через TextEdit + правки, или программно через NSAttributedString → `.rtf` data → запись в Resources. Я ставлю на программный путь — он repeatable, легко поправить позже:

```swift
// Helper в build-time или offline:
func generateRichSample() -> Data {
    let s = NSMutableAttributedString()

    // h1
    s.append(NSAttributedString(string: "Welcome to DrPaste\n", attributes: [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold)
    ]))

    s.append(NSAttributedString(string: "\nDrPaste — это ", attributes: [.font: NSFont.systemFont(ofSize: 13)]))
    s.append(NSAttributedString(string: "press-and-hold", attributes: [
        .font: NSFont.boldSystemFont(ofSize: 13)
    ]))
    s.append(NSAttributedString(string: " clipboard manager для macOS, дизайн которого вдохновлён ", attributes: [.font: NSFont.systemFont(ofSize: 13)]))
    s.append(NSAttributedString(string: "жестами", attributes: [
        .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask)
    ]))
    s.append(NSAttributedString(string: ", а не панелями.\n\n", attributes: [.font: NSFont.systemFont(ofSize: 13)]))

    // h2
    s.append(NSAttributedString(string: "Что есть в этом примере:\n\n", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold)
    ]))

    // bullet list
    let bullets = [
        "Заголовок и подзаголовки (h1, h2)",
        "Bold выделение и italic emphasis",
        "Гиперссылка ниже",
        "Inline `code` оформление",
        "Список с маркерами и нумерацией"
    ]
    for b in bullets {
        s.append(NSAttributedString(string: "  • \(b)\n", attributes: [.font: NSFont.systemFont(ofSize: 13)]))
    }
    s.append(NSAttributedString(string: "\n"))

    // link
    s.append(NSAttributedString(string: "Source: ", attributes: [.font: NSFont.systemFont(ofSize: 13)]))
    s.append(NSAttributedString(string: "https://github.com/ilya000/DrPaste\n", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .link: URL(string: "https://github.com/ilya000/DrPaste")!,
        .foregroundColor: NSColor.systemBlue,
        .underlineStyle: NSUnderlineStyle.single.rawValue
    ]))
    s.append(NSAttributedString(string: "\n"))

    // numbered list
    let steps = ["Press and hold ⌥⌘V", "Navigate with arrow keys", "Release to paste"]
    for (i, step) in steps.enumerated() {
        s.append(NSAttributedString(string: "  \(i+1). \(step)\n", attributes: [.font: NSFont.systemFont(ofSize: 13)]))
    }
    s.append(NSAttributedString(string: "\n"))

    // inline code
    let codeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .backgroundColor: NSColor.controlBackgroundColor
    ]
    s.append(NSAttributedString(string: "Inline ", attributes: [.font: NSFont.systemFont(ofSize: 13)]))
    s.append(NSAttributedString(string: "code", attributes: codeAttrs))
    s.append(NSAttributedString(string: " formatting demonstrates monospaced rendering.\n\n", attributes: [.font: NSFont.systemFont(ofSize: 13)]))

    // accent paragraph
    s.append(NSAttributedString(string: "Цветовой акцент: этот текст выделен accent color чтобы продемонстрировать что Rich text может нести стилистическую информацию которая теряется при plain paste.", attributes: [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: NSColor.controlAccentColor
    ]))

    return s.rtf(from: NSRange(location: 0, length: s.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])!
}
```

Этот генератор запускается один раз — produced RTF файл коммитится в `Resources/SettingsSamples/rich-sample.rtf`. Если нужно поменять — перегенерировать.

`SettingsSamples.sample(for: .richText)` строит `ClipboardItem` так:

```swift
case .richText:
    let rtfURL = Bundle.module.url(forResource: "rich-sample", withExtension: "rtf")!
    let rtfData = try! Data(contentsOf: rtfURL)
    let attr = try! NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    let plain = attr.string

    // Сохраняем RTF blob в settings playground storage и оборачиваем в ClipboardItem
    let relPath = playgroundBlobsDir.appendingPathComponent("rich-sample.rtf")
    try? rtfData.write(to: relPath)

    return ClipboardItem(
        id: UUID(),
        semantic: .richText,
        createdAt: Date(),
        representations: [
            "public.rtf": "rich-sample.rtf",
            "public.utf8-plain-text": "rich-sample.txt"  // fallback plain
        ],
        typesOrdered: ["public.rtf", "public.utf8-plain-text"],
        previewText: plain,
        previewImageRel: nil,
        ...
    )
```

Теперь sample имеет **настоящий RTF representation** — все rich-aware actions могут с ним работать корректно.

### Result pane — rich-aware рендеринг

Result pane сейчас:

```swift
TextEditor(text: $resultText)        // или Text(resultText)
```

Меняется на:

```swift
switch resultItem.semantic {
case .richText:
    RichTextPreview(attributedString: loadAttributedString(from: resultItem))
case .image:
    ImagePreview(image: loadImage(from: resultItem))
case .files:
    FilesPreview(files: loadFiles(from: resultItem))
default:
    Text(resultItem.previewText ?? "")
        .font(.system(size: 12))
}
```

`RichTextPreview` использует SwiftUI `Text(AttributedString)`:

```swift
struct RichTextPreview: View {
    let attributedString: AttributedString
    var body: some View {
        ScrollView {
            Text(attributedString)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private func loadAttributedString(from item: ClipboardItem) -> AttributedString {
    guard let rel = item.representations["public.rtf"],
          let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
          let nsAttr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else {
        return AttributedString(item.previewText ?? "")
    }
    return AttributedString(nsAttr)
}
```

NSAttributedString → AttributedString конверсия — native macOS 12+, поддерживает основные attributes (font, foreground/background color, link, underline). Без потерь для нашего use case.

### Rich-preserving AI engine

Главная техническая задача — AI translate / fix grammar **должны сохранять форматирование**.

**Подход:** Markdown round-trip.

1. На входе rich text → конвертируем NSAttributedString → Markdown (через `engine.rich_to_md` логику или новый helper)
2. Отправляем Markdown в AI с префиксом prompt: `"Preserve all Markdown formatting (bold **, italic *, links [text](url), code blocks, lists) exactly as is. Only modify the text content."`
3. AI возвращает Markdown с переведённым content
4. Конвертируем Markdown → NSAttributedString (через `NSAttributedString(markdown:)` — native macOS 12+ API)
5. Сохраняем как rich item, RTF representation генерится из NSAttributedString

В `engine.ai_prompt` добавляется параметр:

```
☑ Preserve rich formatting (Markdown round-trip)
```

Default — **true** когда engine применяется к `.richText` semantic, **false** для `.plain`. Пользователь может override в editor.

Реализация:

```swift
struct AIPromptEngineAction: ClipboardAction {
    let descriptor: CustomActionDescriptor

    func apply(item: ClipboardItem, context: ContentContext) async -> ApplyOutcome {
        let preserveRich = descriptor.parameters.bool("preserveRichFormatting", default: false)
        let isRich = context.contains(.richText) && preserveRich

        var inputText = item.previewText ?? ""
        let systemAddition: String

        if isRich {
            // Конвертируем rich → markdown
            inputText = RichTextHelpers.attributedStringToMarkdown(loadAttributedString(from: item))
            systemAddition = "\nThe input is in Markdown format. Preserve all Markdown markup exactly (bold **, italic *, links [text](url), code `inline`, code blocks ```, headings #, lists -/1.). Only modify the text content, never the markup."
        } else {
            systemAddition = ""
        }

        let fullPrompt = descriptor.parameters.string("promptTemplate") + systemAddition
        let aiResult = try await provider.complete(prompt: inputText, system: fullPrompt, model: provider.defaultModel)

        if isRich {
            // Конвертируем markdown → rich
            let resultAttr = try NSAttributedString(markdown: aiResult)
            let resultItem = makeRichTextItem(resultAttr, from: item)
            return .preview(resultItem)
        } else {
            return .preview(makeTextItem(aiResult, from: item))
        }
    }
}
```

Это означает: один и тот же AI action автоматически работает в plain-mode (для .plain context) и в rich-mode (для .richText context). Не нужно дублировать descriptor.

### Bundled factory presets «(rich)» variants

В `presets.json` для Rich text tab — отдельные descriptors с уже включённым `preserveRichFormatting: true`:

```json
[
  {
    "id": "preset.ai.translate.rich",
    "engineID": "engine.ai_prompt",
    "title": "translate (rich)",
    "applicableTypes": ["richText"],
    "parameters": {
      "promptTemplate": "Translate the input to Russian. If the user provides text in Russian, translate to English instead.",
      "preserveRichFormatting": true
    },
    "isPreset": true
  },
  {
    "id": "preset.ai.fix_grammar.rich",
    "engineID": "engine.ai_prompt",
    "title": "fix grammar (rich)",
    "applicableTypes": ["richText"],
    "parameters": {
      "promptTemplate": "Fix grammar and typos in the input. Do not change meaning or tone. Reply with the corrected text only.",
      "preserveRichFormatting": true
    },
    "isPreset": true
  }
]
```

Title в editor / list — короткий `translate (rich)`. Это даёт пользователю явный сигнал «это rich-aware version». Plain-text вариант остаётся отдельным preset'ом `preset.ai.translate.plain` без суффикса.

Альтернатива — один descriptor с `preserveRichFormatting: auto` который автоматически переключается по context. Думаю — оба варианта валидны, остановимся на **explicit «(rich)» variant**: пользователь видит **намерение** в имени, не магию.

### NSAttributedString ↔ Markdown helper

Apple даёт `NSAttributedString(markdown:)` для парсинга MD в attributed string (macOS 12+). Обратного — нет native API.

Конвертация attributed → markdown — пишем сами:

```swift
enum RichTextHelpers {
    static func attributedStringToMarkdown(_ attr: NSAttributedString) -> String {
        var result = ""
        var lastWasNewline = true
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length)) { attrs, range, _ in
            let text = attr.attributedSubstring(from: range).string
            let font = attrs[.font] as? NSFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            let isMonospace = font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
            let isHeading1 = (font?.pointSize ?? 0) >= 22
            let isHeading2 = (font?.pointSize ?? 0) >= 14 && (font?.pointSize ?? 0) < 22 && isBold
            let isLink = attrs[.link] as? URL

            var segment = text
            if isBold && isItalic { segment = "***\(segment)***" }
            else if isBold { segment = "**\(segment)**" }
            else if isItalic { segment = "*\(segment)*" }

            if isMonospace { segment = "`\(segment)`" }

            if let link = isLink { segment = "[\(text)](\(link.absoluteString))" }

            if isHeading1 && lastWasNewline { segment = "# \(segment)" }
            else if isHeading2 && lastWasNewline { segment = "## \(segment)" }

            result += segment
            lastWasNewline = segment.hasSuffix("\n")
        }
        return result
    }
}
```

Это упрощённый emitter. Не покрывает все edge cases (вложенные lists, tables, blockquotes), но для типичного rich-paste из Slack/Word/Gmail/Notion — работает достаточно well.

Дальнейшие улучшения (future):
- Использовать `swift-markdown` от Apple для надёжного **парсинга**, а emitter тоже на нём
- Использовать `SwiftDown` package для bidirectional
- На крайний случай — sending raw NSAttributedString RTF data в провайдеры что поддерживают (но это provider-specific и не работает с большинством)

### Engine «Rich → HTML»

Новый engine `engine.rich_to_html`. Использует built-in API:

```swift
struct RichToHTMLEngineAction: ClipboardAction {
    func apply(item: ClipboardItem, context: ContentContext) -> ApplyOutcome {
        guard let rel = item.representations["public.rtf"],
              let data = try? Data(contentsOf: AppStorage.blobsDir.appendingPathComponent(rel)),
              let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else {
            return .failed(original: item, reason: "No RTF representation found", recovery: nil)
        }

        guard let htmlData = try? attr.data(from: NSRange(location: 0, length: attr.length),
                                            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
              let htmlString = String(data: htmlData, encoding: .utf8) else {
            return .failed(original: item, reason: "HTML conversion failed", recovery: nil)
        }

        return .preview(makeTextItem(htmlString, from: item))
    }
}
```

Apple даёт нативную RTF → HTML конверсию через `NSAttributedString.data(from:documentAttributes:)` с `.documentType: .html`. Работает корректно для большинства rich content.

### Curated set summary для всех «text-content» tabs

После правки #9 и в продолжение #8:

| Tab | Default visible | В palette |
|---|---|---|
| Plain text | Paste as text, Paste as is, [Claude] summarize/translate/fix, UPPERCASE, lowercase, Sort, Unique, Word count, ★ QR | 25+ engines |
| Rich text | Paste as is, Paste as text, Rich → MD, Rich → HTML, [Claude] translate (rich), [Claude] fix grammar (rich) | strip styles, change font, theme convert, extract links, ... |
| URL | Paste as is, Strip tracking, Just domain, ★ QR, [Claude] explain, URL encode, URL decode | shorten, expand, query params table, ... |
| JSON | Paste as is, Pretty, Minify, Extract keys, [Claude] explain | Flatten, Remove nulls, CSV→JSON, JSON→YAML, ... |
| Table | Paste as is, Transpose, CSV→JSON, CSV→MD | sort by column, sum, count, ... |
| Markdown | Paste as is, MD → plain, MD → HTML, Extract headings | strip code blocks, extract links, TOC, ... |
| Code | Paste as is, Paste as text, Wrap in MD code block, Tabs→Spaces, Spaces→Tabs, Escape for shell, Escape for JSON, [Claude] explain, [Claude] fix bugs | escape Swift, strip comments, count complexity, ... |
| Image | Paste as is, OCR, Decode QR, Strip metadata, Resize 1920, Grayscale | rotate, invert, sepia, compress JPEG, base64 URI, ... |
| Files | Paste as is, Copy paths, Filenames only, Reveal in Finder, MD links | bash list, HTML links, size, SHA-256, parent folder, ... |

Каждый default список — 5–10 actions. Тонкий, осмысленный, без шума.

### Что не входит

- **Bidirectional Markdown library** на основе swift-markdown — отдельная работа, наш простой emitter покроет 90% использования. Замена когда станет очевидно мало.
- **Inline preview formatting changes** в Result pane real-time во время AI streaming — отдельная правка, требует streaming response architecture.
- **Format-aware diff** между input и output для rich actions — было бы круто видеть точно что изменилось, но heavy lift.
- **Custom RTF templates** для bundled sample (несколько вариантов на выбор — Slack-like, Word-like, Gmail-like) — over-engineering для PoC.

### Зависимости

- **Сильно зависит от правки №7** (engine architecture) — нужен `engine.ai_prompt` с параметрами, `engine.rich_to_html`.
- **Зависит от правки №8** (curated presets) — bundled `presets.json` обновляется здесь же.
- **Зависит от правки №4** (multi-provider AI) — provider должен быть resolved через registry, не hardcoded Anthropic.
- Применяется одной волной с #5/6/7/8.

### Размер изменений

- Новый `Resources/SettingsSamples/rich-sample.rtf`: ~3 KB binary (один раз сгенерирован)
- `ActionConfig.swift` (SettingsSamples): ~30 строк (rich sample loader)
- `SettingsWindow.swift` (Result pane semantic switch + RichTextPreview): ~80 строк
- Новый `RichTextHelpers.swift` (attributed ↔ markdown): ~100 строк
- `Engines.swift` (новый RichToHTMLEngineAction + preserveRichFormatting param в AIPromptEngineAction): ~80 строк
- `presets.json`: +6 entries (4 rich-specific + corrections)

Итого: ~290 строк + binary RTF asset.

---

## Правка №10 (iteration 2) — Полная курация default-наборов + Wiki markup + Spanish как default translate target

**Статус:** запланирована. Финализирует curation для всех content tabs (правки №8/9 описали Plain text и Rich text — этот пункт закрывает остальные), добавляет один новый engine (Wiki markup), правит prompt template для translate. ~80 строк (в основном данные `presets.json` + один новый engine).

**Затрагивает:** `Resources/Actions/presets.json` (default-enabled flags + новые presets для каждого tab), `Resources/Actions/engines.json` (новый `engine.rich_to_wiki`), `Engines.swift` (реализация Wiki markup конвертера), `presets.json` (translate AI presets теперь Spanish-default).

### 1. Rich Text → Wiki markup

Новый engine `engine.rich_to_wiki`. Целевой формат — **MediaWiki syntax** (Wikipedia, MediaWiki-based wikis):

- `'''bold'''`
- `''italic''`
- `[[link]]` или `[url text]`
- `== Heading 2 ==`, `=== Heading 3 ===`
- `* bullet item`
- `# numbered item`
- `<code>inline</code>`
- `<pre>block</pre>`

Implementation — close cousin к моему `attributedStringToMarkdown` из правки №9, но с другим markup mapping:

```swift
enum RichTextHelpers {
    static func attributedStringToWiki(_ attr: NSAttributedString) -> String {
        var result = ""
        var lastWasNewline = true
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length)) { attrs, range, _ in
            let text = attr.attributedSubstring(from: range).string
            let font = attrs[.font] as? NSFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            let isMonospace = font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false
            let size = font?.pointSize ?? 13
            let isH1 = size >= 22 && isBold
            let isH2 = size >= 17 && size < 22 && isBold
            let isH3 = size >= 14 && size < 17 && isBold
            let isLink = attrs[.link] as? URL

            var segment = text
            if isBold && isItalic { segment = "'''''\(segment)'''''" }
            else if isBold { segment = "'''\(segment)'''" }
            else if isItalic { segment = "''\(segment)''" }

            if isMonospace { segment = "<code>\(segment)</code>" }

            if let link = isLink {
                segment = "[\(link.absoluteString) \(text)]"
            }

            if isH1 && lastWasNewline { segment = "= \(segment) =" }
            else if isH2 && lastWasNewline { segment = "== \(segment) ==" }
            else if isH3 && lastWasNewline { segment = "=== \(segment) ===" }

            result += segment
            lastWasNewline = segment.hasSuffix("\n")
        }
        return result
    }
}
```

Параметр engine'а (опциональный, default MediaWiki):

```
Wiki dialect    [ MediaWiki        ▼ ]
                ├─ MediaWiki (Wikipedia)
                ├─ DokuWiki
                └─ Confluence
```

DokuWiki / Confluence — присутствуют как опции но в первой реализации работает только MediaWiki, остальные показывают `.failed(reason: "Wiki dialect not yet implemented")`. Архитектурно готово к расширению, реализация отложена.

**В curated default set Rich text** теперь:

```
   Paste as is
   Paste as text
   Rich → Markdown
   Rich → HTML
   Rich → Wiki markup                  ← новый
✨ [Claude] translate (rich)
✨ [Claude] fix grammar (rich)
[+ Add more actions…]
```

7 actions. Всё ещё компактно.

### 2. Spanish как default target language для translate

Сейчас (правка №9 draft) preset translate содержит:

```
"promptTemplate": "Translate the input to Russian. If the user provides text in Russian, translate to English instead."
```

Меняем на **Spanish ↔ English**:

```
"promptTemplate": "Translate the input to Spanish. If the user provides text in Spanish, translate to English instead."
```

Логика: Spanish — самый распространённый non-English язык в мире (≈ 500M+ native speakers), pre-installed в большинстве macOS дистрибуций, типичный default target для translate apps. Русский, сербский, и другие пользователи могут **переопределить prompt** в editor sheet:

1. Открыть `translate (rich)` через [Edit]
2. Изменить `Spanish` на `Russian` в prompt template
3. Опционально — duplicate preset через [⎘ Duplicate to customize…], создать «translate to Russian (rich)» отдельно от Spanish-варианта, держать оба

Также имеет смысл создать **template** в presets.json для quick-add нескольких целевых языков через palette. Не enabled по дефолту, но доступны:

```json
{
  "id": "preset.ai.translate_ru.rich",
  "engineID": "engine.ai_prompt",
  "title": "translate to Russian (rich)",
  "enabled": false,
  "parameters": {
    "promptTemplate": "Translate the input to Russian. Preserve formatting.",
    "preserveRichFormatting": true
  },
  "isPreset": true
}
```

Аналогично — preset'ы для French, German, Chinese, Japanese, Korean, Arabic. Все `enabled: false` по дефолту, доступны через palette. Пользователь enable'ит нужные.

Это решает проблему «обязательно нужен EN ↔ местный» для широкого круга пользователей без необходимости каждому писать prompt самостоятельно.

### 3. Финализация curated sets для всех content tabs

Полные default-enabled списки. Всё остальное — в palette.

#### Plain text (10 default)

```
   Paste as text                       (clean format + trim)
   Paste as is
✨ [Claude] summarize
✨ [Claude] translate (Spanish ↔ EN)
✨ [Claude] fix grammar
   UPPERCASE
   lowercase
   Sort lines
   Word / char count
   ★ Generate QR code
[+ Add more actions…]
```

В palette: Fix keyboard layout, Title Case, Sentence case, camelCase, snake_case, kebab-case, Slugify, Trim только, Clean format только, Base64 enc/dec, HTML entities enc/dec, Unique lines, Regex replace, …

#### Rich text (7 default)

```
   Paste as is
   Paste as text
   Rich → Markdown
   Rich → HTML
   Rich → Wiki markup
✨ [Claude] translate (rich, Spanish ↔ EN)
✨ [Claude] fix grammar (rich)
[+ Add more actions…]
```

В palette: Strip styles keep structure, Change font, Theme convert (light ↔ dark), Extract links list, Word count for rich, …

#### URL (6 default)

```
   Paste as is
   Strip tracking parameters
   Just domain
   ★ Generate QR code
✨ [Claude] explain link
   URL decode (readable form)
[+ Add more actions…]
```

В palette: URL encode (обратное), Query params as table, Markdown link, HTML link, …

(URL encode редко нужен интерактивно — обычно decode. Поэтому только decode в default; encode — в palette.)

#### JSON (6 default)

```
   Paste as is
   Pretty-print
   Minify
   Extract keys
✨ [Claude] explain JSON structure
✨ [Claude] fix JSON              (typical: missing comma, smart quotes, trailing comma)
[+ Add more actions…]
```

В palette: Flatten, Remove nulls, JSON → YAML, JSON → CSV, Type schema generation, …

«Fix JSON» — частый кейс (broken JSON из логов / Slack-формата / WSL output). Стоит держать в default.

#### Table / CSV (6 default)

```
   Paste as is
   Transpose
   CSV → JSON
   CSV → Markdown table
✨ [Claude] summarize table
   Sort by first column
[+ Add more actions…]
```

В palette: CSV → HTML, Sort by second/N column, Sum column, Count rows, Group by, Pivot, …

#### Markdown (6 default)

```
   Paste as is
   Paste as text
   Markdown → HTML
   Markdown → plain
   Extract headings (TOC)
✨ [Claude] polish prose
[+ Add more actions…]
```

В palette: Strip code blocks, Extract links list, MD → Wiki, MD → RST, Lint MD style, …

#### Code (7 default)

```
   Paste as is
   Paste as text
   Wrap in Markdown code block        (with backtick escape)
   Tabs ↔ spaces                       (toggle engine — autodetect direction)
✨ [Claude] explain code
✨ [Claude] fix bugs
✨ [Claude] add inline comments
[+ Add more actions…]
```

«Tabs ↔ spaces» — объединённый engine с autodetect: если в input больше tabs — converts to spaces (configurable indent size), если больше spaces — converts to tabs. Это убирает два symmetric actions из правки №8 в один полезный.

В palette: Escape for shell, Escape for JSON string, Escape for Swift, Strip comments, Count complexity (LOC), Detect language hint, …

#### Image (6 default)

```
   Paste as is
   OCR (extract text)
   Decode QR
   Strip metadata (EXIF/GPS)
   Resize to max 1920 px
   Grayscale
[+ Add more actions…]
```

В palette: Rotate 90° CW/CCW, Flip H/V, Sepia, Noir, Invert, Compress to JPEG 80%, Base64 data URI, PNG ↔ JPEG ↔ HEIC convert, …

#### Files (5 default)

```
   Paste as is
   Copy paths as text
   Filenames only
   Markdown links
   Reveal in Finder
[+ Add more actions…]
```

В palette: Bash-quoted list, HTML links, Size info, SHA-256 hash, Parent folder, Open with…, …

### Подведение баланса

| Tab | Default count |
|---|---|
| Plain text | 10 |
| Rich text | 7 |
| URL | 6 |
| JSON | 6 |
| Table | 6 |
| Markdown | 6 |
| Code | 7 |
| Image | 6 |
| Files | 5 |
| **Всего default-enabled** | **59 actions across 9 tabs** |
| В palette | ≈ 60+ engines |

Плотность ~6 actions per tab — чистый scan-friendly список без скролла. Total engines ≈ 120 (включая будущие dialect / format variants).

### Принципы curation (для будущих правок)

1. **Default-enabled должны быть actions которые осознанно делает 80%+ пользователей в этом content type.** Не «потенциально интересно», а «реально нужно регулярно».
2. **Никакой строгий лимит** — некоторые типы (Plain text, Code) объективно имеют больше core needs. 5–10 — норма.
3. **Paste as is всегда первый.** Это semantic anchor.
4. **Paste as text — почти всегда второй** (где applicable: Plain text, Rich text, Markdown, Code).
5. **AI actions помечены ✨ префиксом**, provider badge показывается separately (правка №8).
6. **Side-effects** (Reveal in Finder, Open URL) — только если они **доминирующий use case** для этого type. Files — да (Reveal). URL — нет (Open URL менее частый чем strip tracking / QR / etc).
7. **Format conversions** — включаем только самые востребованные direction'ы. CSV → JSON — да. JSON → CSV — в palette (редкое направление в реальной работе).
8. **Symmetric pairs** (encode/decode) — оставляем только частое направление в default. URL decode > URL encode. Base64 в palette (редкое в interactive flow).

### Bundled presets.json структура

Финальный формат:

```json
{
  "version": 1,
  "presets": [
    {
      "id": "preset.identity",
      "engineID": "engine.identity",
      "title": "Paste as is",
      "enabled": true,
      "defaultPosition": 0,
      "applicableTabs": ["plain", "richText", "url", "json", "table", "markdown", "code", "image", "files"],
      "locked": true,
      "isPreset": true
    },
    {
      "id": "preset.paste_as_text",
      "engineID": "engine.paste_as_text",
      "title": "Paste as text",
      "enabled": true,
      "defaultPosition": 1,
      "applicableTabs": ["plain", "richText", "markdown", "code"],
      "isPreset": true
    },
    {
      "id": "preset.ai.translate_es.plain",
      "engineID": "engine.ai_prompt",
      "title": "translate",
      "enabled": true,
      "applicableTabs": ["plain"],
      "parameters": {
        "promptTemplate": "Translate the input to Spanish. If the user provides text in Spanish, translate to English instead. Reply with the translation only.",
        "preserveRichFormatting": false
      },
      "isPreset": true
    },
    {
      "id": "preset.ai.translate_ru.plain",
      "engineID": "engine.ai_prompt",
      "title": "translate to Russian",
      "enabled": false,
      "applicableTabs": ["plain"],
      "parameters": {
        "promptTemplate": "Translate the input to Russian. Reply with the translation only.",
        "preserveRichFormatting": false
      },
      "isPreset": true
    }
  ]
}
```

Поле `enabled: true/false` определяет default-visibility. `applicableTabs` — где появляется. `locked: true` — нельзя delete/drag (только для identity).

### Что не входит

- **Stats-based curation** — динамически перетаскивать редко используемые actions в palette. Нужна сбор статистики, отдельная правка.
- **Per-locale defaults** — autodetect системный язык и enabling translate to соответствующий target. Хорошо, но complexity / surface area большая. Сейчас default Spanish для всех.
- **Wiki markup parser** (Wiki → Rich) — обратное направление. Делается отдельно если будет запрос.
- **Multi-language batch translate** — `["en", "ru", "es", "de"]` одним вызовом. Pipeline feature, future.

### Зависимости

- Применяется одной волной с #5/6/7/8/9 — все они переформатируют Settings + action model совместно.
- Не имеет других зависимостей.

### Размер изменений

- `Resources/Actions/engines.json`: +1 entry (engine.rich_to_wiki) + удаление engine.tabs_to_spaces, engine.spaces_to_tabs (заменены на engine.tabs_spaces_toggle).
- `Engines.swift`: +60 строк (RichToWikiEngineAction + TabsSpacesToggleEngineAction).
- `Resources/Actions/presets.json`: переработка всего файла, ~120 строк (59 default-enabled + ~60 в palette).
- `RichTextHelpers.swift`: +50 строк (attributedStringToWiki).
- `ActionConfig.swift`: ~5 строк (поле applicableTabs в descriptor если не было).

Итого: ~115 Swift + ~120 строк JSON.

---

## Правка №11 (iteration 2) — iCloud sync для настроек: actions, presets, preferences

**Статус:** запланирована. UI как placeholder сейчас (как Launch on Login из правки №3), функционал — после code signing. Архитектурно ~300 строк. Меняет философию Export/Import — теперь это fallback для cross-account / sharing, а не основной способ переносить настройки.

**Затрагивает:** новый `iCloudSync.swift` (CloudKitContainer wrapper + ubiquity container access + reconciliation logic), `SettingsWindow.swift` (sync status section в General tab), `ActionConfig.swift` (timestamp-aware save/load + conflict resolution), Info.plist (iCloud entitlements — позже при signing), `AppDelegate` (background sync observer).

### Use case

У Ильи (и типичного power user) — несколько Mac'ов: рабочий ноутбук, домашний iMac, possibly mac mini как сервер. Сейчас настройки DrPaste — actions, prompt templates, переименования, custom AI configurations — живут в `~/Library/Application Support/DrPaste/`, **локально per-device**. После одной правки в Settings нужно либо вручную Export → AirDrop / Dropbox → Import, либо мириться что на втором Mac'е настройки старые.

iCloud sync через **общий Apple ID** должен делать это автоматически: правишь preset «translate to Russian» на ноутбуке → через 5-30 секунд тот же preset появляется на iMac. Никакого manual transfer.

### Что синхронизируется

| Данное | Синхронизация | Хранилище |
|---|---|---|
| `actions.json` (presets, customTitles, actionOrder, enabledFlags, customActions) | **да** | iCloud Drive ubiquity container |
| `providers.json` (provider configs включая ID и base URL, без секретов) | **да** | iCloud Drive ubiquity container |
| **API keys** | **да** | **iCloud Keychain** (`kSecAttrSynchronizable: true`) |
| User preferences (fontScale, soundsEnabled per cue, soundVolume) | **да** | NSUbiquitousKeyValueStore |
| Hotkey rebindings (когда появится UI для них) | **да** | NSUbiquitousKeyValueStore |
| Clipboard history (`index.json` + blobs) | **НЕТ** | local |
| Action playground samples (custom user-input samples in Settings) | **да** | iCloud Drive (small JSON) |
| AX permission state | **НЕТ** (per-device system) | n/a |
| Mode override (Full vs Limited force) | **НЕТ** (per-device, env-dependent) | local |

### API ключи через iCloud Keychain

Ключи хранятся в **iCloud Keychain** через `kSecAttrSynchronizable: true` атрибут — стандартный механизм Apple для секретов синхронизирующихся между устройствами:

```swift
import Security

enum APIKeyStorage {
    static func save(_ key: String, for providerID: String, syncToiCloud: Bool) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ilya000.DrPaste.provider",
            kSecAttrAccount as String: providerID,
            kSecValueData as String: key.data(using: .utf8)!,
            kSecAttrSynchronizable as String: syncToiCloud,
            kSecAttrAccessible as String: syncToiCloud
                ? kSecAttrAccessibleAfterFirstUnlock        // required for synchronizable
                : kSecAttrAccessibleWhenUnlocked
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
```

**Безопасность:**

- **End-to-end encrypted Apple'ом.** Шифрование на устройстве пользователя secret'ом производным от Apple ID password + device passcode. Apple **не имеет ключей** для decrypt.
- **Sync только между устройствами одного Apple ID** с активным iCloud Keychain. Никаких third parties.
- **Require iCloud Keychain enabled** в System Settings → Apple ID → iCloud → Passwords & Keychain. У power user'ов обычно уже включён (Safari logins / Wi-Fi passwords / прочее уже там живут).
- **Не передаются Apple support'у или восстановительным механизмам** при потере пароля — если потерял Apple ID password без recovery key, ключи становятся недоступны (это feature, не bug).

Это **тот же уровень защиты** что используется для всех credit cards / Safari passwords / Wi-Fi keys в iCloud — стандартный pattern Apple ecosystem.

**Per-device revoke trade-off:**

С `kSecAttrSynchronizable: true` удаление ключа на Mac A пропагируется на все устройства через iCloud Keychain. Это означает:

- **Plus:** добавил ключ один раз → доступен на всех Mac'ах автоматически.
- **Plus:** revoke ключа везде одним действием (важно при краже устройства или утечке).
- **Минус:** нельзя «удалить только с этого Mac'а» через Settings UI — для этого надо сначала отключить sync.

UI компромисс — кнопка «Remove API key» в provider editor предлагает выбор:

```
Remove API key for Anthropic Claude?

⦿ Remove from all my Macs (recommended for revocation)
○ Remove from this Mac only — disable iCloud sync first

                          [Cancel]   [Remove]
```

Default — remove everywhere. Для power user'ов с особым use case — explicit per-device путь через disable sync first.

### Почему clipboard history не синхронизируется

1. **Privacy.** Clipboard содержит пароли, токены, личные документы. Sync умножает attack surface.
2. **Размер.** При активном использовании 50–100 items × средний размер 5–50 KB → 250 KB-5 MB на день. За месяц сотни MB. iCloud storage пользователя — не для этого.
3. **Churn.** Clipboard обновляется секундами. Constant sync = load на iCloud Drive и батарею.
4. **Полезность сомнительна.** Скопировал на ноутбуке 30 секунд назад — нужно ли видеть это в iMac истории через минуту? Чаще нет — clipboard очень контекстуален.

Если когда-нибудь сделаем — opt-in toggle с warning'ом про privacy.

### Почему clipboard history не синхронизируется

1. **Privacy.** Clipboard содержит пароли, токены, личные документы. Синхронизация умножает attack surface.
2. **Размер.** При активном использовании 50–100 items × средний размер 5–50 KB → 250 KB-5 MB на день. За месяц это сотни MB. iCloud storage пользователя — не для этого.
3. **Churn.** Clipboard обновляется каждые секунды. Constant sync создаст load на iCloud Drive и батарею.
4. **Полезность сомнительна.** Я скопировал что-то на ноутбуке 30 секунд назад — нужно ли мне видеть это в истории iMac через минуту? Чаще всего нет — clipboard очень контекстуальная штука.

Если когда-нибудь сделаем — отдельный opt-in toggle с warning'ом про privacy.

### Архитектура — два механизма параллельно

**1. NSUbiquitousKeyValueStore** — для маленьких preferences (fontScale, sound toggles, volume, mode preference, …). Лимит 1 MB суммарно, key-value, instant propagation (5–30 секунд). Идеально для UI state.

**2. iCloud Drive ubiquity container** — для `actions.json` и `providers-public.json` (provider configs без ключей). Файловая sync, atomic file replacement. До 200 KB файлы → быстрый upload.

```
~/Library/Mobile Documents/iCloud~com~ilya000~DrPaste/Documents/
  actions.json
  providers-public.json
  samples.json              ← custom playground samples (опционально)
```

Локальные `actions.json` / `providers.json` остаются — это working copy. Sync logic копирует между local Application Support и iCloud Drive ubiquity container.

### Sync engine

```swift
final class iCloudSyncManager {
    static let shared = iCloudSyncManager()

    @Published private(set) var status: SyncStatus = .disabled
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastError: String?

    enum SyncStatus {
        case disabled                   // iCloud sync off
        case unavailable(reason: String) // entitlement missing, signed out, etc.
        case idle                       // synced, waiting
        case syncing
        case conflict(local: Date, remote: Date)
        case error(String)
    }

    func enable() async { ... }
    func disable() { ... }
    func sync() async { ... }
    func resolveConflict(_ resolution: ConflictResolution) async { ... }

    enum ConflictResolution {
        case keepLocal       // local wins, remote overwritten
        case keepRemote      // remote wins, local overwritten (with backup)
        case merge           // attempt automatic merge per-key
    }
}
```

**Sync workflow:**

```
1. App launch / config change / NSMetadataQuery file-change notification
   ↓
2. Compute local file SHA256 + modification time
3. Read remote (ubiquity container) file SHA256 + modification time
   ↓
4. Decision tree:
   - Local same as remote → idle (do nothing)
   - Only local exists → upload local
   - Only remote exists → download remote, replace local
   - Both exist:
     ├─ Same hash → idle
     ├─ Local newer + last_synced_hash == remote hash → upload local
     ├─ Remote newer + last_synced_hash == local hash → download remote
     └─ Both diverged from last_synced_hash → CONFLICT
       ├─ Auto-resolve via merge (per-key последний-wins по timestamps)
       └─ If merge fails → present UI to user, pause sync
```

**Per-key timestamps:** правка добавляет в `ActionConfig` для каждого field tracking modification time. При merge sub-field берется from device которое модифицировало позже.

```swift
struct ActionConfig: Codable {
    var version: Int = 4         // bump за timestamps
    var modifications: [String: Date] = [:]   // key path → timestamp
    var customTitles: [String: String] = [:]
    var actionOrder: [String: [String]] = [:]
    var enabledFlags: [String: Bool] = [:]
    var customActions: [CustomActionDescriptor] = []
    ...
}
```

Merge:

```swift
func merge(_ local: ActionConfig, _ remote: ActionConfig) -> ActionConfig {
    var result = local
    for key in Set(local.customTitles.keys).union(remote.customTitles.keys) {
        let localTS = local.modifications["customTitles.\(key)"] ?? .distantPast
        let remoteTS = remote.modifications["customTitles.\(key)"] ?? .distantPast
        if remoteTS > localTS {
            result.customTitles[key] = remote.customTitles[key]
            result.modifications["customTitles.\(key)"] = remoteTS
        }
    }
    // аналогично для enabledFlags, actionOrder, customActions
    ...
    return result
}
```

Это решает 95% multi-device кейсов автоматически. Conflict UI триггерится только если timestamps идентичны или невалидны.

### Conflict resolution UI

Если auto-merge не справился — sheet:

```
┌─ iCloud sync conflict ──────────────────────────────────────┐
│                                                             │
│ Your DrPaste settings differ between this Mac and iCloud.   │
│                                                             │
│ This Mac (modified 2 min ago):                              │
│   • 14 custom action titles                                 │
│   • 5 enabled AI actions                                    │
│   • Action order customized for 3 tabs                      │
│                                                             │
│ iCloud (modified 5 min ago, from "MacBook Pro"):            │
│   • 12 custom action titles                                 │
│   • 6 enabled AI actions                                    │
│   • Action order customized for 4 tabs                      │
│                                                             │
│ Choose:                                                     │
│   ⦿ Keep this Mac's settings, upload to iCloud              │
│   ○ Use iCloud settings, overwrite this Mac                 │
│     (a backup of current settings is kept)                  │
│   ○ Merge automatically (newer change per setting wins)     │
│                                                             │
│                              [Cancel]   [Apply]             │
└─────────────────────────────────────────────────────────────┘
```

«Cancel» оставляет sync приостановленным до явного решения — sync indicator показывает оранжевый «paused: conflict».

### Settings UI — General tab

Новая section в General tab:

```
┌─ iCloud sync ──────────────────────────────────────────────┐
│                                                            │
│ ☐ Sync settings via iCloud           (coming soon)         │
│                                                            │
│ When enabled, your action presets, AI provider configs,    │
│ API keys, and preferences sync across all Macs signed in   │
│ to the same Apple ID. Clipboard history stays local.       │
│                                                            │
│ Status:    ● Idle — last synced 3 min ago                  │
│ Storage:   18 KB used of available iCloud space            │
│                                                            │
│ [Force sync now]    [Show conflict log]                    │
│                                                            │
│ ☑ Include API keys (via iCloud Keychain)                   │
│   API keys are end-to-end encrypted by Apple. Requires     │
│   iCloud Keychain to be enabled in System Settings.        │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

«Include API keys» — отдельный sub-toggle. Default ON если iCloud sync overall on и iCloud Keychain доступен. Можно выключить если пользователь хочет ключи per-device (странный кейс, но опция есть для control freak'ов).

Если iCloud Keychain выключен в System Settings — sub-toggle серый, ниже подпись «Enable iCloud Keychain in System Settings → Apple ID → iCloud to use this feature».

Toggle, status indicator (●idle / ⚙syncing / ⚠conflict / ✕error), last sync timestamp, used storage, force-sync button, conflict log button.

Disabled (greyed out) **до code signing** — как с Launch on Login (правка №3). После signing — full functionality. Тот же принцип placeholder-toggle-with-coming-soon что зафиксирован в правке №3.

### Entitlements (требуют code signing)

В Info.plist / entitlements file:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.ilya000.DrPaste</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudDocuments</string>
</array>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array>
    <string>iCloud.com.ilya000.DrPaste</string>
</array>
```

Plus `NSUbiquitousContainers` declaration. Это требует:
1. Developer ID / Apple Distribution certificate
2. iCloud container registered в developer portal
3. Provisioning profile с iCloud capability

То есть весь iCloud machinery невозможен без signing. **UI placeholder сейчас, functional implementation после signing milestone.**

### Export / Import после iCloud

После правки iCloud sync — Export / Import (Backlog #8 итерации 1 / правка №4 итерации 2) **остаётся**, но смещается use case:

| Use case | Раньше | После #11 |
|---|---|---|
| «Перенести настройки между моими Mac'ами» | Export → AirDrop → Import | iCloud sync (auto, включая ключи) |
| «Поделиться preset'ом с другом» | Export → отправить файл | Export → отправить файл (всегда без ключей) |
| «Backup перед экспериментами» | Export → сохранить | Export → сохранить |
| «Импорт community action pack» | Import → JSON | Import → JSON |
| «Migration на новый Mac впервые» | Export → Import на новом | Включи iCloud sync — авто, всё переедет |

Export — для cross-account / cross-platform sharing. **Export всегда без API ключей** — отправлять friend'у файл с твоим Anthropic key никогда не должно быть случайно возможно. Это инвариант не зависящий от iCloud sync настроек. iCloud — для one-user-multiple-devices.

### Multi-platform implications

iCloud sync — Apple-only. Это **намеренное ограничение**: DrPaste и так macOS-only. Если когда-нибудь будет Windows / Linux build — там нет ни Keychain, ни iCloud, ни нашего ecosystem. Cross-platform sync можно делать через generic JSON file + user-supplied storage (Dropbox/Drive/GitHub Gist), но это отдельная архитектура. Сейчас iCloud — best path для целевой аудитории.

### Storage budget

`actions.json` после полного customization — обычно 5–50 KB. `providers-public.json` — 1–5 KB. NSUbiquitousKeyValueStore preferences — < 1 KB. Total per-user — обычно < 100 KB.

Apple iCloud free tier — 5 GB. Наш consumption — 0.002% от free tier. Не нагружаем хранилище пользователя визуально. Quota — не concern.

### Notifications

При успешной sync операции — silent. UI просто показывает updated lastSyncDate.

При первой sync на новом устройстве — `UNUserNotification` с message:

```
DrPaste synced 14 custom actions, 3 AI providers, and your API keys
from iCloud. You're ready to go.
```

Если sub-toggle «Include API keys» был выключен:

```
DrPaste synced 14 custom actions and 3 AI providers from iCloud.
Add API keys in Settings → AI Providers to enable AI actions.
```

Дальше — silent. Notification только для onboarding moments.

При conflict — bouncy menu bar icon (как для AX warnings в Limited Mode) + entry в status menu «iCloud sync needs attention…».

### Что не входит

- **Action pack subscriptions** (auto-update от GitHub registry) — отдельная фича.
- **Cross-account collaboration** (shared action library) — over-engineering для PoC.
- **Conflict log как полный history** — сейчас только last conflict. Можно расширить с full audit trail.
- **Granular per-tab sync selection** (выбрать какие content tabs синхронизировать) — для v1 sync либо on либо off, единственный sub-toggle это API keys.
- **Sync between user accounts** — phenotypically невозможно через iCloud без shared CloudKit zone. Out of scope.

### Зависимости

- **Зависит от правки №3** (Launch on login placeholder pattern) — используется тот же UX подход «disabled toggle + coming soon» до code signing.
- **Связана с правкой №4** (multi-provider AI) — синхронизировать список providers, но без ключей. Конкретно — `providers-public.json` исключает API keys через тот же mechanism что Export/Import.
- **Связана с правкой №7** (action engines / descriptors) — сама `actions.json` структура которая будет синхронизироваться.
- **НЕ зависит** от других правок итерации 2 в плане архитектуры — может быть применена отдельной волной после signing milestone.

### Размер изменений

- Новый `iCloudSync.swift`: ~200 строк (manager, status, merge logic)
- `ActionConfig.swift`: +40 строк (per-key timestamps, merge function, version bump v3→v4 + migration)
- `SettingsWindow.swift` → General tab: +60 строк (iCloud section, status indicator, conflict sheet)
- Info.plist / Entitlements: добавление iCloud entitlements (1–2 строки, активны только после signing)
- `AppDelegate`: +30 строк (NSMetadataQuery observer, app-launch sync trigger)

Итого: ~330 строк Swift + entitlements.

---

## Правка №12 (iteration 2) — HUD: corner radius иногда пропадает (intermittent)

**Статус:** запланирована. Bug fix, ~30–60 строк (точная диагностика после reproduction).

**Затрагивает:** `HUD.swift` (HudPanel — конфигурация window, HudHostingView — настройка layer'а), потенциально `Resources/AppIcon.svg` если связано с window shape mask.

### Симптом

При открытии HUD панели углы окна **иногда** закруглены (как ожидалось), **иногда** прямые. Поведение нестабильное — может работать в одной сессии, не работать в следующей. После открытия-закрытия HUD несколько раз состояние «закруглены / прямые» может меняться.

### Возможные причины (диагностика будет при реализации)

1. **NSVisualEffectView vs layer corner radius race.** HUD использует `.hudWindow` material через NSVisualEffectView. Vibrant material имеет собственный layer который рендерится поверх SwiftUI content. Если SwiftUI `.clipShape(RoundedRectangle)` применяется только к content, а vibrant layer не клипуется — углы прямые. Когда macOS пересчитывает window mask — иногда углы исправляются, иногда нет.

2. **`window.contentView?.wantsLayer` отсутствует или сбрасывается.** Если contentView не имеет layer'а — corner radius на нём не работает. SwiftUI обычно добавляет layer автоматически, но в нашем случае content host'ится через `NSHostingView` внутри NSPanel — bootstrap order может быть нестабильным.

3. **Window backing scale factor mismatch.** При перемещении между mon'ами (Retina ↔ non-Retina) или при изменении DPI — layer corner radius может потерять mask.

4. **NSPanel style mask не включает rounded corners по умолчанию.** Если style mask меняется (например при transition между HUD modes — gesture vs key window), corner radius layer может слетать.

5. **isOpaque / backgroundColor не настроены consistent.** Если window становится opaque в каком-то момент (например при ⌥⌘X swap-paste flow) — corner clipping визуально пропадает за фоном.

### Решение — robust corner clipping

Стандартный paranoid pattern для NSPanel с rounded corners:

```swift
final class HudPanel: NSPanel {
    init(allowsKey: Bool) {
        super.init(contentRect: ..., styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Standard ones
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        configureRoundedCorners()
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        configureRoundedCorners()  // re-apply on each layout
    }

    private func configureRoundedCorners() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true
        cv.layer?.cornerRadius = 14
        cv.layer?.cornerCurve = .continuous       // smooth Apple-style continuous corners
        cv.layer?.masksToBounds = true
        // Также для всех subview которые имеют свой layer (vibrant view)
        cv.subviews.forEach { sub in
            sub.layer?.cornerRadius = 14
            sub.layer?.cornerCurve = .continuous
            sub.layer?.masksToBounds = true
        }
    }
}
```

Ключевые моменты:
- **`cornerCurve = .continuous`** — даёт Apple-style smooth corners (squircles) вместо круглых. Это что использует System UI (notifications, alerts).
- **Re-apply при каждом `layoutIfNeeded`** — защита от race condition'ов когда macOS пересоздаёт layer внутри content view'а.
- **Рекурсивно для subview** — vibrant material живёт в собственной NSVisualEffectView с layer'ом, без mask на нём ничего не работает.

### Альтернатива — SwiftUI-based rounded shape

Если AppKit-level mask flaky — переносим rounded clipping полностью в SwiftUI:

```swift
struct HudView: View {
    var body: some View {
        ZStack {
            VisualEffectBackground()  // NSViewRepresentable обёртка над NSVisualEffectView
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}
```

Window остаётся transparent borderless, SwiftUI отвечает за всё визуальное оформление. Это обходит layer race conditions потому что SwiftUI managment'ит свой rendering pipeline.

Минус — небольшое падение perf при тяжёлом vibrant material под SwiftUI clip (re-rendering на каждый scroll/animation). На M1+ незаметно. На Intel Mac'ах может быть на 1–2 fps slower при анимациях, но HUD анимаций мало.

### Решение

Сначала проверяем **AppKit-level fix** с `cornerCurve = .continuous` + `layoutIfNeeded` re-apply. Если intermittent issue остаётся — переходим к SwiftUI-based clip.

### Reproduction steps для verification

1. Открыть HUD `⌥⌘V` 5 раз подряд, дождаться полного открытия каждый раз. Все 5 должны быть закруглены.
2. Открыть HUD во время display sleep (когда экран засыпает и просыпается) — типичный triggering момент для layer race.
3. Между monitor'ами разного DPI (если есть) — переместить HUD на secondary display, переоткрыть.
4. После System Theme change (light → dark live preview) — переоткрыть HUD.

### Зависимости

Никаких — изолированный bug fix.

### Размер изменений

- `HUD.swift` (HudPanel): ~30 строк (cornerCurve, layoutIfNeeded override, recursive sublayer setup)
- Опционально (если AppKit fix не помогает): добавление VisualEffectBackground NSViewRepresentable: ~30 строк

Итого: ~30–60 строк.

---

## Правка №13 (iteration 2) — HUD: большие изображения ломают layout

**Статус:** запланирована. Bug fix важный для UX, ~80–120 строк.

**Затрагивает:** `HUD.swift` (image preview pane), `ClipboardModel.swift` (thumbnail generation на snapshot, если ещё нет), `PreviewSynthesizer` (создание `previewImageRel` для image items).

### Симптом

Когда в clipboard попадает большая картинка (например 4K скриншот 3840×2160, фото с iPhone 4032×3024, или картинка скопированная из Safari 1920×1080+) — HUD пытается отобразить её в **native size**. Поведение:

- HUD окно либо разрастается до размеров экрана (если SwiftUI не имеет ограничений)
- Либо содержимое расползается за пределы окна (если frame ограничен но `Image` `.resizable` не применён)
- Либо preview pane занимает 90% площади HUD, выталкивая actions bar за пределы
- Медленный рендер на каждом keystroke (re-layout при каждой смене selection)
- Большой memory footprint — каждый раз когда selection меняется, full-size NSImage перерисовывается

### Корень проблемы

Сейчас image preview, вероятно, делает что-то вроде:

```swift
Image(nsImage: loadImage(from: item))
```

Без `.resizable()`, без `.aspectRatio(.fit)`, без `.frame(maxWidth/maxHeight)`. SwiftUI берёт intrinsic size картинки — 3840×2160 pt — и пытается всё это нарисовать. Layout не справляется.

### Решение — двухслойный fix

**1. Thumbnail generation на snapshot time**

В `ClipboardWatcher.snapshotPasteboard` (или в `PreviewSynthesizer.synthesize`) — если semantic .image и dimensions > N px (например > 600 в большей стороне), генерируем thumbnail. Сохраняем как отдельный файл `images/<uuid>-preview.png` с max dimension 600 pt при 2x scale (т.е. 1200 actual px — достаточно для Retina HUD без artefacts).

```swift
extension PreviewSynthesizer {
    static func synthesize(types: [String], pasteboard: NSPasteboard, semantic: SemanticKind, store: ClipboardStore) -> (text: String?, imageRel: String?) {
        ...
        if semantic == .image, let imgData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           let fullImage = NSImage(data: imgData) {
            let thumbnail = makeThumbnail(fullImage, maxDimension: 600)  // 600 pt
            let thumbnailRel = store.writeImageBlob(thumbnail.tiffRepresentation!, suffix: "-preview")
            return (text: nil, imageRel: thumbnailRel)
        }
        ...
    }

    static func makeThumbnail(_ source: NSImage, maxDimension: CGFloat) -> NSImage {
        let originalSize = source.size
        let scale = min(maxDimension / originalSize.width, maxDimension / originalSize.height, 1.0)
        if scale >= 1.0 { return source }  // image already small
        let newSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)
        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()
        return thumbnail
    }
}
```

`ClipboardItem.previewImageRel` теперь указывает на thumbnail. Full image остаётся как representation в blob (`representations["public.png"]` etc.) — нужен для paste. HUD рендерит preview через `previewImageRel` без касания full-size data.

**2. SwiftUI Image preview с constraints**

В HUD image preview:

```swift
struct ImagePreviewPane: View {
    let item: ClipboardItem
    var body: some View {
        Group {
            if let rel = item.previewImageRel,
               let nsImg = loadImage(rel: rel) {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 480, maxHeight: 280)   // HUD ограничения
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            } else {
                emptyPlaceholder
            }
        }
    }
}
```

`.resizable()` + `.aspectRatio(.fit)` + `.frame(maxWidth/maxHeight)` — стандартный комбо для контролируемого rendering.

**3. Dimensions / size info под preview**

Когда показывается thumbnail — полезно знать что это thumbnail и какова реальная картинка:

```
[ thumbnail здесь ]
3840 × 2160 px · 4.2 MB · PNG
```

Маленький лейбл 10 pt secondaryLabelColor под изображением. Загружается из `ClipboardItem` metadata — `originalImageSize` и `originalImageFileSize` поля добавляются.

### Edge cases

- **Animated GIFs.** Текущий код вряд ли поддерживает GIF animation в preview. Делаем thumbnail из первого frame'а, под preview подпись «Animated GIF · 24 frames · 2.1 MB». Animation в preview не запускаем — это лишнее визуальное отвлечение в HUD.
- **CMYK / non-sRGB color spaces.** При снижении размера через `NSImage.draw` color space сохраняется. Если оригинальная картинка очень большая в CMYK (например print-ready PDF rasterization) — thumbnail тоже CMYK. Это нормально, SwiftUI рендерит корректно через ColorSync.
- **PDF в clipboard (как изображение).** Иногда PDF попадает в pasteboard как .pdf type. Preview — рендер первой страницы через CGPDFDocument → NSImage → thumbnail. Уже работает для регулярных image кейсов, расширяем на PDF type.
- **Vector content (SVG).** Если клип SVG (редко в pasteboard) — рендер через WKWebView → snapshot → thumbnail. Edge case, опционально.
- **Очень маленькие картинки (icon 16×16).** Не upscale'им, оставляем как есть с center alignment. `.frame(maxWidth: 480, maxHeight: 280)` правильно центрирует.

### Memory cost

Thumbnail file: 600×400 at 2x = 1200×800 PNG. PNG-compressed photo ~ 200-400 KB. Per-item overhead.

При 200 items в истории: 40-80 MB на thumbnails. Приемлемо для современных Mac'ов с 16+ GB RAM. SSD storage — 40-80 MB → не concern.

Cleanup: при удалении item из history thumbnail тоже удаляется (через ClipboardStore.deleteItem).

### Размер ограничений HUD pane (числа для калибровки)

Текущий HUD ~ 600×400 pt. Image preview pane занимает central row ~ 480 px wide × ~ 280 px tall (after учёта header, actions bar, footer). Это финальные frame constraints в .frame(maxWidth/maxHeight).

При font scale > 1.0 (правка #6 итерации 1) — HUD растёт пропорционально. Image preview пропорционально тоже:

```swift
.frame(maxWidth: 480 * fontScale, maxHeight: 280 * fontScale)
```

Хотя картинка не «масштабируется по font», она занимает relative footprint в окне.

### Зависимости

- Никаких архитектурных. Изолированный bug fix + улучшение preview UX.

### Размер изменений

- `ClipboardModel.swift` (PreviewSynthesizer.synthesize): +40 строк (thumbnail generation)
- `ClipboardItem`: +2 поля (originalImageSize, originalImageFileSize) для info-label
- `ClipboardStore`: +10 строк (writeImageBlob с suffix support)
- `HUD.swift` (image preview pane): +30 строк (constraints + size label)
- Migration: existing items без previewImageRel — фоновое thumbnail generation при первом open HUD после update

Итого: ~80–100 строк.

---

## Правка №14 (iteration 2) — Backspace в HUD: удалить item из истории + обновить легенду

**Статус:** запланирована. Маленькая правка ~60 строк. Полезность очень высокая (повседневная очистка истории от случайных копий — паролей, временного мусора).

**Затрагивает:** `HotkeyEngine.swift` (новый delegate-метод `hotkeyEngineDidDeleteFocused()` + интерсепт Backspace в обоих engine'ах), `HUD.swift` (footer legend — добавить `⌫ Delete`), `AppDelegate` (обработчик delete — `ClipboardStore.deleteItem` + reposition selectedIndex). `ClipboardStore.deleteItem(id:)` уже есть от Backlog #6 итерации 1 (Clear history использует тот же mechanism).

### Use case

Часто в clipboard попадает контент который не должен жить в истории:

- Пароль скопированный из 1Password / Bitwarden — не хочется чтобы он остался в clipboard manager'е навсегда.
- Временный токен / ключ для одноразового использования.
- Гигантская картинка которая случайно скопировалась.
- Кусок текста с personal info из email.
- Просто мусор от accidental copy.

Сейчас удаление — только через Recent submenu → entire Clear history (всё одним махом) или ручное редактирование `index.json` (никто этого не делает). Per-item delete отсутствует.

**Backspace в HUD = одноклавишное удаление focused item.** Это самая частая операция уборки. Пользователь должен иметь к ней мгновенный доступ внутри уже открытого HUD без необходимости лазить в System tray.

### Поведение

1. Пользователь зажал `⌥⌘V`, HUD открылся, навигировал стрелками до некоторого item.
2. Нажал **Backspace** (`kVK_Delete` = 51, не `kVK_ForwardDelete`).
3. Item удаляется из `ClipboardStore` (blob storage + thumbnails чистятся, `index.json` обновляется атомарно).
4. Курсор перемещается:
   - На **следующий** item (если есть items после удалённого)
   - Иначе на **предыдущий** (если был последний в списке)
   - Если history стала пустой → закрываем HUD автоматически (нечего показывать)
5. Воспроизводится sound — новый `delete` cue (короткий «pop», `NSSound.Name("Bottle")` fallback). Без визуального toast и без undo.
6. Никакого confirmation alert / sheet — это destructive, но recoverable «случайно нажал → скопирую снова». UX-приоритет — скорость, не paranoia.

### Почему нет undo

Рассматривал session-scoped undo через ⌘Z + toast. Решение — **не делаем**:

- Clipboard items по природе re-populate'ятся естественно — если удалил что-то нужное, скопируешь снова за 2 секунды.
- Undo + toast добавляют complexity (HudState fields, UI animation, ⌘Z интерсепт) ради marginal benefit.
- Audio feedback (delete sound) достаточно для acknowledgement что delete произошёл — пользователь сразу слышит результат.
- Без toast / undo flow остаётся максимально linear и предсказуемым: нажал Backspace → item исчез → курсор переехал → продолжаешь работать.

Принцип: **скорость + recoverability через естественные средства > artificial safety nets**.

### Edge case — Backspace в search режиме (когда появится)

Пока в HUD нет search input'а. Когда появится (отдельная правка), Backspace в search field должен работать как обычный Backspace (delete char), не trigger'ить delete item. Это решится через keyboard focus — если NSTextField has focus, system handles Backspace как edit, наш intercept не срабатывает.

Сейчас (без search) — HUD не имеет text fields, Backspace всегда delete item.

### Footer legend update

Текущий footer (по правкам итерации 1):

```
   ↑↓ Navigate history    ←→ Switch action    +/- Font size    Enter Paste    Esc Cancel
```

Новый:

```
   ↑↓ History   ←→ Action   ⌫ Delete   +/- Font   ⏎ Paste   Esc Cancel
```

(сокращения чтобы вместить всё в одну строку).

При hover на `⌫ Delete` через AX hint или tooltip — «Remove this clipboard item from history».

При font scale большом — footer переносится в две строки. Не критично.

### HotkeyEngine изменения

В обоих engine'ах (EventTapEngine и CarbonHotKeyEngine):

```swift
// EventTapEngine.handle:
if hudIsActive {
    if kc == CGKeyCode(kVK_Delete) {  // = 51 (Backspace)
        delegate?.hotkeyEngineDidDeleteFocused()
        return nil  // глотаем event чтобы не дошёл до frontmost app
    }
    // ... остальные key handlers
}
```

В Limited Mode (Carbon) — Carbon hotkey'ы не регистрируем для Delete отдельно, потому что Carbon hotkey требует modifier. Для Limited Mode используем `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` пока HUD открыт — отлавливает Delete без необходимости в global hotkey.

```swift
if mode == .limited && hudIsActive {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 51 {  // Backspace
            self.delegate?.hotkeyEngineDidDeleteFocused()
            return nil
        }
        return event
    }
}
```

Local monitor только в Limited Mode, потому что в Full Gesture Mode (EventTap) мы уже глобально слушаем все key events.

### Delegate update

```swift
protocol HotkeyEngineDelegate: AnyObject {
    func hotkeyEngineDidSummon(reason: SummonReason)
    func hotkeyEngineDidQuickCopy()
    func hotkeyEngineDidRelease()
    func hotkeyEngineDidNavigate(_ direction: NavDirection)
    func hotkeyEngineDidCancel()
    func hotkeyEngineDidRequestFontChange(_ change: FontChange)
    func hotkeyEngineDidDeleteFocused()       // new
}
```

### AppDelegate handler

```swift
nonisolated func hotkeyEngineDidDeleteFocused() {
    Task { @MainActor in
        guard let state = hudState, let item = state.currentItem else { return }
        let position = state.selectedIndex
        // Remove from store immediately (blob + index)
        store.deleteItem(id: item.id)
        // Reposition cursor
        if state.history.isEmpty {
            closeHUD()
            return
        }
        state.selectedIndex = min(position, state.history.count - 1)
        // Sound feedback
        SoundFeedback.play(.delete)
    }
}
```

Без undo buffer'а — delete immediate и final. `store.deleteItem` уже чистит blob storage и обновляет index атомарно.

### Sound feedback — новый cue

В правке #10 итерации 1 уже было 5 sound cues. Добавляем шестой:

```swift
enum SoundCue: String {
    case copySuccess = "copy-success"
    case copyFailure = "copy-failure"
    case pasteSuccess = "paste-success"
    case pasteFailure = "paste-failure"
    case typeTick = "type-tick"
    case delete = "delete"            // new
}
```

System fallback: `NSSound.Name("Bottle")` — короткий «pop», ассоциируется с trash. Или `Submarine` если предпочтительнее acoustic.

Опционально toggle в Settings → General → Sound feedback section: `☑ Delete from history` (default on).

### Что не входит

- **Multi-select delete.** Выбрать несколько и удалить разом. Нужен Shift+Click / range selection — отдельный больший UX. Out of scope.
- **Undo / restore** — намеренно убрано из дизайна (см. выше).
- **Delete confirmation для "important" items.** Например items с password-like content. Heuristic'и хрупки. Out of scope.
- **Clear history через Backspace в menu** — отдельно от per-item delete.

### Зависимости

- Опирается на `ClipboardStore.deleteItem(id:)` — уже существует (от Backlog #6 итерации 1).
- Опирается на `SoundFeedback.play(.delete)` — добавляется новый cue в правке #10 итерации 1.
- HotkeyEngine изменения совместимы с правкой №9 итерации 1 (Full vs Limited Mode).

### Размер изменений

- `HotkeyEngine.swift`: +25 строк (key interception для Backspace в обоих engine'ах + delegate method)
- `HUD.swift`: +5 строк (footer legend — одна новая запись)
- `AppDelegate`: +15 строк (hotkeyEngineDidDeleteFocused handler)
- `SoundFeedback.swift`: +5 строк (delete cue)
- `Resources/Sounds/delete.aiff` (опционально, иначе system fallback Bottle)

Итого: ~50 строк Swift.

---

## Правка №15 (iteration 2) — HUD header: компактная одна строка + close-X + content meta row

**Статус:** запланирована. UI правка средняя ~150 строк. Состоит из трёх связанных частей: компактификация header'а, кнопка close (safety net), новая строка content meta.

**Затрагивает:** `HUD.swift` (HudView.headerSection полностью пересобирается, новый ContentMetaRow view, close button handler), `ClipboardModel.swift` (`ContentMeta` helper с lazy async compute и in-memory cache), `AppDelegate` (close button → closeHUD path), опционально `SourceResolver` (короткий формат app names).

### Часть 1 — Компактный header в одну строку

Текущий header (по правкам итерации 1):

```
[icon 24pt]  DrPaste                                                         
             47 items in history                                             
             Copied from Safari — OpenAI Documentation                       
```

Три строки. Занимает ~ 60 pt вертикали. Много места для статической информации.

Новый — **одна строка**:

```
[icon 16pt] DrPaste  ·  47  ·  Safari "OpenAI Docs"                    [×]
```

Layout:

- **Icon** 16 pt (вместо 24 pt) слева
- **«DrPaste»** semibold 13 pt
- Разделитель ` · ` (middle dot со spaces) secondaryLabelColor
- **Item count** — просто число «47», без слова "items" (контекст и так ясен из иконки/положения)
- Разделитель ` · `
- **Source** — кратко (см. ниже), truncationMode = .tail если не помещается
- **Spacer**
- **Close button (×)** справа — SF Symbol `xmark.circle.fill`, 14 pt, secondaryLabel → primaryLabel на hover

Всё в одной HStack высотой ~ 22 pt. Экономия ~ 40 pt вертикали vs текущая раскладка.

### Source — короткий формат

Текущий `SourceResolver` отдаёт строку вроде:

```
"Copied from Safari — OpenAI Platform Documentation"
```

Это полная форма. Для compact header — сокращаем:

| Что есть | Compact display |
|---|---|
| app name + window title | `Safari "OpenAI Docs"` (window title в кавычках, truncate до 25 chars) |
| только app name | `Safari` |
| app name + длинный URL/path | `Safari "openai.com/docs..."` (truncate до 25, suffix `...`) |
| nothing resolved | (ничего не отображаем — спейсер пустой между count и close) |

Реализация в `SourceResolver`:

```swift
extension SourceResolver {
    static func resolve(verbose: Bool = false) -> SourceInfo {
        ...
        let appShort = info.appName ?? info.bundleID?.components(separatedBy: ".").last?.capitalized ?? "Unknown"
        let title = info.windowTitle ?? info.documentTitle
        let titleShort = title.map { String($0.prefix(25)) + ($0.count > 25 ? "…" : "") }

        info.compactSummary = titleShort.map { "\(appShort) \"\($0)\"" } ?? appShort
        info.verboseSummary = title.map { "Copied from \(appShort) — \($0)" } ?? "Copied from \(appShort)"
        return info
    }
}
```

В HUD header используется `compactSummary`. Verbose форма остаётся доступной для tooltip на hover header'а (если будет нужно). Также useful для Recent menu в Status item (правка #6 итерации 1).

### Часть 2 — Close button (×)

```
                                                                       [×]
```

Кнопка крестик в правом верхнем углу header'а. **Always visible**, безусловно — не только когда HUD `залип`, а всегда. Это safety net пользователя: «всегда есть надёжный mouse-route чтобы убрать окно с экрана».

**Поведение:**

- **Клик** → закрыть HUD без commit (как `Esc`). Тот же путь что `hotkeyEngineDidCancel`.
- **Hover** → курсор становится pointing-hand, иконка яркеет (secondaryLabelColor → primaryLabelColor).
- **Не имеет keyboard shortcut** — Esc уже делает то же самое. Кнопка для **mouse-only пути** на случай keyboard race conditions.
- **Не закрывает app/Quit** — только HUD. Status item остаётся, hotkey'и работают, следующий ⌥⌘V снова открывает.

**Implementation:**

```swift
Button {
    appDelegate.closeHUD(reason: .userCancel)
} label: {
    Image(systemName: "xmark.circle.fill")
        .symbolRenderingMode(.hierarchical)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
}
.buttonStyle(.plain)
.onHover { hovering in
    NSCursor.pointingHand.set()  // или .arrow на out
}
.accessibilityLabel("Close DrPaste")
.help("Close (Esc)")
```

`.symbolRenderingMode(.hierarchical)` даёт двух-tone visual: внешний круг secondary + крестик primary. Стандарт SF Symbols.

Tooltip `"Close (Esc)"` — для discoverability что Esc делает то же самое.

**Решает проблему «залипания» HUD.** В правке #12 итерации 2 (corner radius) могут быть race condition'ы где HUD не реагирует на keyboard. Close button — orthogonal путь через NSButton click handler, всегда работает.

### Часть 3 — Content meta row (новая, лёгкая)

Под header'ом (или встроена в preview pane header) — маленькая строка с metadata по focused item:

```
[icon] DrPaste · 47 · Safari "OpenAI Docs"                                [×]
       Plain text · 245 words · 1.5 KB
       ─────────────────────────────────────────────────
       [preview pane: actual content]
```

Поле — secondaryLabelColor, 11 pt. Точки разделители ` · `. Левый padding выравнен с началом «DrPaste» (после icon column).

### Что показываем для каждого типа

| Semantic | Meta пример | Заметки |
|---|---|---|
| `.text` (plain) | `Plain text · 245 words · 1.5 KB` | word/char count |
| `.richText` | `Rich text · 245 words · 12 KB · 3 styles` | "styles" = approximate distinct font/size combos |
| `.url` | `URL · example.com` | хост из URL |
| `.email` | `Email · hello@example.com` | full email |
| `.json` | `JSON · 47 keys · 3.2 KB` | если parse'ится; "JSON · invalid · 3.2 KB" если нет |
| `.code` | `Code · 184 lines · Swift` | language hint heuristic |
| `.markdown` | `Markdown · 4 headings · 245 words` | |
| `.table` | `Table · 12 rows · 5 cols` | детект через TSV/CSV split |
| `.image` | `PNG · 1280 × 720 · 845 KB` | dimensions + format + size (из правки #13) |
| `.pdf` | `PDF · 12 pages · 2.4 MB` | page count через CGPDFDocument |
| `.files` | `5 files · 4.2 MB total` | расчёт через FileManager attributesOfItem |
| `.unknown` | `Unknown · 2.1 KB` | только size |

### Lazy computation + caching

**Критическое требование:** не нагружать систему. Не должно тормозить если узнавание занимает заметное время.

**Архитектура:**

```swift
struct ContentMeta {
    let summary: String
    let computedAt: Date
}

final class ContentMetaCache {
    static let shared = ContentMetaCache()
    private var cache: [UUID: ContentMeta] = [:]   // item.id → meta
    private let queue = DispatchQueue(label: "DrPaste.ContentMeta", qos: .userInitiated)

    func meta(for item: ClipboardItem, completion: @escaping (ContentMeta?) -> Void) {
        if let cached = cache[item.id] {
            completion(cached); return
        }
        queue.async {
            let result = self.compute(for: item)
            DispatchQueue.main.async {
                self.cache[item.id] = result
                completion(result)
            }
        }
    }

    func invalidate(for id: UUID) { cache.removeValue(forKey: id) }

    private func compute(for item: ClipboardItem) -> ContentMeta? {
        // Сам compute с timeout-budget'ом
        let budget: TimeInterval = 0.05  // 50 ms
        let start = Date()

        switch item.semantic {
        case .text:
            return computeTextMeta(item, budget: budget, start: start)
        case .json:
            return computeJSONMeta(item, budget: budget, start: start)
        case .image:
            // Уже есть в ClipboardItem.originalImageSize/originalImageFileSize (правка #13)
            return ContentMeta(summary: formatImageSummary(item), computedAt: Date())
        // ...
        }
    }
}
```

**Принципы:**

1. **Compute только когда нужно** — при focusing на item в HUD, не при snapshot'е. Большинство items пользователь никогда не focus'ит → не тратим CPU зря.
2. **Async + main thread completion** — UI рисует placeholder `…` пока meta вычисляется, обновляется когда придёт.
3. **In-memory cache** — после первого compute meta живёт пока приложение запущено. По выходу — забывается. Не сохраняем в `index.json` (это derived data, можно пересчитать).
4. **Cache invalidation** — при `deleteItem` (правка #14) убираем из кэша.
5. **Budget time** — внутри compute функции отслеживаем `Date().timeIntervalSince(start)`; если приближаемся к budget'у — обрезаем работу и возвращаем partial result с суффиксом `~` или `+`.

### Подробнее по типам

**Plain text (`.text`)** — самый частый:

```swift
private func computeTextMeta(_ item: ClipboardItem, budget: TimeInterval, start: Date) -> ContentMeta {
    let text = item.previewText ?? ""
    let byteSize = text.utf8.count

    // Малые тексты — точный count.
    if text.count < 100_000 {
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let chars = text.count
        let lines = text.components(separatedBy: .newlines).count
        return ContentMeta(summary: "Plain text · \(words) words · \(chars) chars · \(lines) lines", computedAt: Date())
    }
    // Большие — approximate через sampling.
    let sample = text.prefix(10_000)
    let sampleWords = sample.split { $0.isWhitespace || $0.isNewline }.count
    let estimatedWords = Int(Double(sampleWords) * Double(text.count) / Double(sample.count))
    return ContentMeta(summary: "Plain text · ~\(estimatedWords) words · \(formatBytes(byteSize))", computedAt: Date())
}
```

100 KB — типичный threshold между instant и noticeable lag.

**JSON (`.json`)** — наиболее затратный:

```swift
private func computeJSONMeta(_ item: ClipboardItem, budget: TimeInterval, start: Date) -> ContentMeta {
    let text = item.previewText ?? ""
    if text.utf8.count > 1_000_000 {
        return ContentMeta(summary: "JSON · large (\(formatBytes(text.utf8.count)))", computedAt: Date())
    }
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) else {
        return ContentMeta(summary: "JSON · invalid · \(formatBytes(text.utf8.count))", computedAt: Date())
    }
    let topLevelKeys: Int
    if let dict = json as? [String: Any] {
        topLevelKeys = dict.count
    } else if let arr = json as? [Any] {
        topLevelKeys = arr.count
    } else {
        topLevelKeys = 0
    }
    let label = topLevelKeys > 0 ? "\(topLevelKeys) \(topLevelKeys == 1 ? "key" : "keys")" : "scalar"
    return ContentMeta(summary: "JSON · \(label) · \(formatBytes(text.utf8.count))", computedAt: Date())
}
```

1 MB — порог, выше которого даже не parse'им — slow для main thread.

**Files (`.files`)**:

```swift
private func computeFilesMeta(_ item: ClipboardItem, budget: TimeInterval, start: Date) -> ContentMeta {
    let paths = item.fileURLs ?? []
    let count = paths.count
    var totalBytes: Int64 = 0
    let startTime = Date()
    for path in paths {
        if Date().timeIntervalSince(startTime) > budget { break }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
           let size = attrs[.size] as? Int64 {
            totalBytes += size
        }
    }
    return ContentMeta(summary: "\(count) \(count == 1 ? "file" : "files") · \(formatBytes(Int(totalBytes))) total", computedAt: Date())
}
```

`attributesOfItem` — синхронный, обычно < 1 ms на файл, но при сетевых mount'ах может быть slow. Budget защищает.

**Image (`.image`)** — данные уже есть в `ClipboardItem` (originalImageSize / originalImageFileSize) от правки #13:

```swift
private func formatImageSummary(_ item: ClipboardItem) -> String {
    let dims: String
    if let size = item.originalImageSize {
        dims = "\(Int(size.width)) × \(Int(size.height))"
    } else {
        dims = "?"
    }
    let bytes = item.originalImageFileSize.map(formatBytes) ?? "?"
    let format = item.imageFormat ?? "image"
    return "\(format) · \(dims) · \(bytes)"
}
```

Instant — никаких heavy ops.

**Code (`.code`)** — language detection через heuristic:

```swift
private func detectLanguage(_ text: String) -> String {
    if text.contains("func ") && text.contains("var ") && text.contains("->") { return "Swift" }
    if text.contains("def ") && text.contains(":") { return "Python" }
    if text.contains("function ") || text.contains("=>") { return "JavaScript" }
    if text.contains("public class") || text.contains("import java.") { return "Java" }
    if text.contains("#include") && text.contains("std::") { return "C++" }
    if text.contains("#include") { return "C" }
    if text.contains("fn ") && text.contains("let ") { return "Rust" }
    if text.contains("package ") && text.contains("func ") { return "Go" }
    return "code"
}
```

Грубая эвристика. Достаточно для UI hint. Точная детекция (через TreeSitter и подобные) — отдельная правка если будет нужно.

### Размещение в UI

Header'ом владеет HudView. Под header'ом (но над preview pane) — новый ContentMetaRow:

```swift
struct HudView: View {
    ...
    var body: some View {
        VStack(spacing: 0) {
            compactHeader            // одна строка
            contentMetaRow           // одна строка, dynamic
            Divider()
            previewPane              // основной content
            actionsBar
            footerKeyhints
        }
    }

    @ViewBuilder
    private var contentMetaRow: some View {
        HStack(spacing: 0) {
            if let meta = state.contentMeta {
                Text(meta.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("…")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}
```

При смене selection — `state.contentMeta = nil` (показывается «…»), запрос в `ContentMetaCache.shared.meta(for: item)`, по completion → `state.contentMeta = result`. SwiftUI rebuild'ит row реактивно.

### Что не входит

- **Per-tab content meta customization** — настраивать какие поля показывать для какого типа. Out of scope.
- **Click on meta для drill-down** (например click на «12 pages» → preview всех страниц PDF). Out of scope.
- **Live update meta** для items которые меняются (не наш кейс — clipboard items immutable после snapshot).
- **Heavy analysis** (например `[Claude] explain content` в meta row) — это actions, не meta.

### Зависимости

- **Зависит от правки №13** (image metadata `originalImageSize` / `originalImageFileSize` уже в ClipboardItem).
- **Зависит от правки №14** (deleteItem → invalidate meta cache).
- **Зависит от существующего SourceResolver** (расширяется на compactSummary + verboseSummary).
- Не имеет других зависимостей.

### Размер изменений

- `HUD.swift`: ~60 строк (compactHeader rewrite, close button, contentMetaRow view, HudState.contentMeta property)
- `ClipboardModel.swift` (новый ContentMetaCache + helpers): ~120 строк
- `SourceResolver.swift`: ~20 строк (compactSummary)
- `AppDelegate`: ~10 строк (closeHUD wiring для button click + invalidate meta cache)

Итого: ~210 строк Swift. Включая ~120 строк lazy compute logic — основная часть «не должно тормозить» требования.

---

## Правка №16 (iteration 2) — ⌥⌘X (Cut & Replace) bug: HUD «зависает» / не реагирует

**Статус:** запланирована. Bug fix критичный для UX. ~120–180 строк защитного кода и state machine refactor.

**Затрагивает:** `PasteSimulator.swift` (synthCut с правильной обработкой modifier'ов), `HotkeyEngine.swift` (фильтрация own synthetic events, atomic state machine вместо boolean), `AppDelegate` (cut&replace flow с verification + watchdog timeout).

### Симптом

При нажатии **⌥⌘X**:
- Иногда работает корректно (selection вырезается, HUD открывается)
- Иногда HUD «зависает» — не реагирует ни на стрелки, ни на Esc, ни на release ⌥⌘. Окно либо невидимое, либо visible но frozen
- Нажатие **⌥⌘V** «отвисает» HUD — окно появляется в нормальном состоянии, дальше работает

### Reproduction

Помогает воспроизвести:
- Быстрые повторные ⌥⌘X (несколько раз в секунду)
- ⌥⌘X в приложениях с heavy main-thread (Slack во время загрузки канала, browsers во время рендера большого DOM)
- ⌥⌘X при отсутствии selection (нечего вырезать)
- ⌥⌘X сразу после resume from sleep
- ⌥⌘X между monitor'ами разного DPI

### Гипотезы корня

**Гипотеза 1: Modifier state mixup при posting synthetic ⌘X.**

Пользователь физически держит ⌥⌘. Мы посылаем CGEvent ⌘X — но физический ⌥ всё ещё down. Зависимо от того, как frontmost app читает modifier state (через `CGEvent.flags` или через `NSEvent.modifierFlags`), он может получить:

- Наш synthetic event с `flags = .maskCommand` (хотим: чистый ⌘X)
- Или системная модель flags = .maskCommand | .maskAlternate (физический ⌥ + наш synth ⌘) → app видит ⌥⌘X, не Cut

При втором — app никак не реагирует (⌥⌘X у большинства приложений не bound), clipboard не обновляется, watcher не подхватывает, HUD открывается без нового item (или с пустой историей если был empty), state machine «думает» что HUD open, но визуально пустой / непонятный.

**Гипотеза 2: Recursion — наш собственный synthetic ⌘X срабатывает наш же EventTap.**

EventTap слушает все keyDown events глобально. Posting CGEvent ⌘X тоже keyDown event. Он может вернуться обратно в наш tap handler. Если он распознаётся как ⌥⌘X (см. Гипотезу 1 — модификаторы сливаются) — наш handler срабатывает recursively, вызывает второй cut+open flow, state machine путается.

**Гипотеза 3: Race condition между simulateCut и openHUD.**

Сейчас flow:

```swift
PasteSimulator.simulateCut()                          // posts ⌘X synth events
DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
    self.openHUD()                                    // через 80 ms
}
```

80 ms — эмпирическое число. На быстрой машине достаточно, но при загруженной системе app ещё не обработал ⌘X, clipboard.changeCount не успел измениться, watcher polls (0.5s) ещё не tick'нул → openHUD рендерит old state. Пользователь видит «не то».

Плюс есть `watcher.forceTick()` который мы должны вызвать до openHUD — но если он сам блокирующий или возвращает рано — openHUD рендерит stale.

**Гипотеза 4: HUD opens но не становится visible.**

NSPanel.orderFront может silently fail если другое app перехватило focus в момент open. Особенно при focus stealing protection в macOS. State machine помечает `hudIsActive = true`, EventTap дальше intercept'ит все клавиши, но пользователь не видит окна → keystroke'и проглатываются «в чёрную дыру».

**Гипотеза 5: HUD флэшит и сразу закрывается.**

Один из этих flow:
- HUD opens → user release'ит ⌥⌘ слишком быстро → release-handler думает что commit → закрывает HUD без визуального feedback.
- Карбон-engine vs EventTap-engine конфликт — оба пытаются обрабатывать release одновременно.

### Многослойный fix

**Слой 1: правильная обработка modifier'ов при synthetic ⌘X**

В `PasteSimulator.simulateCut`:

```swift
static func simulateCut() {
    let src = CGEventSource(stateID: .combinedSessionState)
    src?.setLocalEventsFilterDuringSuppressionState(
        [], state: .eventSuppressionStateRemoteMouseDrag)

    // 1. Сохраняем текущее физическое состояние модификаторов через NSEvent
    let wereOptHeld = NSEvent.modifierFlags.contains(.option)

    // 2. Если ⌥ физически зажат — "приподнимаем" его programmatically на время synth
    if wereOptHeld {
        let optUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Option), keyDown: false)
        optUp?.flags = []
        optUp?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.005)  // 5 ms settling
    }

    // 3. Posting ⌘X
    let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
    cmdDown?.flags = .maskCommand
    let xDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_X), keyDown: true)
    xDown?.flags = .maskCommand
    let xUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_X), keyDown: false)
    xUp?.flags = .maskCommand
    let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Command), keyDown: false)

    // Mark events as ours so EventTap не recursively обработает
    [cmdDown, xDown, xUp, cmdUp].forEach { event in
        event?.setIntegerValueField(.eventSourceUserData, value: DrPasteSyntheticMarker)
    }

    cmdDown?.post(tap: .cghidEventTap)
    xDown?.post(tap: .cghidEventTap)
    xUp?.post(tap: .cghidEventTap)
    cmdUp?.post(tap: .cghidEventTap)

    // 4. Восстанавливаем ⌥ down (если был up'нут в шаге 2)
    if wereOptHeld {
        Thread.sleep(forTimeInterval: 0.005)
        let optDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_Option), keyDown: true)
        optDown?.flags = .maskAlternate
        optDown?.post(tap: .cghidEventTap)
    }
}

private let DrPasteSyntheticMarker: Int64 = 0x44525041535445  // "DRPASTE" ASCII
```

Это **гарантирует app видит чистый ⌘X**, не ⌥⌘X.

Опционально: использовать `CGEventSource(stateID: .privateState)` чтобы наши events не сливались с физическим keyboard state. Но `.privateState` имеет свои edge cases — некоторые apps игнорируют события из non-combined source.

**Слой 2: фильтрация собственных synthetic events в EventTap**

```swift
private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
    // Проверяем marker
    let userData = event.getIntegerValueField(.eventSourceUserData)
    if userData == DrPasteSyntheticMarker {
        return Unmanaged.passUnretained(event)  // skip, не наш business
    }
    // ... остальной handler
}
```

Это **разрывает recursion** — наши synthetic ⌘X / ⌘V / ⌘C никогда не интерпретируются нашим же кодом как hotkey.

**Слой 3: atomic state machine вместо boolean**

Сейчас `hudIsActive: Bool` — не отражает intermediate states.

```swift
enum HudPhase {
    case idle           // HUD not active
    case opening        // openHUD called, awaiting visibility
    case open           // HUD visible, user navigating
    case closing        // commit/cancel in progress
}

@MainActor
final class HudStateMachine {
    private(set) var phase: HudPhase = .idle
    private var openingDeadline: Date?

    func transition(to next: HudPhase) {
        // Логирование, валидация переходов
        let valid: Bool
        switch (phase, next) {
        case (.idle, .opening), (.opening, .open), (.opening, .idle),
             (.open, .closing), (.closing, .idle):
            valid = true
        default:
            valid = false
        }
        guard valid else {
            log("Invalid transition: \(phase) → \(next)")
            return
        }
        phase = next
        if next == .opening {
            openingDeadline = Date().addingTimeInterval(0.5)  // 500ms watchdog
        } else {
            openingDeadline = nil
        }
    }

    func tickWatchdog() {
        // Каждые 100 ms на main loop проверяем не застряли ли в .opening
        if phase == .opening, let deadline = openingDeadline, Date() > deadline {
            log("HUD opening stuck > 500ms, force reset to .idle")
            transition(to: .idle)
            // Notify HotkeyEngine что HUD больше не active
            hotkeyEngine.setHudActive(false)
        }
    }
}
```

В EventTap логика проверки `hudIsActive` заменяется на:

```swift
let isActive = stateMachine.phase == .open
// или для full handling
let interceptInput = stateMachine.phase == .open || stateMachine.phase == .closing
```

Watchdog запускается на main loop через timer 100 ms (lightweight). Если transition в `.opening` зависает > 500 ms — auto-reset в `.idle`, EventTap прекращает intercept, пользователь может нормально печатать.

**Слой 4: HUD visibility verification**

После `openHUD()`:

```swift
private func openHUD() {
    stateMachine.transition(to: .opening)
    hudPanel?.orderFront(nil)
    hudPanel?.makeKey()

    // Verify через 50 ms что окно реально появилось
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        if let panel = self.hudPanel, panel.isVisible {
            self.stateMachine.transition(to: .open)
        } else {
            // Окно не появилось — retry или закрыть state
            self.log("HUD orderFront did not produce visible window")
            self.stateMachine.transition(to: .idle)
            // Опционально retry один раз
            self.hudPanel?.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let panel = self.hudPanel, panel.isVisible {
                    self.stateMachine.transition(to: .opening)
                    self.stateMachine.transition(to: .open)
                }
            }
        }
    }
}
```

Двух-stage check + retry — защита от focus stealing protection.

**Слой 5: cut & replace flow с clipboard change verification**

Сейчас:

```swift
PasteSimulator.simulateCut()
DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { openHUD() }
```

Меняется на event-driven verification:

```swift
nonisolated func hotkeyEngineDidSummon(reason: SummonReason) {
    Task { @MainActor in
        guard reason == .cutAndReplace else {
            self.openHUD()
            return
        }
        let before = NSPasteboard.general.changeCount
        PasteSimulator.simulateCut()

        // Poll до 250 ms ждём изменение clipboard
        let pollStart = Date()
        let pollInterval: TimeInterval = 0.02
        while Date().timeIntervalSince(pollStart) < 0.25 {
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if NSPasteboard.general.changeCount > before {
                // Cut сработал
                self.watcher.forceTick()
                self.openHUD()
                return
            }
        }

        // Timeout — cut не сработал (нет selection / app blocked)
        SoundFeedback.play(.copyFailure)
        // НЕ открываем HUD, не оставляем state в ожидании
        // Юзер сам поймёт что nothing happened
    }
}
```

Это решает:
- **Empty selection case** — cut ничего не сделал, HUD не открывается зря.
- **Loaded app case** — ждём до 250 ms пока app обработает ⌘X, не 80 ms heuristic.
- **State leak** — если cut не сработал, не зависаем в .opening.

### Diagnostic logging

Для будущих bug reports — лог state transitions, modifier checks, и synthetic event posting:

```swift
private let logFile = FileHandle... // ~/Library/Logs/DrPaste/diagnostic.log

enum DiagLog {
    static func log(_ message: String, level: Level = .info) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(level) \(message)\n"
        // ... запись с rotation
    }
}
```

С пунктом в Settings → General → Diagnostics:
- `☐ Enable diagnostic logging` (default off — иначе spam)
- `[Show diagnostic log…]` — открывает файл в Console.app или Finder

Включается только когда пользователь явно репортит баг.

### Что не входит

- **AX-based cut implementation** (вместо CGEvent simulation) — более radical refactor. Делаем CGEvent fix первым, AX как fallback если CGEvent остаётся flaky.
- **Replay attempt при failure** — если cut не сработал, не пробуем ещё раз через 200 ms. Просто silent fail + sound. Retries — отдельная правка.
- **Different timeout** для different apps — некоторые apps медленнее (Slack может > 300 ms). 250 ms покрывает 95% случаев, остальные просто silent fail.
- **Visual feedback на cut failure** в menu bar icon — статус item не флэшит при failure. Только sound. Visual flash — отдельная правка если будет нужно.

### Зависимости

- **Связана с правкой №9 итерации 1** (Full vs Limited Mode) — фиксы должны работать в обоих engine'ах. CarbonHotKey не имеет recursion-проблемы (не глобальный sniffer), но modifier-state и race conditions те же.
- **Использует** `SoundFeedback.play(.copyFailure)` из правки #10 итерации 1 — добавляет cue для silent failures.
- **Орthогонально** правке #14 (Backspace delete) — bugs независимые.

### Размер изменений

- `PasteSimulator.swift`: ~60 строк (modifier handling + event marker)
- `HotkeyEngine.swift`: ~40 строк (event filter + state machine integration)
- Новый `HudStateMachine.swift`: ~80 строк (atomic transitions + watchdog timer)
- `AppDelegate`: ~50 строк (verified open + poll-based cut flow)
- Опциональный `DiagLog.swift`: ~40 строк (если включаем diagnostic logging)

Итого: ~230 Swift + diagnostic logging опционально.

---

## Дальнейшие пункты backlog'а

(будут добавляться по мере того как накапливаются идеи)
