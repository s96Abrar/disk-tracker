# Mac App Store listing (draft)

Text for App Store Connect, kept here so it is reviewed like code and stays in
step with what the app does. Field limits are Apple's; the lengths shown were
counted, not estimated.

## Listing

| Field | Value |
|---|---|
| Name (≤30) | Disk Tracker (check availability; fall back to "Disk Tracker – Space Analyzer") |
| Subtitle (≤30, 30) | See where your disk space went |
| Category | Utilities (matches `LSApplicationCategoryType`) |
| Privacy policy URL | https://github.com/s96Abrar/disk-tracker/blob/main/PRIVACY.md |
| Support URL | https://github.com/s96Abrar/disk-tracker/issues |
| Age rating | 4+ (no objectionable content) |
| Price | Free |

**Promotional text (≤170, 158):**
Scan a folder or a whole disk and see what fills it, as a sunburst, a treemap
or a list. Find the large, old and duplicate files, then move them to the Trash.

**Keywords (≤100, 98):**
`disk space,storage,analyzer,treemap,sunburst,duplicate,large files,cleanup,xcode,deriveddata,cache`

**Description:**

> Disk Tracker finds out where your disk space went, and helps you get it back.
>
> Choose a folder or a whole disk. Disk Tracker walks it in seconds — a million
> files in under two — and shows the result three ways: a sunburst, a treemap,
> or a sortable list. Click into the folders that are actually large, press
> Space to Quick Look a file, and move what you don't need to the Trash.
>
> • Sizes are the space actually used on disk, the same number Finder reports.
> • Smart filters: large files, old files, empty folders, duplicates (compared
>   by content), oversized app bundles.
> • Developer caches: see how much Xcode, the Simulator, Homebrew, npm, pip,
>   Cargo, Gradle and Android caches take, with each tool's own cleanup command.
> • Every deletion is confirmed and goes to the Trash. Anything inside a Library
>   folder or a system location is refused.
> • Past scans reopen from history without rescanning. Export a scan as JSON or CSV.
> • A free-space warning at the level you choose.
>
> Private by design: no network access, no analytics, no accounts. Nothing
> leaves your Mac.

## App Review notes

> Disk Tracker is a disk space analyzer. It is sandboxed and has no network
> entitlement.
>
> **Folder access.** The sandbox lets the app read most folders, but it can only
> delete inside folders the user picked in an open panel. Choose Folder… and
> the one-time Home prompt both use `NSOpenPanel`, and the app keeps
> security-scoped bookmarks so those folders reopen after a restart. There are
> no temporary-exception entitlements.
>
> **Helper executable.** `Contents/MacOS/disk-tracker-engine` is the app's own
> scanner, written in Rust and launched as a subprocess for crash isolation. It
> is signed with `app-sandbox` + `inherit` and runs in the app's sandbox. The
> app launches nothing else.
>
> **To test:** click Choose Folder…, pick any folder, and the results appear in
> a few seconds. Right-click a file → Move to Trash asks for confirmation first.
> Developer Caches (sidebar) asks once for the home folder and then lists cache
> sizes.

## Screenshots (to capture)

Mac screenshots must be 16:10 at one of 1280×800, 1440×900, 2560×1600 or
2880×1800. Up to ten; the first three matter most.

1. Sunburst of a home-folder scan, a large folder hovered.
2. Treemap of the same scan.
3. Smart filter "Large files" with a batch selected and the reclaim total.
4. Developer Caches sheet.
5. Dashboard with volumes and recent scans.
