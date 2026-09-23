//
//  FileOperationsService.swift
//  DiskTracker
//
//  Safe file operations with sandbox-friendly fallbacks.
//  Enforces system path protection at the service level.
//

import Foundation
import AppKit

/// Errors that can occur during file operations.
enum FileOperationError: Error, Sendable {
    case invalidURL
    case systemPathProtected
    case deletionFailed(underlying: Error)
}

/// Provides trash, Finder reveal, and Quick Look functionality.
/// Enforces system path protection at the service level.
final class FileOperationsService: @unchecked Sendable {

    // Singleton
    static let shared = FileOperationsService()

    /// Paths that are protected from deletion/modification. Every `Library`
    /// folder is protected by name as well, below.
    private let protectedPaths: Set<String> = [
        "/", "/System", "/usr", "/bin", "/sbin", "/lib", "/lib64",
        "/opt", "/private", "/dev", "/Volumes", "/Network",
        "/Applications", "/Users/Guest", "/System/Volumes",
    ]

    /// The app's own sandbox container. It sits under ~/Library but holds only
    /// this app's data, so the Library rule does not apply to it. Nil when not
    /// sandboxed: there `NSHomeDirectory()` is the real home, and exempting it
    /// would unprotect ~/Library.
    private let ownContainer: String? =
        NSHomeDirectory() == ScopedAccess.realHome ? nil : NSHomeDirectory()

    // MARK: - System Path Protection

    /// Returns true if the given URL points to a system-protected path.
    func isSystemProtected(url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let path = url.resolvingSymlinksInPath().path

        // Check if the path or any of its ancestors is protected
        for protected in protectedPaths {
            if path == protected || path.hasPrefix(protected + "/") {
                return true
            }
        }

        // Nothing in or under any Library folder — ~/Library, /Library, or one
        // nested anywhere. Apps keep live state there; the user deletes it in
        // Finder if they are sure. Case-insensitive, like the default volume.
        if let own = ownContainer, path == own || path.hasPrefix(own + "/") {
            return false
        }
        return URL(fileURLWithPath: path).pathComponents
            .contains { $0.caseInsensitiveCompare("Library") == .orderedSame }
    }

    // MARK: - Trash / Deletion

    /// Move a single file or directory to trash.
    /// Returns `.failure(.systemPathProtected)` if the path is protected.
    func moveToTrash(url: URL) -> Result<Void, FileOperationError> {
        guard url.isFileURL else {
            return .failure(.invalidURL)
        }
        guard !isSystemProtected(url: url) else {
            return .failure(.systemPathProtected)
        }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return .success(())
        } catch {
            return .failure(.deletionFailed(underlying: error))
        }
    }

    // MARK: - Finder / Reveal

    /// Open Finder with the file pre-selected.
    func showInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Open

    /// Hand the file to its default application.
    ///
    /// This was called `previewWithQuickLook`, which it never was — opening a
    /// 2GB video in an editor is not a preview. Real Quick Look lives in
    /// `QuickLookPreview`.
    func openInDefaultApp(url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - Batch Trash

    /// Move multiple files/directories to trash, returning per-item results.
    /// Protected paths return `.systemPathProtected`; valid paths return `.success`
    /// or `.deletionFailed`.
    func moveMultipleToTrash(urls: [URL]) -> [(url: URL, result: Result<Void, FileOperationError>)] {
        urls.map { url in
            let result = moveToTrash(url: url)
            return (url: url, result: result)
        }
    }
}
