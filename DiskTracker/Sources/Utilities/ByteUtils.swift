//
//  ByteUtils.swift
//  DiskTracker
//
//  Byte formatting helpers shared across the UI.
//

import Foundation

/// Human-readable byte string (e.g. "42 GB", "1.2 MB").
///
/// - Parameter bytes: Raw byte count.
/// - Returns: Localised, formatted string.
func humanReadableBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
}
