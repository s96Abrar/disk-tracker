//
//  DiskTrackerApp.swift
//  DiskTracker
//
//

import SwiftUI
import AppKit

@main
struct DiskTrackerApp: App {
    @StateObject private var appModel = AppModel()

    /// Root-level gate: when true, the welcome screen is presented instead of
    /// the main `ContentView`. Toggled off the moment the user starts a scan
    /// or explicitly closes the welcome screen via Settings.
    @State private var showingOnboarding: Bool = OnboardingSettings.showAtLaunch

    /// Set up the runtime listener that lets Settings re-trigger onboarding
    /// without restarting the app.
    init() {
        NotificationCenter.default.addObserver(
            forName: .diskTrackerRequestShowOnboarding,
            object: nil,
            queue: .main
        ) { _ in
            // Dispatch onto the main actor for @State mutation.
            DispatchQueue.main.async {
                OnboardingSettings.showAtLaunch = true
                DiskTrackerApp.requestOnboardingPresentation?()
            }
        }
    }

    /// Closure set by `rootView.onAppear` so the app shell can flip the
    /// `showingOnboarding` state from outside its view hierarchy.
    static var requestOnboardingPresentation: (() -> Void)?

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(appModel)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentSize)

        // Settings scene — exposes the "Show welcome screen at launch" toggle.
        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }

    @ViewBuilder
    private var rootView: some View {
        if showingOnboarding {
            OnboardingView { _ in
                // "Start Scan" / "Choose Folder…" both dismiss onboarding and
                // hand the user over to the main window with a folder picker.
                showingOnboarding = false
                // Defer the picker until after ContentView has appeared so the
                // open panel attaches to the right window.
                DispatchQueue.main.async {
                    presentFolderPickerAndStartScan()
                }
            }
            .onAppear {
                // Make sure the onboarding window is large enough.
                NSApp.windows.first?
                    .setContentSize(NSSize(width: 900, height: 600))
                // Expose a hook so the notification observer can flip us back
                // to onboarding from Settings → "Show Welcome Screen Now".
                DiskTrackerApp.requestOnboardingPresentation = {
                    showingOnboarding = true
                }
            }
        } else {
            ContentView()
                .onAppear {
                    DiskTrackerApp.requestOnboardingPresentation = {
                        showingOnboarding = true
                    }
                }
        }
    }

    /// Opens an `NSOpenPanel` for a directory and, on selection, kicks off
    /// a scan. Mirrors the folder-picker flow already used in the toolbar.
    private func presentFolderPickerAndStartScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Select Folder to Scan"
        panel.message = "Choose a directory to analyze with Disk Tracker"
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url {
            appModel.startScan(path: url.path)
        }
    }
}
