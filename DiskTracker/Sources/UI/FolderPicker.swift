//
//  FolderPicker.swift
//  DiskTracker
//
//  One directory-chooser panel. The Dashboard hero, the Scan Results
//  toolbar/empty state, and the onboarding "Start Scan" button each had their
//  own byte-identical copy of this NSOpenPanel setup.
//

import AppKit

enum FolderPicker {
    /// Prompts for a directory. Returns nil when the user cancels.
    /// Must be called on the main thread — `runModal()` is blocking.
    static func chooseScanFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Select Folder to Scan"
        panel.message = "Choose a directory to analyze with Disk Tracker"
        panel.prompt = "Scan"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        // Bookmark now, while access is held: inside the sandbox the grant from
        // this panel ends with the launch, and a scan cannot be re-opened after
        // a restart without one.
        ScopedAccess.remember(url)
        return url
    }
}
