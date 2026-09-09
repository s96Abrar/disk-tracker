//
//  SettingsView.swift
//  DiskTracker
//
//  Settings scene for Disk Tracker. Currently exposes the
//  "Show welcome screen at launch" toggle, backed by
//  `OnboardingSettings` (UserDefaults). A "Show Welcome Screen Now"
//  button lets the user re-open onboarding without restarting the app.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    /// Local toggle state, synced from `OnboardingSettings` on appear so the
    /// UI always reflects the persisted value.
    @State private var showWelcomeAtLaunch: Bool = OnboardingSettings.showAtLaunch

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 480, height: 240)
        .onAppear {
            // Re-sync from UserDefaults each time settings opens.
            showWelcomeAtLaunch = OnboardingSettings.showAtLaunch
        }
    }

    private var generalTab: some View {
        Form {
            Section("Welcome") {
                Toggle("Show welcome screen at launch", isOn: $showWelcomeAtLaunch)
                    .help("When enabled, Disk Tracker opens the onboarding screen on every launch until you turn it off.")
                    .onChange(of: showWelcomeAtLaunch) { _, newValue in
                        OnboardingSettings.showAtLaunch = newValue
                    }

                HStack {
                    Spacer()
                    Button("Show Welcome Screen Now") {
                        // Re-open onboarding immediately. We post a global
                        // notification so the running app shell can react
                        // without us holding a reference to its state here.
                        NotificationCenter.default.post(
                            name: .diskTrackerRequestShowOnboarding,
                            object: nil
                        )
                    }
                    .help("Re-open the welcome screen without restarting Disk Tracker.")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Notification

extension Notification.Name {
    /// Posted when the user clicks "Show Welcome Screen Now" in Settings.
    /// `DiskTrackerApp` listens for this and re-presents onboarding.
    static let diskTrackerRequestShowOnboarding = Notification.Name(
        "DiskTracker.RequestShowOnboarding"
    )
}
