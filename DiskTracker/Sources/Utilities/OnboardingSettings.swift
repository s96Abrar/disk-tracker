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
