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
