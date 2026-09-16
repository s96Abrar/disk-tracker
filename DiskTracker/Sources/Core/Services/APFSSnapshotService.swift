//
//  APFSSnapshotService.swift
//  DiskTracker
//
//  Phase 5: List APFS local snapshots via `tmutil listlocalsnapshots /`.
//  Deletion requires root privileges — deferred to the privileged helper (Phase 7+).
//
//  NOT BUILT IN v0.1 — gated behind `DISKTRACKER_V05`.
//
//  No build configuration defines that condition, so this file compiles to
//  nothing today. It is kept rather than deleted because it works and is
//  tested; it is the starting point for the phase named above, tracked in
//  a post-v0.1 target.
//
//  To build it, add to the DiskTracker target's build settings:
//      SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DISKTRACKER_V05
//
//  `./build-disk-tracker --v05` does exactly that, and is run in CI so this
//  code cannot rot into something that no longer compiles.
//

#if DISKTRACKER_V05

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

    /// Abstraction over the `tmutil` subprocess for testability.
    /// ponytail: the production runner shells out to /usr/bin/tmutil; tests inject
    /// canned output to drive parser behavior without touching the system binary.
    protocol ProcessRunner {
        func run(arguments: [String]) -> String?
    }

    /// Live runner — execs /usr/bin/tmutil synchronously.
    struct TmUtilRunner: ProcessRunner {
        func run(arguments: [String]) -> String? {
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
    }

    /// Default runner; tests inject their own via setRunner.
    /// ponytail: kept as a static var with explicit setter so test tear-down is obvious.
    nonisolated(unsafe) static var runner: ProcessRunner = TmUtilRunner()

    /// Install a fake runner for tests. Pass `nil` to restore defaults.
    static func setRunner(_ next: ProcessRunner?) {
        runner = next ?? TmUtilRunner()
    }

    /// List local snapshots for the given volume path.
    /// Defaults to the root volume `/` when none is provided.
    static func listSnapshots(for volumePath: String = "/") -> [APFSSnapshot] {
        return parseSnapshots(rawOutput: runner.run(arguments: ["listlocalsnapshots", volumePath]) ?? "",
                              volumePath: volumePath)
    }

    /// Total reclaimable size, summed across all snapshots.  Best-effort.
    static func totalSnapshotSize(for volumePath: String = "/") -> UInt64 {
        // ponytail: tmutil doesn't report per-snapshot size on stock systems.
        // A full accounting would call fs_snapshot_list (private) — left for the
        // privileged helper. Return 0 so the UI shows "—".
        return 0
    }

    // MARK: - Pure helpers (test seams)

    /// Parses tmutil output into APFSSnapshot records. Pure function — no I/O.
    /// ponytail: extracted so tests can drive parser behavior without faking a runner.
    static func parseSnapshots(rawOutput: String, volumePath: String) -> [APFSSnapshot] {
        return rawOutput
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

    /// Parses the date suffix on a snapshot name (e.g. "...2026-07-12-123456" → 2026-07-12 12:34:56).
    static func parseDate(from snapshotName: String) -> Date? {
        // com.apple.TimeMachine.2026-07-12-123456 -> 2026-07-12 12:34:56
        // tmutil uses YYYY-MM-DD-HHMMSS; splitting on "-" yields 4 chunks.
        guard let range = snapshotName.range(of: "TimeMachine.") else { return nil }
        let stamp = String(snapshotName[range.upperBound...])  // 2026-07-12-123456
        let parts = stamp.split(separator: "-")
        // ponytail: tmutil emits exactly 4 dash-separated chunks (Y-M-D-HHMMSS).
        // Earlier versions of this guard required 6 chunks, breaking real inputs.
        guard parts.count >= 4 else { return nil }

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

#endif  // DISKTRACKER_V05
