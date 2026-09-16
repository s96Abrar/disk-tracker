# Disk Tracker — Claude Code Guidance

**Scope (v0.1):** scan a **local** folder or volume, show where the space went,
delete what you don't want. Network volumes, S.M.A.R.T., APFS snapshots, the
privileged helper, DuckDB, FSEvents and background scans are **deferred** —
`documents/5_FUTURE_TARGETS.md`.

**Reading Order (for AI agents):**
1. `documents/1_PROJECT_GUIDE.md` — Architecture, scan contract, data models
2. `documents/2_BUILD_PLAN.md` — Requirements, phase status, release checklist
3. `documents/3_STANDARDS.md` — Coding standards, testing, git workflow
4. `documents/4_COMPLETION_PLAN.md` — What's left before v0.1 ships
5. `documents/5_FUTURE_TARGETS.md` — Deferred features
6. `documents/market_research.md` — Competitive analysis (external reference)

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

**Performance** (measured 2026-09-15 — `2_BUILD_PLAN.md` §3):
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

cd traversal-engine && cargo test --release
xcodebuild test -project DiskTracker/DiskTracker.xcodeproj \
  -scheme DiskTracker -destination 'platform=macOS'

open -a "Disk Tracker"
```

Release build and DMG packaging: `documents/2_BUILD_PLAN.md` §4 (verified).

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
Finder do. Reporting shared extents once is deferred
(`documents/5_FUTURE_TARGETS.md` §2.2).

---

## Gotchas

- **Xcode 16 synchronized groups.** Adding or deleting a source file needs no
  `project.pbxproj` edit.
- **SF Symbol names are not validated at build time.** A wrong name renders a
  blank row. Several Material Design names survived from the HTML mock.
- **Deferred code is gated, not deleted.** Five services sit behind
  `#if DISKTRACKER_V05` and compile to nothing in a normal build; `helper-tool/`
  is not in the Xcode project at all. Build them with
  `./build-disk-tracker --v05`. A normal suite runs 349 tests, the gated one 376.
- **A passing test suite does not mean the code is reachable.** That gate exists
  because those services had full suites and zero callers, which reads as
  finished work.
- **`DiskNode` is a value type.** Build a child completely before appending it
  to its parent; appending copies.
- **Never interpolate a tree or scan result into a log line.** Interpolation is
  eager and will build a multi-GB string.

For technical detail, the scan contract, and the implementation checklist, see
the documents above.
