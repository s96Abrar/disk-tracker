//
//  ScanHistoryService.swift
//  DiskTracker
//
//  Phase 6: Stores scan history for the historical dashboard.
//

import Foundation

/// A single scan record in history.
struct ScanHistoryEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let scanDate: Date
    let volumePath: String
    let totalFiles: Int
    let totalSize: UInt64
    let duration: TimeInterval
    let scanId: String
    /// File name (not full path) of the serialized tree under
    /// `ScanHistoryService.treeDirectory`, so the dashboard can re-open a past
    /// scan without re-walking the filesystem. Optional: entries written before
    /// this field, and scans whose tree failed to persist, simply have no tree.
    /// Cleared when the tree is pruned to stay inside the disk budget. The
    /// entry survives — its stats are still worth showing — but it can no
    /// longer be re-opened without re-scanning.
    var treeFile: String?

    init(scanDate: Date, volumePath: String, totalFiles: Int, totalSize: UInt64, duration: TimeInterval, treeFile: String? = nil) {
        self.id = UUID()
        self.scanDate = scanDate
        self.volumePath = volumePath
        self.totalFiles = totalFiles
        self.totalSize = totalSize
        self.duration = duration
        self.scanId = UUID().uuidString
        self.treeFile = treeFile
    }
}

/// Service that stores and retrieves scan history.
/// `@Observable`, not `ObservableObject`: views reach this through
/// `AppModel.scanHistory`, and Observation does not see into a nested
/// `ObservableObject` — recording a scan left the dashboard's Recent Scans
/// table stale until something else redrew it.
@Observable
final class ScanHistoryService: @unchecked Sendable {

    /// How many scans are listed. Entries are metadata only — a few hundred
    /// bytes each — so this is generous. The trees they point at are what
    /// costs, and those are capped separately by `treeDiskBudget`.
    static let maxHistoryCount = 20

    /// Ceiling on the serialized trees kept for re-opening.
    ///
    /// Measured at ~294 bytes per node, so a scan of a million files writes
    /// about 294MB. Capping by entry count instead would let twenty large
    /// scans hoard several gigabytes — in a tool whose whole purpose is
    /// reclaiming disk space. Oldest trees are dropped first; their entries
    /// stay, and simply lose the ability to restore.
    static let treeDiskBudget: UInt64 = 500 * 1024 * 1024

    private static let storageKey = "DiskTracker.ScanHistory"

    private(set) var entries: [ScanHistoryEntry] = []

    init() {
        load()
    }

    /// Record a new scan in history. Call on the main thread — it publishes.
    /// Persist the tree with `saveTree` off the main thread first and pass the
    /// returned file name here.
    func recordScan(volumePath: String, totalFiles: Int, totalSize: UInt64, duration: TimeInterval, treeFile: String? = nil) {
        let entry = ScanHistoryEntry(
            scanDate: Date(),
            volumePath: volumePath,
            totalFiles: totalFiles,
            totalSize: totalSize,
            duration: duration,
            treeFile: treeFile
        )
        entries.insert(entry, at: 0)

        // Trim to max count, taking the evicted entries' trees with it.
        if entries.count > Self.maxHistoryCount {
            entries.suffix(from: Self.maxHistoryCount).forEach(deleteTree)
            entries = Array(entries.prefix(Self.maxHistoryCount))
        }

        pruneTreesToBudget()
        save()
    }

    /// Clear all history.
    func clearHistory() {
        entries.forEach(deleteTree)
        entries.removeAll()
        save()
    }

    // MARK: - Tree storage

    /// Directory holding serialized scan trees. Trees are orders of magnitude
    /// too large for UserDefaults (a home-directory scan runs to tens of MB,
    /// and the whole prefs plist is read back at every launch), so only the
    /// file name lives in the entry.
    static var treeDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiskTracker/Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Persist a serialized tree. Safe to call off the main thread. Returns the
    /// file name to hand to `recordScan`, or nil if the write failed.
    func saveTree(_ data: Data) -> String? {
        let name = "\(UUID().uuidString).json"
        do {
            try data.write(to: Self.treeDirectory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// Load the tree recorded with `entry`, if it is still on disk.
    func loadTree(for entry: ScanHistoryEntry) -> Data? {
        guard let name = entry.treeFile else { return nil }
        return try? Data(contentsOf: Self.treeDirectory.appendingPathComponent(name))
    }

    /// Drops the oldest trees until the rest fit inside `treeDiskBudget`.
    ///
    /// Newest first, so the scan a user is most likely to re-open is the last
    /// one to go. A tree larger than the whole budget is kept if it is the
    /// newest — otherwise the most recent scan could never be restored.
    func pruneTreesToBudget() {
        var running: UInt64 = 0
        var changed = false

        for index in entries.indices {
            guard let name = entries[index].treeFile else { continue }
            let size = treeSize(name)

            // Always keep the newest, whatever it costs.
            if index == 0 {
                running += size
                continue
            }
            if running + size <= Self.treeDiskBudget {
                running += size
            } else {
                deleteTree(for: entries[index])
                entries[index].treeFile = nil
                changed = true
            }
        }
        if changed { save() }
    }

    private func treeSize(_ name: String) -> UInt64 {
        let url = Self.treeDirectory.appendingPathComponent(name)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values?.fileSize ?? 0)
    }

    /// Total bytes the saved trees occupy. Surfaced so Settings can show it.
    var treeDiskUsage: UInt64 {
        entries.compactMap(\.treeFile).reduce(0) { $0 + treeSize($1) }
    }

    private func deleteTree(for entry: ScanHistoryEntry) {
        guard let name = entry.treeFile else { return }
        try? FileManager.default.removeItem(at: Self.treeDirectory.appendingPathComponent(name))
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ScanHistoryEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    // MARK: - Statistics

    /// Total bytes scanned across all history.
    var totalBytesScanned: UInt64 {
        entries.reduce(0) { $0 + $1.totalSize }
    }

    /// Average scan duration.
    var averageDuration: TimeInterval {
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0) { $0 + $1.duration } / Double(entries.count)
    }

    /// Largest single scan (by file count).
    var largestScanEntry: ScanHistoryEntry? {
        entries.max(by: { $0.totalFiles < $1.totalFiles })
    }

    /// Most recent scan.
    var mostRecentScan: ScanHistoryEntry? {
        entries.first
    }
}