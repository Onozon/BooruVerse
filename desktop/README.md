# BooruVerse (Qt / QML)

Cross-platform client for the same booru APIs as the Apple app: Moebooru, Danbooru 2.x, and Gelbooru.

This tree is the Windows / Linux / Android client. The shipped Apple app stays on the Xcode project in `BooruVerse/`.

The UI is Qt Quick (QML): compact below 700 px (bottom tabs, one Browse screen at a time), regular above that (top tabs, Browse sidebar + grid). Controls stay large enough for touch and comfortable with a mouse and keyboard.

## Requirements

- Qt 6.5+ (Quick, Quick Controls, Qml, Network). On this Mac: `~/Qt/6.11.2/macos`
- CMake 3.21+
- A C++20 compiler (Apple Clang / MSVC / GCC)

## Build (macOS)

```bash
cd desktop
cmake -S . -B build -DCMAKE_PREFIX_PATH="$HOME/Qt/6.11.2/macos"
cmake --build build -j
open build/BooruVerse.app
```

## Build (Windows)

Install Qt 6 for MSVC, then:

```bat
cmake -S . -B build -DCMAKE_PREFIX_PATH=C:\Qt\6.11.2\msvc2022_64
cmake --build build --config Release
```

### GitHub Actions (from macOS / anywhere)

Push to a branch or run **Actions → Desktop Windows → Run workflow**. The job builds `windows-amd64`, runs `windeployqt`, and uploads `BooruVerse-windows-amd64.zip` as an artifact.

CI currently uses Qt **6.8.3** (MSVC 2022). Locally you can keep a newer kit; the project only requires Qt 6.5+.

## What works now

- Adaptive chrome: compact phone/tablet vs regular desktop
- Browse with a tag sidebar (chips, page tags, autocomplete)
- Saved tag sets; check a set to include it in Personal feed
- Feed: Personal mix, plus popular Day / Week / Month
- Local Favorites
- Moebooru Pools (yande.re / konachan)
- Rating filter
- Grid scale (pinch or Ctrl+wheel), Columns / Adaptive, remembered per section
- Exact duplicates collapsed by md5 (caption shows ×N)
- Viewer: typed tags, favorite, save, Site, original, ←/→, Esc
- Tabs keep posts when you switch away
- Settings: boards, colors, credentials, rating, full quality, Personal feed

Safebooru is on by default so the app works without API keys. gelbooru.com still needs User ID + API key.
