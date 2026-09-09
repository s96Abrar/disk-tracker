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
        return panel.runModal() == .OK ? panel.url : nil
    }
}
