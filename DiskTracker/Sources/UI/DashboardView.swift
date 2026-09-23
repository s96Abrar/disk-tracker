//
//  DashboardView.swift
//  DiskTracker
//
//  Dashboard landing screen. Mirrors the HTML mock (DashboardView.txt):
//  sidebar (DashboardSidebar) + main area with hero card, volumes grid,
//  recent scans table, and bottom status bar.
//
//  Behavior:
//   - Tap a volume row → starts a scan (if no scan in flight).
//   - Tap a recent-scan row → restores that scan into Scan Results.
//   - "Choose Folder…" button in the hero opens NSOpenPanel.
//   - Settings button (in sidebar) → opens the system Settings scene.
//

import SwiftUI
import AppKit

struct DashboardView: View {
    var model: AppModel

    /// Full scan history, opened from the sidebar. Scrolling the main area to
    /// the Recent Scans card looked like a dead click whenever the dashboard
    /// already fit on screen.
    @State private var showingHistory = false
    @State private var showingDevCaches = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                DashboardSidebar(
                    model: model,
                    onShowHistory: { showingHistory = true },
                    onShowDevCaches: { showingDevCaches = true })

                mainArea
            }

            LowSpaceBanner(monitor: model.freeSpaceMonitor)

            // Persistent bottom status bar — also shown on Scan Results.
            StatusBar(model: model)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingHistory) {
            ScanHistorySheet(model: model, onClose: { showingHistory = false })
        }
        .sheet(isPresented: $showingDevCaches) {
            DevCachesSheet(model: model, onClose: { showingDevCaches = false })
        }
    }

    // MARK: - Main area

    private var mainArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                hero
                grid
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 760)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Glass-panel hero card with subtle gradient.
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                LinearGradient(
                    colors: [Color.brandAccent.opacity(0.10), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Welcome to Disk Tracker")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Monitor your storage health, visualize disk usage, and quickly free up space. Select a common path to scan instantly.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 480, alignment: .leading)

                    HStack(spacing: Spacing.sm) {
                        Button {
                            startScanWithFolderPicker()
                        } label: {
                            Label("Choose Folder…", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canStartNewScan)
                        .help("Select a directory to analyze")

                        Button {
                            guard model.canStartNewScan else { return }
                            model.startScan(path: NSHomeDirectory())
                        } label: {
                            Label("Scan Home", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canStartNewScan)
                    }
                    .padding(.top, Spacing.xs)
                }
                .padding(Spacing.lg)
            }
        }
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            // Left column — Volumes + Recent Scans.
            VStack(alignment: .leading, spacing: Spacing.lg) {
                volumesSection
                recentScansSection
            }
            .frame(maxWidth: .infinity)

            // Right column — Storage breakdown (free space indicator).
            breakdownSection
                .frame(width: 240)
        }
    }

    // MARK: - Sections

    private var volumesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader(icon: "internaldrive", title: "Volumes")
            volumesGrid
        }
    }

    private var volumesGrid: some View {
        let volumes = DiskVolumeService.mountedVolumes()
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Spacing.sm),
                      GridItem(.flexible(), spacing: Spacing.sm)],
            spacing: Spacing.sm
        ) {
            ForEach(volumes) { volume in
                VolumeCard(volume: volume) {
                    guard model.canStartNewScan else { return }
                    model.startScan(path: volume.url.path)
                }
            }
        }
    }

    private var recentScansSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader(icon: "clock.arrow.circlepath", title: "Recent Scans")

            if model.scanHistory.entries.isEmpty {
                emptyHistory
            } else {
                recentScansTable
            }
        }
    }

    private var emptyHistory: some View {
        EmptyState(icon: "tray", title: "No scans yet",
                   message: "Pick a folder or volume to begin.", compact: true)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
    }

    private var recentScansTable: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider().opacity(0.4)
            ForEach(Array(model.scanHistory.entries.enumerated()), id: \.element.id) { idx, entry in
                Button {
                    model.restoreScanFromHistory(entry)
                } label: {
                    tableRow(entry: entry, isLast: idx == model.scanHistory.entries.count - 1)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.2)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var tableHeader: some View {
        HStack {
            Text("DATE").headerStyle()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("PATH").headerStyle()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("SIZE").headerStyle()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    @ViewBuilder
    private func tableRow(entry: ScanHistoryEntry, isLast: Bool) -> some View {
        HStack {
            // `.relative` style counts seconds and redraws every tick, so the
            // column flickered "1 min, 4 sec / 1 min, 5 sec". One named unit,
            // rendered once: "1 minute ago", "yesterday".
            Text(entry.scanDate.formatted(.relative(presentation: .named)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.brandAccent)
                Text(entry.volumePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.brandAccent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(humanReadableBytes(entry.totalSize))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader(icon: "chart.pie", title: "Free Space")
            FreeSpaceIndicator(monitor: model.freeSpaceMonitor)
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                )
        }
    }

    @ViewBuilder
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.brandAccent)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Actions

    /// Prompts for a directory, then starts a scan.
    /// Cancellation: stay on Dashboard (per spec).
    private func startScanWithFolderPicker() {
        guard let url = FolderPicker.chooseScanFolder() else { return }
        model.startScan(path: url.path)
    }
}

// MARK: - History Sheet

/// The full scan history, with restore and clear. The dashboard card shows
/// only the most recent handful.
private struct ScanHistorySheet: View {
    var model: AppModel
    var onClose: () -> Void

    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Scan History", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Clear…", role: .destructive) { confirmingClear = true }
                    .disabled(model.scanHistory.entries.isEmpty)
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.md)

            Divider()

            if model.scanHistory.entries.isEmpty {
                emptyState
            } else {
                List(model.scanHistory.entries) { entry in
                    row(entry)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 560, height: 380)
        .confirmationDialog(
            "Clear all scan history?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                model.scanHistory.clearHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes every recorded scan and its saved tree. Files on disk are not touched.")
        }
    }

    private func row(_ entry: ScanHistoryEntry) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(Color.brandAccent)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.volumePath)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(entry.scanDate.formatted(date: .abbreviated, time: .shortened)) · \(entry.totalFiles) items · \(String(format: "%.1fs", entry.duration))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.sm)

            Text(humanReadableBytes(entry.totalSize))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            model.restoreScanFromHistory(entry)
            onClose()
        }
        .help("Re-open this scan without re-scanning")
    }

    private var emptyState: some View {
        EmptyState(icon: "tray", title: "No scans recorded yet")
    }
}

// MARK: - VolumeCard

private struct VolumeCard: View {
    let volume: DiskVolume
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .top) {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: 36, height: 36)
                            Image(systemName: volume.isRemovable ? "externaldrive" : "internaldrive")
                                .font(.system(size: 18))
                                .foregroundStyle(volume.isReadOnly ? .orange : Color.brandAccent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(volume.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(volume.isRemovable ? "Removable" : "APFS Volume")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !volume.isRemovable {
                        Text("Primary")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color(hex: "70FF76").opacity(0.18))
                            )
                            .foregroundStyle(Color.brandOK)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(humanReadableBytes(volume.usedCapacity)) Used")
                            .font(.system(size: 10, design: .monospaced))
                        Spacer()
                        Text("\(humanReadableBytes(volume.availableCapacity)) Free")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(height: 6)
                            Capsule()
                                .fill(Color.brandAccent)
                                .frame(width: max(2, geo.size.width * CGFloat(volume.usageFraction)), height: 6)
                        }
                    }
                    .frame(height: 6)
                    Text("\(humanReadableBytes(volume.totalCapacity)) Total")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View helper

private extension Text {
    /// JetBrains-Mono-feel table header.
    func headerStyle() -> some View {
        self.font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}
