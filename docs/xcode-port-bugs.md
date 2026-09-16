# Xcode port bugs (review 2026-09-03)

Findings from the A–D port review vs `docs/xcode-port-from-qt-plan.md`.  
Status: `open` → `fixed` as patches land.

---

## Critical

| ID | Status | Area | Issue |
|----|--------|------|-------|
| C1 | **fixed** | Downloads / sandbox | Security scope retained by `DownloadStore` for async directory writes. |

---

## High

| ID | Status | Area | Issue |
|----|--------|------|-------|
| H1 | **fixed** | Settings / sandbox | Security-scoped bookmark for download folder. |
| H2 | **fixed** | Selection / Favorites | Clear selection only after folder-picker confirm. |
| H3 | **fixed** | Selection / Favorites | No silent wipe when all already favorited. |
| H4 | **fixed** | Selection / Downloads | iOS Save As keeps selection until successful pick. |
| H5 | **fixed** | Selection | iPad ⌘/Ctrl via `GCKeyboard`. |

---

## Medium

| ID | Status | Area | Issue |
|----|--------|------|-------|
| M1 | **fixed** | Downloads UI | Indeterminate `ProgressView` + “Downloading…” while running. |
| M2 | **fixed** | Downloads | `activeIDs` cleared on finish — re-enqueue allowed during success toast. |
| M3 | **fixed** | Photos | Video extensions use `PHAssetResourceType.video`. |
| M4 | **fixed** | Downloads | Original only (`fileURL`); missing → `missingOriginal` error. |
| M5 | **fixed** | Viewer | Selection checkbox no longer gated on `showChrome`. |
| M6 | **fixed** | Favorites | `allowMove` + context “Move to Folder…”; batch Favorites moves too. |
| M7 | **fixed** | Keyboard | iPad F/⌘A via `GCKeyboard` physical keys. |
| M8 | **fixed** | Keyboard / focus | Grid no longer steals focus on appear; restores after peek/gallery. |
| M9 | **fixed** | Keyboard | `⌘A` with empty visibility selects keyboard cursor only. |
| M10 | **fixed** | Settings iOS | `fileImporter` for Choose Folder. |
| M11 | **fixed** | Save As | Peek/Viewer/context/action bar all go through `DownloadStore`. |
| M12 | **fixed** | Favorites | `activeFolderID` persisted separately from `lastFolderID`. |
| M13 | **fixed** | Migration | Legacy keys cleared; remigrate if empty entries + legacy remain; interleaved order. |
| M14 | **fixed** | Observation | `ColumnsMasonryGallery` equatable includes `selectionRevision`. |
| M15 | **fixed** | Wiring | Chrome / cells / Peek use `@Environment(SelectionStore)` (+ Download in chrome). |

---

## Low

| ID | Status | Area | Issue |
|----|--------|------|-------|
| L1 | **fixed** | Selection UI | Remove by `globalID`. |
| L2 | **fixed** | Keyboard | Esc ignored when selection empty. |
| L3 | **fixed** | Downloads UI | Download button uses primary (red only on failure). |
| L4 | **fixed** | Open on site | `pageURL` scheme follows media URL (`http` custom hosts). |
| L5 | **fixed** | Docs | `qt-vs-xcode-features.md` updated for ported parity. |
| L6 | **fixed** | VM | Removed redundant `favoritesRevision`. |

---

## Fix priority

1. ~~**C1 + H1** — security scope + bookmark~~ ✅  
2. ~~**H2 + H3 + H4** — selection clear timing~~ ✅  
3. ~~**H5** — iPad ⌘/Ctrl~~ ✅  
4. ~~**Mediums + lows**~~ ✅
