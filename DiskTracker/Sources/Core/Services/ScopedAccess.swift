//
//  ScopedAccess.swift
//  DiskTracker
//
//  Security-scoped bookmarks for folders the user picked.
//
//  Inside the sandbox, choosing a folder in NSOpenPanel grants access to it for
//  that launch only. Without a bookmark, re-opening a scan from history or
//  re-scanning a remembered path silently returns nothing after a restart — the
//  entitlement is there, the grant is not.
//
//  Requires `com.apple.security.files.bookmarks.app-scope`, which is declared
//  in DiskTracker.entitlements.
//

import Foundation
import os

private let log = Logger(subsystem: "com.disktracker", category: "scoped-access")

/// Persists and re-establishes access to user-chosen folders.
enum ScopedAccess {

    /// Bookmarks keyed by the path they were created for.
    private static let defaultsKey = "com.disktracker.scopedBookmarks"

    /// An active access grant. Access is released when this is deallocated, so
    /// callers keep it alive for as long as they touch the folder rather than
    /// having to remember a matching `stopAccessing` call.
    final class Grant {
        private let url: URL
        fileprivate init(url: URL) { self.url = url }
        deinit { url.stopAccessingSecurityScopedResource() }
    }

    /// Records a folder the user just chose, so access survives relaunch.
    /// Called at pick time — a bookmark can only be minted while access is
    /// already held.
    static func remember(_ url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var all = storedBookmarks()
            all[url.path] = data
            UserDefaults.standard.set(all, forKey: defaultsKey)
        } catch {
            // Not fatal: the scan still works this launch, it just will not be
            // re-openable after a restart.
            log.error("could not bookmark \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-establishes access to a previously chosen folder.
    ///
    /// Returns nil when there is no bookmark, which is the normal case for a
    /// path the user reached some other way — a volume root, or the home
    /// directory the app can already read. Callers scan regardless; the grant
    /// only widens what is reachable.
    static func access(path: String) -> Grant? {
        guard let data = storedBookmarks()[path] else { return nil }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            forget(path: path)
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            log.error("bookmark for \(path, privacy: .public) resolved but access was refused")
            return nil
        }
        let grant = Grant(url: url)

        // A stale bookmark still resolves; refreshing it now — while access is
        // held — keeps it working after the folder is moved or renamed.
        if stale {
            remember(url)
        }
        return grant
    }

    /// Drops a bookmark that no longer resolves.
    static func forget(path: String) {
        var all = storedBookmarks()
        all.removeValue(forKey: path)
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }

    private static func storedBookmarks() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }
}
