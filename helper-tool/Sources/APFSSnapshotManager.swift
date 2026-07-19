import Foundation
import os.log

// MARK: - Errors

enum SnapshotError: Error, LocalizedError {
    case listingFailed(String)
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .listingFailed(let msg):  return "Failed to list snapshots: \(msg)"
        case .deletionFailed(let msg): return "Failed to delete snapshot: \(msg)"
        }
    }
}

// MARK: - Snapshot Model

struct SnapshotInfo {
    let name: String          // e.g. com.apple.TimeMachine.2024-01-15-120000
    let dateToken: String     // e.g. 2024-01-15-120000
    let displayName: String   // Human-readable string derived from dateToken
}

// MARK: - Manager

/// Manages APFS Time Machine local snapshots.
///
/// Because this code runs inside a privileged helper tool (as root), it can call
/// `tmutil` for any volume. The implementation intentionally uses `tmutil`
/// rather than private `fs_snapshot_*` ioctls because `tmutil` is the Apple-blessed,
/// forward-compatible interface for snapshot operations.
final class APFSSnapshotManager {
    private let log = OSLog(subsystem: "com.disktracker.helper", category: "snapshot")
    private let tmutilPath = "/usr/bin/tmutil"

    // MARK: - Public API

    /// Returns an array of dictionaries suitable for XPC serialization.
    func listSnapshots(forPath: String) throws -> [[String: Any]] {
        let infos = try listSnapshotInfos(forPath: forPath)
        return infos.map { info in
            [
                "name": info.name,
                "date": info.dateToken,
                "displayName": info.displayName,
            ]
        }
    }

    /// Deletes a snapshot identified by its date token.
    func deleteSnapshot(named dateToken: String, forPath: String) throws {
        try runTmutil(arguments: ["deletelocalsnapshots", dateToken])
        os_log("Deleted snapshot %{public}@", log: log, type: .info, dateToken)
    }

    // MARK: - Listing Implementation

    private func listSnapshotInfos(forPath: String) throws -> [SnapshotInfo] {
        let output = try runTmutil(arguments: ["listlocalsnapshots", forPath])

        // tmutil output lines look like:
        //   com.apple.TimeMachine.2024-01-15-120000
        //   com.apple.TimeMachine.2024-02-03-080030
        // A header line "Snapshots for volume …" may also appear.
        let prefix = "com.apple.TimeMachine."
        var infos: [SnapshotInfo] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { continue }

            let dateToken = String(trimmed.dropFirst(prefix.count))
            let display = formatDisplayName(dateToken: dateToken)

            infos.append(SnapshotInfo(
                name: trimmed,
                dateToken: dateToken,
                displayName: display
            ))
        }

        os_log("Parsed %{public}d snapshot(s) for %{public}@",
               log: log, type: .info, infos.count, forPath)
        return infos
    }

    // MARK: - tmutil Shell-Out

    /// Executes `tmutil` with the supplied arguments and returns stdout as a String.
    @discardableResult
    private func runTmutil(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmutilPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let stdout = String(data: stdoutData, encoding: .utf8) else {
            throw SnapshotError.listingFailed("Unable to decode tmutil output")
        }

        if process.terminationStatus != 0 {
            let stderrData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "unknown error"
            throw SnapshotError.listingFailed("tmutil exited \(process.terminationStatus): \(stderr)")
        }

        return stdout
    }

    // MARK: - Formatting

    /// Converts a tmutil date token (yyyy-MM-dd-HHmmss) into a human-readable string.
    private func formatDisplayName(dateToken: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone.current

        guard let date = fmt.date(from: dateToken) else { return dateToken }

        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }
}
