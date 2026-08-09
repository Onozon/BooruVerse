<p align="center">
  <img src="Design/Logo/booruverse-icon.png" alt="BooruVerse" width="160" height="160">
</p>

<h1 align="center">BooruVerse</h1>

<p align="center">A native Apple app for browsing image boards — several at once, in one feed.</p>

BooruVerse talks to Moebooru, Danbooru 2.x, and Gelbooru APIs. Flip on the hosts you care about, search with tags, and flip through posts without hopping between sites.

Built with SwiftUI for iPhone, iPad, and Mac.

## Download

macOS builds are on the [Releases](https://github.com/Onozon/BooruVerse/releases) page (`BooruVerse-*-macOS.zip`).

1. Unzip and move `BooruVerse.app` somewhere convenient (e.g. Applications).
2. First launch will likely be blocked by Gatekeeper (the build is not notarized). Right-click the app → **Open**, or clear the quarantine flag:

```bash
xattr -cr /path/to/BooruVerse.app
```

Current release is **Apple Silicon (arm64)** and needs **macOS 14.6+**.

## What you get

**One feed, many servers.** Enable Safebooru, yande.re, Konachan, Danbooru, Gelbooru, or any custom host that speaks a supported API. Results merge into a single stream; each server keeps its own border color so you can tell them apart.

**Search that stays out of the way.** Tag chips, suggestions, saved tag sets, and a rating filter that applies everywhere — Browse, Feed, Pools, Favorites.

**A gallery meant for looking.** Pinch-zoom, full-size fetch, peek overlays, and two tiling modes (column stacks or adaptive rows).

**Pools & favorites.** Browse pools on servers that expose them, and keep a local favorites list across hosts.

**Add your own boards.** Paste a host; BooruVerse probes it and picks the API flavor automatically. Optional credentials for Gelbooru / Danbooru when you need them.

## Requirements

- Xcode 16+
- A recent iOS / iPadOS / macOS SDK

```bash
open BooruVerse.xcodeproj
```

## Notes

Personal project for public board APIs. Follow each site’s terms and the law where you are. Don’t commit API keys or cookies.
