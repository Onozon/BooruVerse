# Konepa

Monorepo with clients for [Kemono](https://kemono.cr) and Booru-style image boards.

## Projects

| Path | Stack | Description |
|------|--------|-------------|
| [`KemonoXcode/BooruVerse`](KemonoXcode/BooruVerse) | SwiftUI (iOS / iPadOS / macOS) | Multi-server Booru browser (Moebooru, Danbooru 2.x, Gelbooru) |
| [`KemonoXcode/Konepa`](KemonoXcode/Konepa) | SwiftUI + SwiftData | Native Kemono client with offline catalog sync |
| [`kemono/`](kemono) | Python + PyQt6 | Original Kemono parser and desktop GUI |
| [`Konepa/Konepa`](Konepa/Konepa) | Qt / C++ / QML | Earlier native Kemono GUI (legacy) |

---

## BooruVerse

SwiftUI app for browsing one or more Booru APIs at once.

**Features**
- Multi-server feed (enable any combination of built-in / custom hosts)
- Browse by tags, favorites, pools, and popular feed
- Gallery with zoom, full-quality fetch, and tiling modes
- Global content rating filter (server-side where supported, client fallback)
- Per-server border colors, optional API credentials (Gelbooru / Danbooru)

**Built-in servers** (toggle in Settings): `safebooru.org`, `yande.re`, `konachan.com`, `danbooru.donmai.us`, `gelbooru.com`

**Open in Xcode**

```bash
open KemonoXcode/BooruVerse/BooruVerse.xcodeproj
```

Requires Xcode 16+ and a recent Apple SDK (folder-synced project).

---

## Konepa (Swift)

Native Kemono client: author/post search, subscriptions, recent history, offline catalog import.

```bash
open KemonoXcode/Konepa/Konepa.xcodeproj
```

---

## kemono (Python)

Parser and PyQt6 GUI for downloading from Kemono.

```bash
cd kemono
python3 -m venv ../.venv
source ../.venv/bin/activate   # Windows: ..\.venv\Scripts\activate
pip install -r requirements.txt
python kemono_gui_v6.py
```

| File | Role |
|------|------|
| `kemono_parser.py` | Core HTTP / Selenium parser |
| `kemono_gui_v6.py` | Current GUI |
| `interactive_downloader.py` | CLI-style downloader |
| `config.json` | Default settings |
| `legacy/` | Older GUI revisions (v1–v5) |

Do not commit `session_cookie.txt` or other session files — they are gitignored.

---

## Konepa (Qt, legacy)

CMake + Qt 6 desktop client under `Konepa/Konepa/`. Build artifacts stay out of git (`build/` is ignored).

```bash
cd Konepa/Konepa
cmake -B build -DCMAKE_PREFIX_PATH="$(brew --prefix qt)"
cmake --build build
```

---

## Docs

- [`docs/pybooru-readthedocs-io-en-stable.epub`](docs/pybooru-readthedocs-io-en-stable.epub) — Pybooru API reference used while building BooruVerse.

---

## License / usage

Personal / research tooling for public APIs and mirrored content. Respect each site’s terms of service and local law. Keep API keys and session cookies out of the repository.
