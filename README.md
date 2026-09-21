<img src="DiskTracker/Sources/Assets.xcassets/AppIcon.appiconset/icon_128x128%402x.png" width="128" alt="Disk Tracker icon">

# Disk Tracker

[![Tests](https://github.com/s96Abrar/disk-tracker/actions/workflows/tests.yml/badge.svg)](https://github.com/s96Abrar/disk-tracker/actions/workflows/tests.yml)
[![Core coverage](badges/coverage.svg)](#testing)
[![Release](https://img.shields.io/github/v/release/s96Abrar/disk-tracker?sort=semver)](https://github.com/s96Abrar/disk-tracker/releases)
![Platform](https://img.shields.io/badge/macOS-15.0%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![Rust](https://img.shields.io/badge/Rust-stable-orange)

**Find out where your disk space went, then get it back.**

Disk Tracker scans a local folder or volume and shows the result as a sunburst,
a treemap, or a list. Click through to the folders that are actually large,
preview a file to check what it is, and move it to the Trash without leaving the
app.

A scan of a million files takes **1.8 seconds** and **164 MB** of memory.

> **v0.1 is the first shareable build.** It does local disks only. Network
> volumes, drive health, APFS snapshot management and background scanning are
> deliberately out of scope — see [Roadmap](#roadmap).

---

## Install

Download the DMG from [Releases](https://github.com/s96Abrar/disk-tracker/releases),
then:

1. Drag **Disk Tracker** to Applications.
2. Run this once in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/DiskTracker.app
   ```
3. Open it normally.

**Why step 2 is necessary.** This build is ad-hoc signed, not notarized. Apple
notarization requires a paid Developer Program membership, which this project
does not have. The command clears the "downloaded from the internet" flag on
this one app; it does not disable Gatekeeper system-wide, and the app's
signature stays intact and verifiable.

> Right-click → Open does **not** work for ad-hoc signed apps on Apple Silicon.
> The `xattr` command is required. If that trade-off isn't acceptable, build
> from source — the instructions are below and the result is identical.

**Requires macOS 15.0 or later.**

---

## What it does

| | |
|---|---|
| **Scan** | A local folder or a whole volume. Hidden files optional; folders you never want scanned can be excluded permanently. |
| **See** | Sunburst and treemap, both click-to-descend with a breadcrumb back. Or a sortable list. Hover for the path and size. |
| **Find** | Search by name, filter by category, or use smart filters: large files, old files, empty folders, duplicates (SHA-256), oversized app bundles. |
| **Delete** | Move to Trash, singly or in a batch, with a confirmation that states how much you'd actually reclaim. System paths are refused. |
| **Inspect** | Spacebar for Quick Look, exactly like Finder. |
| **Export** | The whole tree as JSON or CSV. |
| **Watch** | Live free-space readout, with a warning banner at a threshold you choose. |
| **Revisit** | Past scans re-open from history without re-scanning the disk. |

### What it deliberately does not do

- **Delete without asking.** Every removal is confirmed and goes to the Trash,
  never `unlink`. Protected system paths are refused outright.
- **Guess.** Sizes are the bytes actually allocated on disk
  (`ATTR_FILE_DATAALLOCSIZE`) — the same number `du` and Finder report, which
  means sparse files are reported honestly rather than at their nominal length.
- **Phone home.** No network code, no analytics. The app sandbox grants it
  nothing but the folders you pick.

---

## Performance

Every number below is produced by `./benchmark --full`, not estimated.

| Measurement | Target | Result |
|---|---|---|
| Scan 100K files | ≤ 3 s | **0.16 s** |
| Scan 1M files | ≤ 15 s | **1.81 s** |
| Memory, 100K files | — | 15.7 MB |
| Memory, 1M files | ≤ 300 MB | **164.1 MB** |
| Treemap layout, 50K children | ≤ 16.67 ms | **2.11 ms** |
| Sunburst layout, 50K children | ≤ 16.67 ms | **0.13 ms** |
| Cold launch to first frame | ≤ 2 s | **0.287 s** |

<sub>Apple M3 Pro, macOS 26.6.2. Regenerate with `./benchmark --full --markdown`.</sub>

Roughly **550,000 files per second** on a warm cache.

### Where the speed comes from

**`getattrlistbulk(2)`, not `stat()`.** One syscall returns metadata for a whole
batch of directory entries. The obvious alternative — `readdir` plus a `stat`
per file — costs one to two kernel transitions per file, and at a million files
that is the entire budget. Measured on a cold page cache, the bulk path scans
100K files in 1.48 s where the per-entry path takes 3.36 s.

**Rayon work-stealing, not recursion.** Subdirectories are pushed onto a shared
queue rather than recursed into. `node_modules` can nest fifty levels deep, and
recursive spawning burns a stack frame per level while leaving cores idle on an
unbalanced tree.

**A flat binary buffer, not JSON.** The engine is a subprocess; results cross as
a packed 56-byte-per-record buffer plus a string table. The same data as JSON is
about **2.8× larger** — at a million files that is roughly 175 MB of text to
serialize, pipe and reparse, against a 300 MB budget for the entire scan.

**Sub-pixel marks are never laid out.** A folder with 200,000 immediate children
would otherwise produce 200,000 tiles, almost all below one pixel. Both
visualizations cut by pixel budget before layout, so cost tracks what is on
screen rather than what was scanned.

### The honest gap

Frame rate under live interaction has **not** been measured end to end. The
figures above are layout cost in a Release build, which is the CPU half and the
half that regresses; actual fps also depends on the GPU, the display link and
the compositor. What is proven: layout leaves **87%** of the 60 fps frame budget
unused at 50,000 children.

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   Disk Tracker.app                       │
├────────────────────────────┬─────────────────────────────┤
│  SwiftUI                   │  Rust engine (subprocess)   │
│  · Canvas visualizations   │  · getattrlistbulk(2)       │
│  · Trash / Finder / QL     │  · Rayon work-stealing      │
│  · @Observable state       │  · flat FileRecord buffer   │
└────────────────────────────┴─────────────────────────────┘
         stdout: binary scan buffer · stderr: progress
```

The engine ships at `Contents/Resources/disk-tracker-engine`. It has to live
inside the bundle — the App Sandbox refuses to launch anything outside it.

**Why a subprocess rather than an in-process FFI.** A traversal engine walks
whatever a user points it at, so a crash on a malformed volume takes down a
child process instead of the app. The cost is one pipe copy of about 62 MB per
million files, comfortably inside budget.

| Where | What |
|---|---|
| `traversal-engine/src/` | Scanner, directory walker, wire format |
| `DiskTracker/Sources/Core/` | Scan transport, app state, domain services |
| `DiskTracker/Sources/UI/` | Views and visualizations |

---

## Build from source

Requires Xcode 16+ and a stable Rust toolchain.

```bash
git clone https://github.com/s96Abrar/disk-tracker.git
cd disk-tracker

./build-disk-tracker            # engine + app (Debug)
./build-disk-tracker --rust     # engine only
./build-disk-tracker --swift    # app only
./build-disk-tracker --clean

./package-release               # Release build, verified, into a DMG
./package-release --verify      # same checks, no DMG
```

`package-release` refuses to hand you a broken DMG: it checks the engine is
inside the bundle, the version matches the source, the signature is valid and
hardened, the nested engine binary is signed, the sandbox entitlements are
present — and then mounts the finished image and verifies it again.

### Testing

```bash
cd traversal-engine && cargo test --release    # 27 unit + 4 perf + 3 scale

xcodebuild test -project DiskTracker/DiskTracker.xcodeproj \
  -scheme DiskTracker -destination 'platform=macOS'        # 349 tests

./check-coverage                # per-file coverage, fails under target
./benchmark                     # performance targets
./measure-launch                # cold launch, process exec to first frame
```

**Core coverage is 87.8%**, against a >80% target on the scanner, the domain
algorithms and the state machines.

Whole-app coverage is 34.6%, and that number is not the target — it averages in
SwiftUI view bodies, which this project does not unit test. A single app-wide
figure would mostly measure how much UI code exists. `./check-coverage` checks
the files the target actually names.

### Deferred code

Five services are kept in the tree but gated behind `DISKTRACKER_V05`, so they
compile to nothing in a v0.1 build:

```bash
./build-disk-tracker --v05      # compile and test the gated code
```

They are kept rather than deleted because they work and are tested. They are
gated rather than shipped because code in a binary that nothing calls reads as
finished work. CI compiles them on every run — a `#if` block is invisible to the
compiler, so gated code otherwise rots silently while still looking alive.

---

## Roadmap

v0.1 is local disk scanning, and stops there on purpose.

| Deferred | Blocked on |
|---|---|
| Network volumes (SMB/AFP/NFS) | Its own traversal strategy; latency and mount loss differ in kind |
| S.M.A.R.T. drive health | Adjacent product, not a disk-usage feature |
| APFS snapshot deletion | A privileged helper, which needs Developer ID |
| Notarized DMG, Sparkle updates | Apple Developer Program membership ($99/yr) |
| FSEvents live updates, background scans | Durable scan storage to diff against |
| APFS clone reporting | Extent-identity tracking |
| Incremental scanning, hard-link dedup | — |

**On APFS clones:** two clones of a 3 MB file are reported as 3 MB each, not
once. `du` and Finder agree. Reporting shared extents once is a real feature,
not a rounding decision, and it is deferred.

---

## License

MIT — see [LICENSE](LICENSE).
