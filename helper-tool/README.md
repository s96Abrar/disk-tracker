# DiskTracker Privileged Helper Tool

This directory contains the SMAppService-based privileged helper that runs as root and exposes NSXPC endpoints for file-system operations the sandboxed DiskTracker app cannot perform directly.

## Role in Architecture

The main DiskTracker app (`com.disktracker.app`) is sandboxed. It can scan user-visible directories, but it **cannot**:

1. Delete SIP-protected files or files behind TCC restrictions (e.g. Reminders data, Mail downloads).
2. List or delete APFS Time Machine local snapshots (requires root).
3. Recursively scan system directories such as `/System/Volumes/Data/private/var` or `/usr/local`.

The helper tool (`com.disktracker.helper`) fills that gap. It is an XPC service launched on-demand by `launchd`, runs with root privileges, and exposes a single `DiskTrackerHelperProtocol` interface over NSXPC.

## File Layout

```
helper-tool/
  Sources/
    main.swift                — Entry point, NSXPCListener, protocol impl, code-sign verification
    APFSSnapshotManager.swift — tmutil wrapper for listing/deleting APFS snapshots
  Info.plist                  — Bundle metadata, MachServices, SMAuthorizedClients
```

## NSXPC Protocol

```swift
@objc protocol DiskTrackerHelperProtocol {
    func listAPFSSnapshots(forPath: String, withReply: @escaping ([[String: Any]]?, Error?) -> Void)
    func deleteAPFSSnapshot(named: String, forPath: String, withReply: @escaping (Bool, Error?) -> Void)
    func deleteProtectedFile(at path: String, withReply: @escaping (Bool, Error?) -> Void)
    func scanDirectory(at path: String, withReply: @escaping ([[String: Any]]?, Error?) -> Void)
}
```

All methods are fully asynchronous (reply-block based) so the main-app UI never blocks.

## How the Main App Connects

1. **Registration** — On first launch (or via Settings), the main app calls:
   ```swift
   let service = SMAppService.daemon(plistName: "com.disktracker.helper.plist")
   try service.register()
   ```
   This copies the helper binary and its embedded launchd plist into `/Library/PrivilegedHelperTools/`, prompting the user for admin credentials via a system dialog.

2. **Connection** — The main app creates an `NSXPCConnection` targeted at the Mach service:
   ```swift
   let connection = NSXPCConnection(machServiceName: "com.disktracker.helper")
   connection.remoteObjectInterface = NSXPCInterface(with: DiskTrackerHelperProtocol.self)
   connection.resume()
   ```

3. **Authorization Check** — When a connection arrives, the helper validates the caller's code signature in `NSXPCListenerDelegate.shouldAcceptNewConnection:` using `SecCodeCopyGuestWithAttributes` + `SecCodeCheckValidity` against the `SMAuthorizedClients` requirement string.

4. **Teardown** — The connection is invalidated when the app terminates or explicitly calls `connection.invalidate()`.

## Security Model

- The helper is a **LaunchDaemon**, not a LaunchAgent, so it runs as root in the system bootstrap namespace.
- `SMAuthorizedClients` restricts connections to the DiskTracker app bundle only. In production, tighten the requirement string with your Apple Developer Team ID.
- The helper uses `os.log` for all operations, making activity auditable via Console.app.
- XPC messages are bounded (e.g. directory scan caps at 50,000 entries) to avoid memory pressure and message-size limits.

## Building

The helper is built as a command-line Swift executable and then packaged into the main app's bundle under `Contents/Library/LaunchDaemons/` so that `SMAppService` can install it at runtime.

Typical Xcode build integration:
1. Add a new **Command Line Tool** target named `DiskTrackerHelper`.
2. Set its `PRODUCT_BUNDLE_IDENTIFIER` to `com.disktracker.helper`.
3. Add the source files and Info.plist to the target.
4. Embed the resulting binary into the main app's `Contents/Library/LaunchDaemons/` via a Copy Files build phase.

## macOS Version

Minimum: **macOS Sequoia 15.0+** (matches the main app).
