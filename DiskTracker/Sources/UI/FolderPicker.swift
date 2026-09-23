//
//  FolderPicker.swift
//  DiskTracker
//
//  The app's AppKit file panels.
//
//  The directory chooser is here because the Dashboard hero, the Scan Results
//  toolbar and empty state, and the onboarding "Start Scan" button each had
//  their own byte-identical copy of the same NSOpenPanel setup.
//

import AppKit

enum FolderPicker {
    /// Prompts for a directory. Returns nil when the user cancels.
    /// Must be called on the main thread — `runModal()` is blocking.
    @MainActor
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

    /// The real home folder, asking for access the first time. Nil when the
    /// user declines. Every "Home" shortcut goes through here.
    @MainActor
    static func homeFolder() -> String? {
        if ScopedAccess.access(path: ScopedAccess.realHome) != nil || grantHomeAccess() {
            return ScopedAccess.realHome
        }
        return nil
    }

    /// Asks for the real home folder.
    /// Returns false when the user cancels or picks another folder.
    @MainActor
    static func grantHomeAccess() -> Bool {
        let home = URL(fileURLWithPath: ScopedAccess.realHome, isDirectory: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = home
        panel.title = "Allow Access to Home Folder"
        panel.message = "Choose your home folder to let Disk Tracker scan it. You only need to do this once."
        panel.prompt = "Allow"
        guard panel.runModal() == .OK, let url = panel.url,
              url.standardizedFileURL.path == home.path else { return false }
        ScopedAccess.remember(url)
        return true
    }

    /// Prompts for where to write an export. Returns nil when the user cancels.
    ///
    /// Inside the sandbox the returned URL carries its own write grant for this
    /// launch, which is all an export needs — unlike a scan folder, there is
    /// nothing to re-open later, so no bookmark is kept.
    @MainActor
    static func chooseExportDestination(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        panel.title = "Export Scan"
        panel.message = "Choose where to save the scan report"
        panel.prompt = "Export"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
