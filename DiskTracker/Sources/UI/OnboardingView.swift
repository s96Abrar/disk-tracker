//
//  OnboardingView.swift
//  DiskTracker
//
//  First-launch welcome screen. Shown when OnboardingSettings.showAtLaunch
//  is true. Recreates the HTML mock (DiskTracker/OnboardingView.txt) in
//  native SwiftUI: dark macOS surface, Bento feature cards, system materials.
//

import SwiftUI
import AppKit

// MARK: - OnboardingView

/// The welcome screen. Presented as the root window content until the user
/// dismisses it (via "Start Scan" or "Choose Folder…", or by ticking
/// "Don't show this again" and closing).
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    /// Whether to show the welcome screen on subsequent launches.
    @State private var dontShowAgain: Bool = OnboardingSettings.showAtLaunch == false

    /// Action invoked when the user taps "Start Scan". The parent opens
    /// a folder picker; on selection, kicks off a scan and transitions
    /// to Scan Results. On cancellation, the parent falls back to dashboard.
    var onStartScan: () -> Void

    /// Action invoked when the user taps "Go to Dashboard" (skip scanning
    /// from onboarding and go straight to the dashboard).
    var onGoToDashboard: () -> Void

    var body: some View {
        ZStack {
            // Background — matches the mock's subtle diagonal gradient.
            backgroundGradient

            // Centered macOS-flavoured card window.
            VStack(spacing: 0) {
                // Decorative title bar with traffic-light dots.
                titleBar

                Divider().opacity(0.3)

                // Main content.
                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        header
                        featuresBento
                        actions
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.xl)
                }

                Divider().opacity(0.3)

                footer
            }
            .frame(width: 900, height: 600)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 25, x: 0, y: 12)
        }
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(.dark)
        .onChange(of: dontShowAgain) { _, newValue in
            // Persist immediately so a crash before "Start Scan" still honours it.
            OnboardingSettings.showAtLaunch = !newValue
        }
    }

    // MARK: - Sub-views

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.10, blue: 0.13),
                Color(nsColor: NSColor(calibratedWhite: 0.07, alpha: 1.0))
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var titleBar: some View {
        HStack {
            // Traffic-light dots — purely decorative in onboarding context.
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
            }
            .padding(.leading, Spacing.md)

            Spacer()

            HStack(spacing: Spacing.md) {
                Image(systemName: "sidebar.left")
                Image(systemName: "gear")
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .padding(.trailing, Spacing.md)
        }
        .frame(height: 44)
        .background(Color.clear)
    }

    private var header: some View {
        VStack(spacing: Spacing.md) {
            // The real app icon, not a stand-in — it already has the
            // squircle and the shadow baked in.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.xs) {
                Text("Welcome to Disk Tracker")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Visualize your storage space, find large files, and clean up your drive with precision.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(.top, Spacing.md)
    }

    private var featuresBento: some View {
        HStack(spacing: Spacing.md) {
            FeatureCard(
                icon: "magnifyingglass",
                iconColor: Color(hex: "C2C1FF"),
                iconBackground: Color.brandAccent.opacity(0.18),
                title: "Deep Scan",
                subtitle: "Lightning fast indexing of your entire file system."
            )
            FeatureCard(
                icon: "chart.pie.fill",
                iconColor: Color(hex: "70FF76"),
                iconBackground: Color(hex: "008122").opacity(0.22),
                title: "Visualize",
                subtitle: "Interactive sunburst and treemap representations."
            )
            FeatureCard(
                icon: "trash.slash.fill",
                iconColor: Color.brandAlert,
                iconBackground: Color(hex: "93000A").opacity(0.22),
                title: "Clean Up",
                subtitle: "Safely identify and remove unnecessary clutter."
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        VStack(spacing: Spacing.sm) {
            Button {
                // "Start Scan" hands control back to the parent, which opens
                // a folder picker. On cancel the parent falls back to dashboard.
                onStartScan()
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "play.fill")
                    Text("Start Scan")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.brandAccent)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)

            // "Go to Dashboard" — skip scanning, jump straight to dashboard.
            Button {
                onGoToDashboard()
            } label: {
                Text("Go to Dashboard")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "C2C1FF"))
            }
            .buttonStyle(.plain)
            .help("Skip the scan and open the dashboard.")

            // "Don't show again" sits below the primary actions — bottom-left of the card.
            HStack {
                Toggle(isOn: $dontShowAgain) {
                    Text("Don't show this again")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .help("You can re-enable this from Settings.")

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xs)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("Fast, visual, and safe.")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))
            Spacer()
        }
        .frame(height: 36)
    }
}

// MARK: - FeatureCard

/// One of the three feature cards shown in the onboarding Bento.
private struct FeatureCard: View {
    let icon: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let subtitle: String

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(onStartScan: {}, onGoToDashboard: {})
            .environment(AppModel())
            .frame(width: 900, height: 600)
    }
}
#endif
