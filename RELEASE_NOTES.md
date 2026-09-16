# Disk Tracker v0.1.0

First shareable build. Scans a local folder or volume, shows where the space
went, and lets you delete what you don't want.

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

## What's in it

- Sunburst, treemap and list views, all click-to-descend with a breadcrumb back
- Search, category filters, and smart filters for large, old, empty, duplicate
  and oversized-bundle items
- Move to Trash, singly or batched, with a confirmation stating what you'd
  actually reclaim; protected system paths are refused
- Quick Look on spacebar
- JSON and CSV export
- Live free-space readout with a configurable low-space warning
- Scan history that re-opens without re-scanning

## Performance

| Measurement | Target | Result |
|---|---|---|
| Scan 1M files | ≤ 15 s | **1.81 s** |
| Memory, 1M files | ≤ 300 MB | **164.1 MB** |
| Cold launch to first frame | ≤ 2 s | **0.287 s** |

Apple M3 Pro. Reproduce with `./benchmark --full`.

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
