//
//  DiskVolume.swift
//  DiskTracker
//
//  Volume enumeration and free-space queries.
//

import Foundation

/// Represents a mounted volume visible to DiskTracker.
struct DiskVolume: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let totalCapacity: UInt64
    let availableCapacity: UInt64
    let isRemovable: Bool
    let isReadOnly: Bool
    
    /// Used capacity in bytes.
    var usedCapacity: UInt64 {
        totalCapacity >= availableCapacity ? totalCapacity - availableCapacity : 0
    }
    
    /// Usage fraction (0.0 – 1.0).
    var usageFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }
}

/// Queries mounted volumes and their capacity.
enum DiskVolumeService {
    
    /// Enumerate all mounted volumes (excluding system-internal ones).
    static func mountedVolumes() -> [DiskVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsReadOnlyKey,
        ]
        
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }
        
        return urls.compactMap { url -> DiskVolume? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
                return nil
            }
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let avail = UInt64(values.volumeAvailableCapacity ?? 0)
            return DiskVolume(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                totalCapacity: total,
                availableCapacity: avail,
                isRemovable: values.volumeIsRemovable ?? false,
                isReadOnly: values.volumeIsReadOnly ?? false
            )
        }
    }
    
    /// Refresh free-space info for a specific volume URL.
    static func refreshFreeSpace(for url: URL) -> (total: UInt64, available: UInt64)? {
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) else {
            return nil
        }
        let total = UInt64(values.volumeTotalCapacity ?? 0)
        let avail = UInt64(values.volumeAvailableCapacity ?? 0)
        return (total, avail)
    }
}
