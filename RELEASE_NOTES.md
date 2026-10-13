# Disk Tracker v0.1.4 — Find the 40 GB you forgot about

## What's new in v0.1.4

**The list and the chart, side by side.** Scan results now show the list and the chart together instead of one at a time. Drag the divider between them to resize. Switch the chart between **Sunburst** and **Treemap** with the toggle above it.

Both sides always show the same folder. Click into a folder in the chart, or double-click one in the list, and the other side follows. The path bar above both takes you back up, and so does ⌘↑. Switching between Sunburst and Treemap keeps your place, and deleting something no longer sends you back to the top folder.

**Categories ranked by size.** The sidebar now shows how much space each kind of file takes — Images, Videos, Documents, Applications, Archives, Other — with a bar for its share of the scan. It used to show how many files there were, which put thousands of tiny files ahead of one huge disk image. Hover over a category to see the count.

## Installing

1. Open `DiskTracker-v0.1.4.dmg` and drag **Disk Tracker** to Applications.
2. Run this once in Terminal:
   ```
   xattr -dr com.apple.quarantine /Applications/DiskTracker.app
   ```
3. Open it normally.

Step 2 is required because this build is **ad-hoc signed rather than
notarized** — Apple notarization needs a paid Developer Program membership.
The command clears the "downloaded from the internet" flag on this app only;
it does not disable Gatekeeper system-wide, and the signature stays valid.

> Right-click → Open does **not** work for ad-hoc signed apps on Apple
> Silicon. The `xattr` command is required.

**Requires macOS 15.0 or later.**

---

# Disk Tracker v0.1.3 — Find the 40 GB you forgot about

## What's new in v0.1.3

**Fixes.**
- Move to Trash works again. Selected files and folders were reported as "not found" because the app was looking for them in the wrong place. Show in Finder, Open and Quick Look had the same problem and work again too.

Scans saved in History before this version still point to the wrong place. Rescan a folder before deleting from it.

## Installing

1. Open `DiskTracker-v0.1.3.dmg` and drag **Disk Tracker** to Applications.
2. Run this once in Terminal:
   ```
   xattr -dr com.apple.quarantine /Applications/DiskTracker.app
   ```
3. Open it normally.

Step 2 is required because this build is **ad-hoc signed rather than
notarized** — Apple notarization needs a paid Developer Program membership.
The command clears the "downloaded from the internet" flag on this app only;
it does not disable Gatekeeper system-wide, and the signature stays valid.

> Right-click → Open does **not** work for ad-hoc signed apps on Apple
> Silicon. The `xattr` command is required.

**Requires macOS 15.0 or later.**

---

# Disk Tracker v0.1.2 — Find the 40 GB you forgot about

## What's new in v0.1.2

**Developer Caches.** A new sidebar entry that measures the caches your dev tools leave behind — Xcode (DerivedData, device support, archives), the Simulator, Homebrew, npm/Yarn/pnpm, pip, Cargo, Gradle and Android — with one bar showing which tool takes the most. The caches in your home folder's hidden folders (npm, Cargo, Gradle, Android) can go straight to the Trash; for the rest, each row shows the tool's own cleanup command, ready to copy. It asks once for access to your home folder.

**A new icon for macOS 26.** The icon is now a Liquid Glass icon that follows macOS 26's light, dark, clear and tinted styles. macOS 15 gets the same design, flattened.

**Fixes.**
- **Home** now scans your home folder. It used to scan the app's own sandbox folder instead.
- Move to Trash works on scans reopened from History after a restart.
- Nothing inside a **Library** folder can be moved to the Trash any more — apps keep live data there. Those items point you to Show in Finder instead.
- When macOS won't let the app delete from a folder you didn't choose, the message now says how to fix it: open the folder with **Choose Folder…**.
- In full screen, the sidebar stays at the left edge instead of drifting toward the middle.
- The welcome screen no longer draws a second, fake window inside the real one.
- Scans no longer wait behind low-priority background work.

**Privacy and security.**
- Release builds no longer allow a debugger to attach to the app. Earlier builds did.
- The scan engine is now sandboxed in its own right and runs inside the app's sandbox.
- A privacy manifest and a [privacy policy](https://github.com/s96Abrar/disk-tracker/blob/main/PRIVACY.md): nothing leaves your Mac.

## Installing

1. Open `DiskTracker-v0.1.2.dmg` and drag **Disk Tracker** to Applications.
2. Run this once in Terminal:
   ```
   xattr -dr com.apple.quarantine /Applications/DiskTracker.app
   ```
3. Open it normally.

Step 2 is required because this build is **ad-hoc signed rather than
notarized** — Apple notarization needs a paid Developer Program membership.
The command clears the "downloaded from the internet" flag on this app only;
it does not disable Gatekeeper system-wide, and the signature stays valid.

> Right-click → Open does **not** work for ad-hoc signed apps on Apple
> Silicon. The `xattr` command is required.

**Requires macOS 15.0 or later.**

---

# Disk Tracker v0.1.1 — Find the 40 GB you forgot about

## What's new in v0.1.1

**App Icon.** The app now displays a custom icon instead of a blank placeholder. The icon is a squircle in brand indigo carrying a treemap of blocks, with one green for reclaimable space. Generated from code at each native resolution to stay readable at all sizes.

**UI Fixes.**
- Low-space alerts now correctly name the containing **volume** (e.g., "Macintosh HD") instead of the scanned folder
- Recent Scans timestamps show relative time once ("2 hours ago") instead of a live clock that redraws every second
- Welcome screen status bar displays the last scanned path instead of showing the untouched default

---

# Disk Tracker v0.1.0 — Find the 40 GB you forgot about

Point it at a folder or a whole volume. It scans a million files in under two
seconds, draws you a map of where the space went, and lets you delete the
offenders without leaving the app.

## Installing

1. Open `DiskTracker-v0.1.0.dmg` and drag **Disk Tracker** to Applications.
2. Run this once in Terminal:
   ```
   xattr -dr com.apple.quarantine /Applications/DiskTracker.app
   ```
3. Open it normally.

Step 2 is required because this build is **ad-hoc signed rather than
notarized** — Apple notarization needs a paid Developer Program membership.
The command clears the "downloaded from the internet" flag on this app only;
it does not disable Gatekeeper system-wide, and the signature stays valid.

> Right-click → Open does **not** work for ad-hoc signed apps on Apple
> Silicon. The `xattr` command is required.

**Requires macOS 15.0 or later.**

## What you get

- **Three ways to look at it** — sunburst, treemap and list, all click-to-descend
  with a breadcrumb to climb back out
- **Filters that find the junk for you** — large, old, empty, duplicate and
  oversized-bundle, plus search and category filters
- **Delete with your eyes open** — Move to Trash one item or a whole batch,
  after a confirmation that states what you'd actually reclaim; protected
  system paths are refused outright
- **Spacebar for Quick Look**, exactly like Finder
- **Export to JSON or CSV** when you want the numbers elsewhere
- **Live free-space readout** with a low-space warning you can set
- **Scan history** that re-opens a previous scan without walking the disk again

## Speed

| Measurement | Target | Result |
|---|---|---|
| Scan 1M files | ≤ 15 s | **1.81 s** |
| Memory, 1M files | ≤ 300 MB | **164.1 MB** |
| Cold launch to first frame | ≤ 2 s | **0.287 s** |

A Rust core walks the filesystem with `getattrlistbulk` and Rayon work-stealing;
SwiftUI draws the result on an immediate-mode Canvas. Apple M3 Pro, reproduce
with `./benchmark --full`.

## Known limits

- **Sizes are per-file, not per-extent.** Two APFS clones of one file are
  reported as two files. `du` and Finder agree; reporting shared storage once
  is a later feature.
- **Hard links are counted once per link**, so a file with several is
  over-counted.
- **Frame rate under live interaction is unmeasured.** Layout uses 12.7% of a
  60 fps frame at 50,000 children, but end-to-end fps has not been captured.
- **No auto-update.** Download the next DMG manually.
- Network volumes, S.M.A.R.T. and APFS snapshot management are out of scope
  for v0.1.
