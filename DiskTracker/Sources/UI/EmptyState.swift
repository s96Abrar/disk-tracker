//
//  EmptyState.swift
//  DiskTracker
//
//  One empty-state placeholder.
//
//  Five near-identical copies had accumulated across the dashboard, scan
//  results, filtered results and smart filters — same icon-title-message stack,
//  four slightly different sets of sizes and spacings.
//

import SwiftUI

/// Centred icon, title and explanation, for a view with nothing to show.
struct EmptyState: View {
    let icon: String
    let title: String
    var message: String?

    /// `compact` fits inside a card; the default fills the available space.
    var compact: Bool = false

    /// Optional call to action, for the cases where there is something the
    /// user can do about it.
    var action: (() -> Void)?
    var actionLabel: String?
    var actionIcon: String?

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: compact ? 28 : 40))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: compact ? 13 : 14, weight: .semibold))

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let action, let actionLabel {
                Button(action: action) {
                    Label(actionLabel, systemImage: actionIcon ?? "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity,
               maxHeight: compact ? nil : .infinity)
        .padding(compact ? Spacing.xl : 0)
    }
}
