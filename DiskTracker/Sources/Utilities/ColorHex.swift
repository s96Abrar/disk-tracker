//
//  ColorHex.swift
//  DiskTracker
//
//  Shared Color(hex:) initializer used by DesignTokens and the UI.
//

import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)

        // ponytail: supports 6-digit RGB; falls back to gray on bad input.
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8)  & 0xFF) / 255
            b = Double( value        & 0xFF) / 255
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
