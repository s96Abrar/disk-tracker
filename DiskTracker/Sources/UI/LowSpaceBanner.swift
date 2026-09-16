//
//  LowSpaceBanner.swift
//  DiskTracker
//
//  Surfaces `FreeSpaceMonitor.alertLevel`.
//
//  The monitor computed the level correctly and set `isAlertShowing` on every
//  transition into warning, and nothing read either — the one thing that is
//  supposed to interrupt the user was the one thing with no UI.
//
//  A banner rather than a system notification: a notification needs
//  authorization the app does not currently request, and is only worth it when
//  the app is in the background, which is a later concern.
//

import SwiftUI

/// Bar shown above the status bar when the monitored volume is running low.
///
/// Dismissible, because a warning that cannot be silenced gets ignored — but
/// it comes back if the level gets worse, which is the point of the severity
/// distinction.
struct LowSpaceBanner: View {
    var monitor: FreeSpaceMonitor

    /// The severity the user has already dismissed. A warning they have seen
    /// stays hidden; the same volume dropping to critical shows it again.
    @State private var dismissedAt: FreeSpaceAlertLevel = .none

    private var level: FreeSpaceAlertLevel { monitor.alertLevel }

    private var isVisible: Bool {
        level > .none && level > dismissedAt
    }

    var body: some View {
        if isVisible, let snapshot = monitor.snapshot {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(headline(snapshot))
                        .font(.system(size: 12, weight: .semibold))
                    Text(detail(snapshot))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.sm)

                Button("Dismiss") {
                    dismissedAt = level
                    monitor.isAlertShowing = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(tint.opacity(0.12))
            .overlay(
                Rectangle().fill(tint.opacity(0.5)).frame(height: 1),
                alignment: .top
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            // Getting worse un-dismisses; getting better resets so the next
            // dip warns again.
            .onChange(of: level) { _, new in
                if new == .none { dismissedAt = .none }
            }
        }
    }

    private var tint: Color {
        switch level {
        case .none:      return .secondary
        case .warning:   return .orange
        case .critical:  return .red
        case .emergency: return .red
        }
    }

    private var icon: String {
        switch level {
        case .none:      return "checkmark.circle"
        case .warning:   return "exclamationmark.triangle"
        case .critical:  return "exclamationmark.triangle.fill"
        case .emergency: return "exclamationmark.octagon.fill"
        }
    }

    private func headline(_ snapshot: FreeSpaceSnapshot) -> String {
        let name = snapshot.volume.name
        switch level {
        case .none:      return ""
        case .warning:   return "\(name) is running low on space"
        case .critical:  return "\(name) is critically low on space"
        case .emergency: return "\(name) is almost full"
        }
    }

    /// Leads with what is left, since that is the number the user acts on.
    private func detail(_ snapshot: FreeSpaceSnapshot) -> String {
        let free = humanReadableBytes(snapshot.availableBytes)
        let percent = Int((snapshot.availableFraction * 100).rounded())
        var text = "\(free) free of \(humanReadableBytes(snapshot.totalBytes)) · \(percent)%"

        // Only worth saying when the volume is actually filling up.
        if let seconds = monitor.estimatedSecondsUntilFull, seconds < 60 * 60 * 24 * 30 {
            text += " · full in about \(Self.relative(seconds))"
        }
        return text
    }

    private static func relative(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        return formatter.string(from: seconds) ?? "a while"
    }
}
