//
//  ByteUtils.swift
//  DiskTracker
//
//  Byte formatting helpers shared across the UI.
//

import Foundation

/// Human-readable byte string (e.g. "42 GB", "1.2 MB").
func humanReadableBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}
