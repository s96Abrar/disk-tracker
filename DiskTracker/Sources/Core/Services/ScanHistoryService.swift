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

    init(scanDate: Date, volumePath: String, totalFiles: Int, totalSize: UInt64, duration: TimeInterval) {
        self.id = UUID()
        self.scanDate = scanDate
        self.volumePath = volumePath
        self.totalFiles = totalFiles
        self.totalSize = totalSize
        self.duration = duration
        self.scanId = UUID().uuidString
    }
}

/// Service that stores and retrieves scan history.
final class ScanHistoryService: ObservableObject, @unchecked Sendable {

    static let maxHistoryCount = 30
    private static let storageKey = "DiskTracker.ScanHistory"

    @Published private(set) var entries: [ScanHistoryEntry] = []

    init() {
        load()
    }

    /// Record a new scan in history.
    func recordScan(volumePath: String, totalFiles: Int, totalSize: UInt64, duration: TimeInterval) {
        let entry = ScanHistoryEntry(
            scanDate: Date(),
            volumePath: volumePath,
            totalFiles: totalFiles,
            totalSize: totalSize,
            duration: duration
        )
        entries.insert(entry, at: 0)

        // Trim to max count
        if entries.count > Self.maxHistoryCount {
            entries = Array(entries.prefix(Self.maxHistoryCount))
        }

        save()
    }

    /// Clear all history.
    func clearHistory() {
        entries.removeAll()
        save()
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