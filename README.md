# BooruVerse

SwiftUI client for browsing one or more [Booru](https://en.wikipedia.org/wiki/Booru)-style image boards at once (Moebooru, Danbooru 2.x, Gelbooru).

## Features

- Multi-server feed — enable any mix of built-in or custom hosts
- Browse by tags, favorites, pools, and popular feed
- Gallery with zoom, full-quality fetch, and tiling modes
- Global content rating filter (server-side where supported, client fallback)
- Per-server border colors and optional API credentials (Gelbooru / Danbooru)

## Built-in servers

Toggle in Settings:

- `safebooru.org`
- `yande.re`
- `konachan.com`
- `danbooru.donmai.us`
- `gelbooru.com`

## Open in Xcode

```bash
open BooruVerse.xcodeproj
```

Requires Xcode 16+ and a recent Apple SDK (folder-synced project). Targets iOS / iPadOS / macOS.

## Layout

| Path | Role |
|------|------|
| `BooruVerse/` | App sources (API clients, features, models) |
| `BooruVerse.xcodeproj/` | Xcode project |
| `BooruVerseTests/` | Unit tests |
| `BooruVerseUITests/` | UI tests |
| `docs/` | Reference material (e.g. Pybooru API epub) |

## Docs

- [`docs/pybooru-readthedocs-io-en-stable.epub`](docs/pybooru-readthedocs-io-en-stable.epub) — Pybooru API reference used while building the clients

## License / usage

Personal / research tooling for public APIs. Respect each site’s terms of service and local law. Keep API keys and session cookies out of the repository.
