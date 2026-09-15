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

    /// Low-space warning threshold, as a percentage of the volume.
    @State private var lowSpaceThreshold: Double = LowSpaceSettings.thresholdPercent

    /// Folders every scan skips. Mirrored from `ExclusionSettings` on appear.
    @State private var excludedPaths: [String] = ExclusionSettings.paths

    /// Row selection in the exclusions list, so Remove knows its target.
    @State private var selectedExclusion: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            scanningTab
                .tabItem { Label("Scanning", systemImage: "magnifyingglass") }
        }
        .frame(width: 520, height: 360)
        .onAppear {
            // Re-sync from UserDefaults each time settings opens.
            showWelcomeAtLaunch = OnboardingSettings.showAtLaunch
            lowSpaceThreshold = LowSpaceSettings.thresholdPercent
            excludedPaths = ExclusionSettings.paths
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

            Section("Disk Space") {
                // Below 10% and 5% the monitor escalates to critical and
                // emergency regardless, so this only moves the first warning.
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $lowSpaceThreshold, in: 10...50, step: 5) {
                        Text("Warn below")
                    } minimumValueLabel: {
                        Text("10%").font(.caption)
                    } maximumValueLabel: {
                        Text("50%").font(.caption)
                    }
                    .onChange(of: lowSpaceThreshold) { _, newValue in
                        LowSpaceSettings.thresholdPercent = newValue
                        model.freeSpaceMonitor.thresholdPercent = newValue
                    }

                    Text("Warn when free space drops below \(Int(lowSpaceThreshold))% "
                         + "of the scanned volume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Scanning tab

private extension SettingsView {

    var scanningTab: some View {
        Form {
            Section("Excluded Folders") {
                Text("Scans skip these folders and everything inside them. "
                     + "System locations are always skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if excludedPaths.isEmpty {
                    Text("No folders excluded.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Spacing.xs)
                } else {
                    List(excludedPaths, id: \.self, selection: $selectedExclusion) { path in
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .help(path)
                    }
                    .frame(height: 120)
                }

                HStack {
                    Button {
                        guard let url = FolderPicker.chooseScanFolder() else { return }
                        ExclusionSettings.add(url.path)
                        excludedPaths = ExclusionSettings.paths
                    } label: {
                        Label("Add Folder…", systemImage: "plus")
                    }

                    Button {
                        guard let selected = selectedExclusion else { return }
                        ExclusionSettings.remove(selected)
                        excludedPaths = ExclusionSettings.paths
                        selectedExclusion = nil
                    } label: {
                        Label("Remove", systemImage: "minus")
                    }
                    .disabled(selectedExclusion == nil)

                    Spacer()
                }
            }

            Section("Scan History") {
                // Trees are what cost — roughly 294 bytes per scanned file, so
                // a million-file scan writes about 294MB.
                LabeledContent("Saved scans") {
                    Text("\(model.scanHistory.entries.count) of \(ScanHistoryService.maxHistoryCount)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Disk used by saved trees") {
                    Text(humanReadableBytes(model.scanHistory.treeDiskUsage))
                        .foregroundStyle(.secondary)
                }
                Text("Older scans stop being re-openable once saved trees pass "
                     + "\(humanReadableBytes(ScanHistoryService.treeDiskBudget)). "
                     + "Their entries stay in the list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
