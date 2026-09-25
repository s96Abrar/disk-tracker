# Privacy Policy

_Last updated: 2026-09-25_

Disk Tracker does not collect, transmit, or share any data. Everything it
reads and writes stays on your Mac.

## What the app reads

- **File and folder metadata:** names, sizes, modification dates and kinds of
  the files in the folders you scan. It needs these to show where your space
  went. It does not read what is inside a file, with two exceptions that you
  start yourself:
  - **Duplicate finder:** it hashes the contents of candidate files (SHA-256)
    to confirm they are identical.
  - **Quick Look:** macOS renders a preview of the file you selected.
- **Volume capacity and free space,** for the dashboard and the low-space
  warning.

## What the app stores

All of it is kept inside the app's own sandbox container:

- **Preferences:** excluded folders, the low-space threshold, whether the
  welcome screen appears.
- **Scan history:** the paths and results of past scans, so you can reopen them
  without scanning again.
- **Folder access bookmarks:** macOS security-scoped bookmarks for folders you
  chose, so the app can reopen them after a restart.

To erase scan history, use **History → Clear…** in the sidebar. To erase
everything, delete the app together with
`~/Library/Containers/com.disktracker.app`.

## What the app sends

Nothing. The app contains no networking code and no analytics, crash reporting
or advertising SDKs. It is not granted the network entitlement, so the macOS
sandbox would block a connection even if it tried.

## Deleting files

Files you remove go to the Trash, never straight to permanent deletion, and
only after you confirm. Nothing inside a `Library` folder or a system location
can be removed from the app.

## Contact

Questions about this policy:
[open an issue](https://github.com/s96Abrar/disk-tracker/issues).
