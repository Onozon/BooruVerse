# Qt vs Xcode — функциональные расхождения

Краткий снимок на 2026-09-03 (обновлено после порта A–D в Xcode). Общий каркас совпадает. Ниже только отличия.

Платформы: **Xcode** = iOS / iPadOS / macOS (SwiftUI). **Qt** = desktop (macOS / Windows / Linux).

---

## Только Qt (отрыв desktop)

| Функция | Суть |
|--------|------|
| Локальные снимки избранного | Хранятся полные посты (не только id) |
| MD5 collapse | Один кадр + `×N` при одинаковом md5 с разных серверов |
| Windows CI / zip | Сборка `BooruVerse-windows-amd64` |

---

## Только Xcode (ещё эксклюзив)

| Функция | Суть |
|--------|------|
| Save to Photos | В системную Фотоплёнку (iOS/Mac Photos) |
| Pull-to-refresh | Жест обновления списка (посты / pools) |
| Scroll restore к посту | После закрытия gallery грид возвращается к просмотренному посту |
| Жесты dismiss gallery | Swipe-away / vertical dismiss (особенно iPhone) |
| iPhone / iPad UI | Нативный `TabView`, phone chrome, safe areas как primary target |
| Favorites = id + refetch | Избранное — список id по серверу; лента тянется с сети (офлайн слабее Qt) |

---

## Похоже, но не 1:1

| Область | Xcode | Qt |
|--------|-------|-----|
| Масштаб сетки | Pinch, **per-section** (Browse/Feed/Favorites/Pools) | Pinch / Ctrl+wheel; slider в Settings; per-section в C++ settings |
| Multi-select | Глобальный `SelectionStore`; ⌘/Ctrl+click; Peek checkbox; chrome | Ctrl/Cmd+клик; SelectionChrome |
| Batch download | `DownloadStore` очередь, Photos / Save As, retry, 3s hide | То же по смыслу; открытие файла в Finder — нет в Xcode |
| Папки избранного | Sidebar + picker; id+refetch (не snapshots) | Create/rename/delete + полные снимки постов |
| Open on site | Viewer / Peek / context menu | Viewer / Peek |
| Toggle tag из viewer/peek | В Browse без смены вкладки + badge | `toggleTag`, можно остаться в overlay |
| Клавиатура в гриде | Стрелки, Enter, F, Space=peek, Esc, ⌘A | Стрелки, Enter, F |
| Compact layout | Mac &lt;~700pt → bottom tabs | То же по ширине окна |

---

## Паритет (оба есть)

- Вкладки Feed (Personal / Day / Week / Month), Browse, Pools, Favorites, Settings  
- Multi-server merge, enable/disable, add host, credentials, border color  
- Tag search, suggestions, chips, saved sets, page tags, Personal feed sets  
- Rating filter, Columns vs Adaptive Rows, full-quality in viewer  
- Grid → viewer / long-press peek, zoom, favorite toggle  
- Infinite scroll / load more  
- Multi-select + selection chrome + batch download + favorite folders  
- Open on site, toggle tag из peek/viewer, grid keyboard  

---

## Заметки

1. Главный оставшийся отрыв Qt: **MD5 collapse**, **favorite snapshots**, **Windows CI**.  
2. Главный отрыв Xcode: **Photos + mobile UX + scroll-back к посту**.  
3. План порта и баги: [`xcode-port-from-qt-plan.md`](xcode-port-from-qt-plan.md), [`xcode-port-bugs.md`](xcode-port-bugs.md).
