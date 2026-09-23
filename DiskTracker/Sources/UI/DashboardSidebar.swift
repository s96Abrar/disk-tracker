//
//  DashboardSidebar.swift
//  DiskTracker
//
//  Left sidebar shown on the Dashboard. Mirrors the HTML mock:
//  "Disk Tracker" title, Quick Scan section with one-click presets
//  (Root / Users / Applications / Macintosh HD), History, Settings.
//

import SwiftUI

struct DashboardSidebar: View {
    var model: AppModel

    /// Opens the scan history sheet.
    var onShowHistory: () -> Void

    /// Opens the developer caches sheet.
    var onShowDevCaches: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            title
            quickScanHeader
            navList
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .frame(width: 260)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .overlay(
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1),
            alignment: .trailing
        )
    }

    // MARK: - Sub-views

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Disk Tracker")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            Rectangle()
                .fill(Color.brandAccent)
                .frame(width: 32, height: 3)
                .clipShape(Capsule())
        }
        .padding(.bottom, Spacing.sm)
    }

    private var quickScanHeader: some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 32, height: 32)
                Image(systemName: "server.rack")
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Scan")
                    .font(.system(size: 12, weight: .semibold))
                Text("System Volumes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, Spacing.xs)
    }

    private var navList: some View {
        VStack(alignment: .leading, spacing: 2) {
            navRow(icon: "folder.fill", label: "Root") {
                guard model.canStartNewScan else { return }
                model.startScan(path: "/")
            }
            navRow(icon: "person.2", label: "Users") {
                guard model.canStartNewScan else { return }
                model.startScan(path: "/Users")
            }
            navRow(icon: "square.grid.2x2", label: "Applications") {
                guard model.canStartNewScan else { return }
                model.startScan(path: "/Applications")
            }
            // Home, labelled as such — this row used to say "Macintosh HD"
            // while scanning the home directory.
            navRow(
                icon: "house",
                label: "Home",
                isPrimary: true
            ) {
                guard model.canStartNewScan else { return }
                model.startScan(path: NSHomeDirectory())
            }

            Divider().padding(.vertical, Spacing.xs)

            navRow(icon: "clock.arrow.circlepath", label: "History", action: onShowHistory)
            navRow(icon: "hammer", label: "Developer Caches", action: onShowDevCaches)

            // SettingsLink, not a button that pokes `showSettingsWindow:` —
            // AppKit rejects that selector on macOS 14+ ("Please use
            // SettingsLink for opening the Settings scene"), so the old row
            // silently did nothing.
            SettingsLink {
                navRowLabel(icon: "gear", label: "Settings")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func navRow(
        icon: String,
        label: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            navRowLabel(icon: icon, label: label, isPrimary: isPrimary)
        }
        .buttonStyle(.plain)
    }

    private func navRowLabel(icon: String, label: String, isPrimary: Bool = false) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 18)
            Text(label)
                .font(isPrimary
                      ? .system(size: 12, weight: .semibold)
                      : .system(size: 12))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isPrimary ? Color.brandAccent : .secondary)
        .background(
            isPrimary
            ? Color.brandAccent.opacity(0.15)
            : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
