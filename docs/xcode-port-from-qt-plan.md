# План: перенос Qt-функционала → Xcode

Приоритет сверху вниз. **Не переносим:** MD5 collapse, Windows CI/zip.

Целевой клиент: SwiftUI (`BooruVerse/`), iPhone / iPad / Mac.

Ориентир UI/поведения: Qt `desktop/` (SelectionChrome, FavoriteStore folders, DownloadStore, `toggleTag`, open site).

Иконки чекбоксов: `icons/checkbox-blank-circle-line.svg` / `checkbox-circle-line.svg`  
(уже в `AppIcon.checkBlank` / `AppIcon.check`).

---

## Зафиксированные решения

### Multi-select / Peek
- **Long-press = Peek** (как Qt), не вход в select.
- Select: Mac / iPad+мышь — **⌘+click**; также **чекбокс в углу Peek**; после появления selection — круглые чекбоксы на карточках и в Viewer.
- Пока selection непустой: на **всех** ячейках сетки угол = круглый checkbox (tap checkbox = toggle select; tap остальной ячейки = открыть viewer как обычно).
- В **Viewer** — checkbox в углу экрана, пока selection непустой.
- Чекбоксы на сетке/viewer **исчезают**, когда selection очищен (Clear / после успешного download всех выбранных / после успешного add всех выбранных в избранное). Иначе говоря: UI чекбоксов виден iff `selection.count > 0` (или только что добавили первого через ⌘/Peek — тогда count ≥ 1).
- Selection **глобальная** на всё приложение (все вкладки).
- **Не сбрасывать** при новом поиске, смене Personal↔Day, открытии pool, смене вкладки.

### Downloads
- Успешные jobs исчезают из UI через **~3s**; **failed остаются** + Retry.
- Batch destination: **один** prompt на всю пачку (Photos vs Save As… / directory).
- Имена файлов: **как Qt** (`{server}_{id}.{ext}`).
- Качество: **всегда original / file URL**, даже из Peek и если original ещё не в кэше.
- Tap по finished job → Finder/Photos: **нет**.

### Toggle tags
- Пишет в **Browse** tag set; **не** переключает вкладку.
- На табе Browse — **badge** с числом выбранных тегов.
- Чипы в Peek/Viewer/page tags меняют стиль, если тег выбран в Browse.

### Favorites folders
- Пока оставляем модель **id + refetch** (не Qt snapshots).
- Пост только в **одной** папке.
- Unfavorite = полное удаление из избранного (из той единственной папки).
- Кнопка favorite в Viewer/Peek: красная если уже в избранном → повторный тап = unfavorite (логика не ломается).
- Favorites UI папок: **sidebar как Browse** (compact: slide Folders ↔ Posts).
- Batch/single add: **folder picker как Qt**, preselect **last used** folder.

### Keyboard
- ←↑→↓, Enter, **F**, плюс **Space = peek**, **Esc = clear selection**, **⌘A = select visible**.
- Key **codes**, не символы раскладки.
- Те же биндинги на **iPad + hardware keyboard**.

### Open on site / Peek meta
- Server line в Peek: **display name**, мелкий, слегка прозрачный.
- Open on site: кнопки нет, если URL отсутствует (**скрыть**).

### Chrome placement
- Compact: selection chrome **левее кнопки Refresh**.
- Peek select: **круглый checkbox в углу окна Peek**, не нижняя кнопка как в Qt.

---

## Порядок реализации

### 1. Open on site
Кнопка в Viewer и Peek → URL поста в браузере (`AppIcon.site`). Скрыть, если URL нет.  
Source URL — вне scope.

### 2. Toggle tag из Viewer / Peek (+ selected chip style)
`toggleTag` в общий Browse tag store; без смены вкладки; badge на Browse; яркий selected chip.

### 3. Multi-select
Глобальный `SelectionStore`; ⌘+click; Peek corner checkbox; при `count > 0` — checkboxes на всех карточках + Viewer corner; круглые Remix icons.

### 4. Selection chrome + Downloads
Chrome: count / list / remove one / Clear / Favorites / Download→Photos | Save As….  
Все saves (batch + Peek/Viewer) через `DownloadStore`; always original; success auto-hide 3s; failures + Retry.

### 5. Клавиатура в гриде
Layout-independent: arrows, Enter, F, Space, Esc, ⌘A. Не перехватывать, когда фокус в text field.

### 6. Настройки пути скачивания
Default: directory/file prompt на пачку. Settings: optional fixed folder → без prompt.

### 7. Папки избранного
Default «Favorites»; CRUD; one folder per post; picker with last-used; Favorites sidebar как Browse; migrate existing IDs → default folder. Хранение пока id+refetch.

### 8. Peek: строка сервера
Display name, secondary/opacity text.

---

## Фазы поставки

| Фаза | Пункты | Статус |
|------|--------|--------|
| A | 1, 8, 2 | **Сделано** (2026-09-03) |
| B | 3, 4, 6 | **Сделано** (2026-09-03) |
| C | 5 | **Сделано** (2026-09-03) |
| D | 7 | **Сделано** (2026-09-03) |

---

## Вне scope

- MD5 duplicate collapse
- Windows CI / zip
- Open source URL (пока)
- Миграция favorites на full post snapshots (пока)

---

## Пояснения к непонятным вопросам (закрыты)

### Бывш. Q6 — «permission prompt» Photos
Доступ к Photos: запросить **один раз при первом запуске** (или при первом save в Photos, если так проще на платформе).  
Если отказал / отозвал в Settings — job в downloads с ошибкой «нет доступа к Photos».  
Destination prompt (Photos vs Save As / directory) — **один на пачку**.

### Бывш. Q12 — haptic
Haptic **только при открытии Peek**. Toggle tag и прочее — без вибрации.

### Бывш. Q13 — «снять последний тег»
Снять последний Browse-тег из Peek/Viewer → пустой Browse query (нормально).

---

## Зависимости

```
Open site, Peek server line     → независимы (фаза A)
Toggle tag + chip + Browse badge → общий Browse tag store
Multi-select                     → SelectionStore + cell/peek/viewer checkboxes
Downloads list                   → вместе с chrome download actions
Download path setting            → читается DownloadStore
Favorite folders                 → поверх selection Favorites action
Keyboard                         → после grid + selection
```
