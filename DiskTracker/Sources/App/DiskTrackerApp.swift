//
//  DiskTrackerApp.swift
//  DiskTracker
//
//  App entry point. Owns the root `AppModel` and routes between the
//  three top-level phases:
//
//      onboarding ─┐
//                  ├─► dashboard ─► scanResults
//                  │       ▲           │
//                  └───────┴───────────┘  (back)
//
//  Routing is driven by `model.phase`. Folder-picker cancellation
//  falls back to dashboard (per spec).
//

import SwiftUI
import AppKit

@main
struct DiskTrackerApp: App {
    @State private var appModel = AppModel()

    /// Local copy of the pref so re-opening onboarding via Settings works
    /// without an extra hop through the model.
    @State private var showingOnboarding: Bool = OnboardingSettings.showAtLaunch

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(appModel)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowResizability(.contentSize)
        .commands { scanCommands }

        Settings {
            SettingsView()
                .environment(appModel)
        }
    }

    // MARK: - Menu commands

    /// File menu entries. `ExportService` and `AppModel.exportTree` were fully
    /// built and had no callers at all — nothing in the UI could reach them.
    @CommandsBuilder
    private var scanCommands: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder to Scan…") {
                presentFolderPickerAndStartScan()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(!appModel.canStartNewScan)

            Divider()

            Button("Export as JSON…") { export(.json) }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!canExport)

            Button("Export as CSV…") { export(.csv) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!canExport)
        }
    }

    private var canExport: Bool {
        appModel.rootNode != nil && !appModel.isExporting
    }

    /// Prompts for a destination, then writes off the main thread.
    ///
    /// Serializing a million-node tree produces a document hundreds of
    /// megabytes long; doing that inline would freeze the window mid-menu.
    private func export(_ format: AppModel.ExportFormat) {
        guard let url = FolderPicker.chooseExportDestination(
            defaultName: appModel.exportFileName(format: format)) else { return }

        appModel.writeExport(format: format, to: url) { error in
            guard let error else { return }
            // NSAlert rather than SwiftUI state: a menu command has no view to
            // hang a presentation modifier on.
            let alert = NSAlert()
            alert.messageText = "Couldn't export the scan"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Routing

    @ViewBuilder
    private var rootView: some View {
        // Onboarding wins over everything else while it's still pending.
        if showingOnboarding {
            OnboardingView(
                onStartScan: {
                    // User tapped "Start Scan" → folder picker; on success
                    // the model itself advances to .scanResults. On cancel
                    // we fall through to dashboard.
                    showingOnboarding = false
                    DispatchQueue.main.async {
                        let didStart = presentFolderPickerAndStartScan()
                        if !didStart {
                            // Cancellation → go to dashboard (per spec).
                            appModel.navigate(to: .dashboard)
                        }
                    }
                },
                onGoToDashboard: {
                    // User opted to skip the scan from onboarding → dashboard.
                    showingOnboarding = false
                    appModel.navigate(to: .dashboard)
                }
            )
        } else {
            // Sync the local pref with the model's phase so a manual
            // change persists if user later toggles via Settings.
            phaseRouter
                .onAppear {
                    if appModel.phase == .onboarding {
                        appModel.navigate(to: .dashboard)
                    }
                    // Monitoring used to start only once a scan finished, so a
                    // nearly-full disk went unmentioned on the screen whose job
                    // is to report disk health.
                    appModel.startFreeSpaceMonitoring(
                        for: URL(fileURLWithPath: appModel.currentScanPath))
                }
        }
    }

    @ViewBuilder
    private var phaseRouter: some View {
        switch appModel.phase {
        case .onboarding:
            // Defensive — rootView already handles the local flag above.
            Color.clear

        case .dashboard:
            DashboardView(model: appModel)

        case .scanResults:
            ScanResultsView(
                model: appModel,
                onBack: { appModel.navigate(to: .dashboard) }
            )
        }
    }

    // MARK: - Helpers

    /// Opens an `NSOpenPanel` for a directory and starts a scan on selection.
    /// Returns `true` when a scan was started, `false` on cancellation.
    @discardableResult
    private func presentFolderPickerAndStartScan() -> Bool {
        guard let url = FolderPicker.chooseScanFolder() else { return false }
        appModel.startScan(path: url.path)
        return true
    }

    // MARK: - Settings → "Show Welcome Screen Now" listener

    init() {
        NotificationCenter.default.addObserver(
            forName: .diskTrackerRequestShowOnboarding,
            object: nil,
            queue: .main
        ) { [self] _ in
            DispatchQueue.main.async {
                OnboardingSettings.showAtLaunch = true
                self.showingOnboarding = true
            }
        }
    }
}
