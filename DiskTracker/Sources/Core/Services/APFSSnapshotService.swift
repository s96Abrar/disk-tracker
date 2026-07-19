//
//  APFSSnapshotService.swift
//  DiskTracker
//
//  Phase 5: List APFS local snapshots via `tmutil listlocalsnapshots /`.
//  Deletion requires root privileges — deferred to the privileged helper (Phase 7+).
//

import Foundation

// MARK: - APFS Snapshot

/// One APFS local Time Machine snapshot.
struct APFSSnapshot: Identifiable, Sendable {
    let id = UUID()
    let volumePath: String
    let snapshotName: String     // e.g. com.apple.TimeMachine.2026-07-12-123456
    let timestamp: Date?
    let sizeBytes: UInt64?       // may be nil if tmutil doesn't report it
}

// MARK: - APFS Snapshot Service

/// Lists APFS local snapshots for a given volume.
///
/// ponytail: shells out to `tmutil listlocalsnapshots <vol>` rather than linking
/// against private Time Machine framework. Deletion (`tmutil deletelocalsnapshots`)
/// needs root and is deferred to the privileged helper tool.
enum APFSSnapshotService {

    /// List local snapshots for the given volume path.
    /// Defaults to the root volume `/` when none is provided.
    static func listSnapshots(for volumePath: String = "/") -> [APFSSnapshot] {
        let output = runTmUtil(arguments: ["listlocalsnapshots", volumePath]) ?? ""
        return output
            .split(separator: "\n")
            .compactMap { line -> APFSSnapshot? in
                let s = line.trimmingCharacters(in: .whitespaces)
                guard s.contains("com.apple.TimeMachine.") else { return nil }
                let name = s.replacingOccurrences(of: "Snapshot:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return APFSSnapshot(
                    volumePath: volumePath,
                    snapshotName: name,
                    timestamp: parseDate(from: name),
                    sizeBytes: nil
                )
            }
    }

    /// Total reclaimable size, summed across all snapshots.  Best-effort.
    static func totalSnapshotSize(for volumePath: String = "/") -> UInt64 {
        // ponytail: tmutil doesn't report per-snapshot size on stock systems.
        // A full accounting would call fs_snapshot_list (private) — left for the
        // privileged helper. Return 0 so the UI shows "—".
        return 0
    }

    // MARK: - Helpers

    private static func runTmUtil(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func parseDate(from snapshotName: String) -> Date? {
        // com.apple.TimeMachine.2026-07-12-123456 -> 2026-07-12 12:34:56
        // tmutil uses YYYY-MM-DD-HHMMSS
        guard let range = snapshotName.range(of: "TimeMachine.") else { return nil }
        let stamp = String(snapshotName[range.upperBound...])  // 2026-07-12-123456
        let parts = stamp.split(separator: "-")
        guard parts.count >= 6 else { return nil }

        guard let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let hhmmss = Int(parts[3]) else { return nil }
        let hour = hhmmss / 10_000
        let minute = (hhmmss / 100) % 100
        let second = hhmmss % 100

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar(identifier: .gregorian).date(from: components)
    }
}