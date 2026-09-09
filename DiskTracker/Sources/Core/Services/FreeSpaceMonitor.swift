//
//  FreeSpaceMonitor.swift
//  DiskTracker
//
//  Phase 4: Live free-space monitoring with configurable low-space alerts.
//

import Foundation
import Combine

// MARK: - Free Space Threshold

/// Severity levels for low-space alerts.
enum FreeSpaceAlertLevel: Int, Comparable, Sendable {
    case none = 0
    case warning = 1   // < 20% or < threshold
    case critical = 2  // < 10%
    case emergency = 3 // < 5%

    static func < (lhs: FreeSpaceAlertLevel, rhs: FreeSpaceAlertLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var description: String {
        switch self {
        case .none: return "OK"
        case .warning: return "Low Space"
        case .critical: return "Critical"
        case .emergency: return "Emergency"
        }
    }

    var colorHex: String {
        switch self {
        case .none: return "27AE60"
        case .warning: return "F39C12"
        case .critical: return "E67E22"
        case .emergency: return "E74C3C"
        }
    }
}

// MARK: - Free Space Snapshot

/// A point-in-time reading of a volume's capacity.
struct FreeSpaceSnapshot: Sendable {
    let volume: DiskVolume
    let timestamp: Date
    let availableBytes: UInt64
    let totalBytes: UInt64

    var usedBytes: UInt64 {
        totalBytes >= availableBytes ? totalBytes - availableBytes : 0
    }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var availableFraction: Double {
        guard totalBytes > 0 else {return 0 }
        return Double(availableBytes) / Double(totalBytes)
    }

    /// Determine alert level given a user-configured threshold (percentage).
    func alertLevel(thresholdPercent: Double) -> FreeSpaceAlertLevel {
        let pct = availableFraction * 100
        if pct < 5 { return .emergency }
        if pct < 10 { return .critical }
        if pct < thresholdPercent { return .warning }
        return .none
    }
}

// MARK: - Monitoring Service

/// Periodically polls volume free space and publishes updates.
///
/// Usage:
///   let monitor = FreeSpaceMonitor()
///   monitor.startMonitoring(volume: volume, interval: 5.0)
///   // Listen to monitor.$snapshot or monitor.$alertLevel
@Observable
final class FreeSpaceMonitor: @unchecked Sendable {

    /// Latest snapshot for the monitored volume.
    var snapshot: FreeSpaceSnapshot?

    /// Current alert level based on the configured threshold.
    var alertLevel: FreeSpaceAlertLevel = .none

    /// Whether an alert banner is currently showing.
    var isAlertShowing: Bool = false

    /// User-configurable threshold (percentage, 0–100). Default 20%.
    var thresholdPercent: Double = 20.0 {
        didSet { refresh() }
    }

    /// Accumulated history (last N snapshots) for trend analysis.
    private(set) var history: [FreeSpaceSnapshot] = []
    private let maxHistoryCount = 60

    /// Last alert level to detect transitions (for one-shot notifications).
    private var lastAlertLevel: FreeSpaceAlertLevel = .none

    private var timer: Timer?
    private var monitoredVolume: DiskVolume?

    // MARK: - Lifecycle

    deinit {
        stopMonitoring()
    }

    // MARK: - Control

    /// Begin periodic polling.
    ///
    /// - Parameters:
    ///   - volume: The volume to monitor.
    ///   - interval: Polling interval in seconds (default 5.0).
    func startMonitoring(volume: DiskVolume, interval: TimeInterval = 5.0) {
        stopMonitoring()
        monitoredVolume = volume
        refresh()  // Immediate reading

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Stop polling and clear state.
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        monitoredVolume = nil
        snapshot = nil
        alertLevel = .none
        lastAlertLevel = .none
        history.removeAll()
    }

    /// Force an immediate refresh.
    func refresh() {
        guard let volume = monitoredVolume else { return }

        if let (total, available) = DiskVolumeService.refreshFreeSpace(for: volume.url) {
            let newSnapshot = FreeSpaceSnapshot(
                volume: volume,
                timestamp: Date(),
                availableBytes: available,
                totalBytes: total
            )

            snapshot = newSnapshot
            history.append(newSnapshot)
            if history.count > maxHistoryCount {
                history.removeFirst(history.count - maxHistoryCount)
            }

            let newLevel = newSnapshot.alertLevel(thresholdPercent: thresholdPercent)
            alertLevel = newLevel

            // Show alert banner when entering warning or above
            if newLevel > .none && lastAlertLevel == .none {
                isAlertShowing = true
            }
            lastAlertLevel = newLevel
        }
    }

    // MARK: - Trend Analysis

    /// Estimate time until full based on recent consumption trend (bytes / second).
    /// Returns nil if no clear trend or volume is not getting fuller.
    var estimatedSecondsUntilFull: TimeInterval? {
        guard history.count >= 2 else { return nil }
        let recent = Array(history.suffix(10))
        guard recent.count >= 2 else { return nil }

        // Simple linear regression on available bytes vs time
        let first = recent.first!
        let last = recent.last!
        let dt = last.timestamp.timeIntervalSince(first.timestamp)
        guard dt > 0 else { return nil }

        let dAvailable = Double(last.availableBytes) - Double(first.availableBytes)
        let consumptionRate = -dAvailable / dt  // positive = getting fuller

        guard consumptionRate > 0 else { return nil }  // Space not decreasing

        let timeToFull = Double(last.availableBytes) / consumptionRate
        return timeToFull > 0 ? timeToFull : nil
    }
}
