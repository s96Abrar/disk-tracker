# Disk Tracker — Claude Code Guidance

**Scope (v0.1):** scan a **local** folder or volume, show where the space went,
delete what you don't want. Network volumes, S.M.A.R.T., APFS snapshots, the
privileged helper, DuckDB, FSEvents and background scans are **deferred**; the
Swift ones are gated behind `DISKTRACKER_V05`.

---

## Quick Start

**Architecture:** Hybrid Rust/Swift. The Rust core (`traversal-engine/`) walks
the filesystem with Rayon work-stealing. SwiftUI (`DiskTracker/`) renders
Canvas-based visualizations and owns file operations.

| Component | Location | Purpose |
|-----------|----------|---------|
| Rust scanner | `traversal-engine/src/` | Traversal, `FileRecord` array |
| Swift app | `DiskTracker/Sources/` | GUI, file operations |
| Engine binary | `Contents/Resources/disk-tracker-engine` | Sandbox forbids launching anything outside the bundle |

**Performance** (measured; regenerate with `./benchmark --full`):
1M files **1.74 s** / 215 MB against a 15 s / 300 MB budget · 100K in **0.11 s**.
60 fps and launch-to-window still need an Instruments pass.

**Constraints:**
- macOS 15.0+ (Sequoia), Swift 6.0 strict concurrency
- App Sandbox enabled; needs `files.user-selected.read-write` before Trash works
- **Ad-hoc signing only** — no paid Developer Program membership, so no
  notarization, no Sparkle, no privileged helper

---

## Common Commands

```bash
./build-disk-tracker           # Rust + Swift (Debug)
./build-disk-tracker --rust    # engine only; copies into DiskTracker/Binaries/
./build-disk-tracker --swift
./build-disk-tracker --clean

./make-icon                    # redraws the app icon asset catalog from code

cd traversal-engine && cargo test --release
xcodebuild test -project DiskTracker/DiskTracker.xcodeproj \
  -scheme DiskTracker -destination 'platform=macOS'

open -a "Disk Tracker"
```

Release build and DMG packaging: `./package-release`. Install steps for users
are in `RELEASE_NOTES.md`.

---

## Key Decisions

| Decision | Rationale | Status |
|---|---|---|
| `getattrlistbulk` over `stat()` | One kernel transition per batch | ✅ 2.3x faster cold-cache |
| Allocated size via `ATTR_FILE_DATAALLOCSIZE` | Matches what `du` and Finder report | ✅ |
| Rust for traversal | No ARC on millions of objects | ✅ |
| Immediate-mode Canvas | Declarative hierarchy stalls past ~1K nodes | ✅ |
| One scan transport | Two is a maintenance tax and a memory ceiling | ✅ subprocess + flat binary buffer |
| Ad-hoc signed DMG for v0.1 | No Developer Program membership | ✅ verified |

**APFS clones are counted once per clone, not once per shared extent.** The
original guide claimed `ATTR_FIL_ALLOCSIZE` deduplicated them; measurement says
otherwise — two clones of a 3MB file report 3MB each, exactly as `du` and
Finder do. Reporting shared extents once is deferred.

---

## Gotchas

- **Xcode 16 synchronized groups — app sources only.** A file under
  `DiskTracker/Sources/` needs no `project.pbxproj` edit. The test target is
  not synchronized: a new file in `Tests/DiskTrackerTests/` needs a build-file,
  file-reference, group and Sources-phase entry, or it silently never runs.
- **`NSHomeDirectory()` is the sandbox container**, not `~`. Use
  `ScopedAccess.realHome`, and reach it through `FolderPicker.homeFolder()` so
  the one-time grant is requested and bookmarked.
- **Nothing inside a `Library` folder goes to Trash.** `FileOperationsService`
  refuses any path with a `Library` component, at any depth. The app's own
  container is the one exception. Such items are measured only; the UI points
  to Finder.
- **Hosted tests do not enforce the App Sandbox** the way a normal launch does:
  from the test host the engine reads `~/.gradle`, which the real app cannot.
  Prove sandbox behavior in the launched app (`sandbox_check` on its pid).
- **SF Symbol names are not validated at build time.** A wrong name renders a
  blank row. Several Material Design names survived from the HTML mock.
- **Deferred code is gated, not deleted.** Five services sit behind
  `#if DISKTRACKER_V05` and compile to nothing in a normal build; `helper-tool/`
  is not in the Xcode project at all. Build them with
  `./build-disk-tracker --v05`. The gated suite runs 27 more tests than a normal
  one (350 and 377 at the time of writing).
- **A passing test suite does not mean the code is reachable.** That gate exists
  because those services had full suites and zero callers, which reads as
  finished work.
- **`DiskNode` is a value type.** Build a child completely before appending it
  to its parent; appending copies.
- **Never interpolate a tree or scan result into a log line.** Interpolation is
  eager and will build a multi-GB string.

The scan wire format is specified in `traversal-engine/src/wire.rs` and
mirrored in `DiskTracker/Sources/Core/Engine/ScanBuffer.swift`; both sides have
tests asserting the same byte offsets.
