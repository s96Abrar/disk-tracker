//
//  OnboardingSettings.swift
//  DiskTracker
//
//  Persists the user's preference for whether the welcome screen
//  is shown at launch. Defaults to true (show) on first launch.
//

import Foundation
import SwiftUI

/// Wrapper around the `showOnboardingAtLaunch` UserDefaults key.
/// Centralises the key + default so views and `DiskTrackerApp` agree.
enum OnboardingSettings {
    private static let key = "DiskTracker.showOnboardingAtLaunch"

    /// Default: show the welcome screen on the very first launch.
    /// After that, the user's choice is honoured.
    static var showAtLaunch: Bool {
        get {
            // UserDefaults.bool returns false when the key is missing.
            // We need a tri-state distinction (never-set vs explicitly false),
            // so probe object(forKey:) first.
            if UserDefaults.standard.object(forKey: key) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }

    /// SwiftUI binding wrapper for use with `Toggle`.
    static var binding: Binding<Bool> {
        Binding(
            get: { showAtLaunch },
            set: { showAtLaunch = $0 }
        )
    }
}

// MARK: - Low space

/// Persisted low-space warning threshold.
///
/// Separate from `FreeSpaceMonitor.thresholdPercent`, which is the live value:
/// the monitor is rebuilt whenever a scan starts, so the user's choice has to
/// outlive it.
enum LowSpaceSettings {
    private static let key = "com.disktracker.lowSpaceThresholdPercent"

    /// Percentage of the volume below which the banner appears. Default 20%.
    static var thresholdPercent: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: key)
            // `double(forKey:)` returns 0 for an unset key, which would warn
            // constantly rather than never.
            return stored > 0 ? stored : 20
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Exclusions

/// Folders the user has asked every scan to skip.
///
/// `ScanConfig.excludeSystemPaths` already covers the system tree; this is the
/// user-defined half, which had no storage and no UI. Typical use is a backup
/// folder or a network mount that would otherwise dominate every scan.
enum ExclusionSettings {
    private static let key = "com.disktracker.excludedPaths"

    static var paths: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set {
            // Deduplicate and drop empties: the picker can return the same
            // folder twice, and an empty path would exclude nothing while
            // still occupying a row.
            let cleaned = Array(Set(newValue.filter { !$0.isEmpty })).sorted()
            UserDefaults.standard.set(cleaned, forKey: key)
        }
    }

    static func add(_ path: String) {
        paths = paths + [path]
    }

    static func remove(_ path: String) {
        paths = paths.filter { $0 != path }
    }
}
