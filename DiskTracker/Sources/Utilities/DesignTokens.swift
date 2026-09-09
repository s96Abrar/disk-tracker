//
//  DesignTokens.swift
//  DiskTracker
//
//  Phase 2 Design System Tokens following macOS HIG.
//

import SwiftUI

/// Spacing scale (8pt grid)
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

/// Corner radius scale
enum CornerRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
}

/// Animation durations
enum AnimationDuration {
    static let fast: Double = 0.15
    static let normal: Double = 0.25
    static let slow: Double = 0.35
}

/// Brand colors. Every view was spelling these out as `Color(hex:)` literals,
/// so a palette change meant a find-and-replace across the UI.
extension Color {
    /// Primary accent — buttons, selection, links, sidebar highlights.
    static let brandAccent = Color(hex: "5E5CE6")
    /// "Healthy" green — status dots, capacity badges.
    static let brandOK = Color(hex: "42E355")
    /// Error/attention red.
    static let brandAlert = Color(hex: "FFB4AB")
}

/// File type color palette (8 colors, WCAG AA compliant)
extension Color {
    static let fileImage = Color(hex: "E74C3C")
    static let fileVideo = Color(hex: "8E44AD")
    static let fileAudio = Color(hex: "F39C12")
    static let fileDocument = Color(hex: "3498DB")
    static let fileArchive = Color(hex: "27AE60")
    static let fileApplication = Color(hex: "C0392B")
    static let fileDirectory = Color(hex: "34495E")
    static let fileOther = Color(hex: "7F8C8D")

    static func forFileKind(_ kind: FileKind) -> Color {
        switch kind {
        case .image: return .fileImage
        case .video: return .fileVideo
        case .audio: return .fileAudio
        case .document: return .fileDocument
        case .archive: return .fileArchive
        case .application: return .fileApplication
        case .directory: return .fileDirectory
        case .other: return .fileOther
        }
    }
}
