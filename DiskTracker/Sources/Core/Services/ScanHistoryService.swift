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
    let treeFile: String?

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

    static let maxHistoryCount = 5
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