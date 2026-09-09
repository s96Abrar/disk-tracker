//
//  StatusBar.swift
//  DiskTracker
//
//  Persistent bottom status bar shared by Dashboard and Scan Results.
//  Mirrors the mock footer:
//   - Left: scan state indicator (idle/scanning/done/error) + path
//   - Right: version
//
//  When a scan is running, a Back button appears so the user can leave
//  Scan Results while the scan continues in the background.
//

import SwiftUI

struct StatusBar: View {
    var model: AppModel

    var body: some View {
        HStack(spacing: Spacing.sm) {
            leftGroup
            Spacer()
            rightGroup
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
        .overlay(
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Left side

    @ViewBuilder
    private var leftGroup: some View {
        switch model.scanState {
        case .idle:
            idleIndicator

        case .scanning:
            scanningIndicator

        case .completed(let total, let count):
            completedIndicator(total: total, count: count)

        case .failed(let error):
            failedIndicator(error: error)
        }

        // Path being scanned.
        Text(model.currentScanPath)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(model.currentScanPath)

        // Back button — only meaningful from Scan Results.
        if model.phase == .scanResults {
            Button {
                model.navigate(to: .dashboard)
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .help("Return to dashboard. Scans continue in the background.")
        }
    }

    private var idleIndicator: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.brandOK).frame(width: 8, height: 8)
            Text("Ready for scan")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    /// Indeterminate on purpose: the engine reports how many entries it has
    /// seen, and the total isn't known until the walk finishes.
    private var scanningIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .progressViewStyle(.circular)
            Text("Scanning… \(model.filesScanned) items")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button("Cancel") { model.cancelScan() }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
    }

    private func completedIndicator(total: UInt64, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.brandOK).frame(width: 8, height: 8)
            Text("Scan complete · \(count) items · \(humanReadableBytes(total))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func failedIndicator(error: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.brandAlert).frame(width: 8, height: 8)
            Text("Error: \(error)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    // MARK: - Right side

    private var rightGroup: some View {
        Text("Disk Tracker v\(Self.appVersion)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    /// Read from the bundle rather than hardcoded — the literal here said
    /// v2.4.1 while the app shipped 0.1.0.
    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
