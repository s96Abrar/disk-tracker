//
//  BackgroundScanScheduler.swift
//  DiskTracker
//
//  Phase 6: Timer-based scheduled background scans.
//

import Foundation
import Combine

/// Schedules and executes background scans at configurable intervals.
final class BackgroundScanScheduler: ObservableObject, @unchecked Sendable {

    /// Available scan schedules.
    enum Schedule: String, CaseIterable, Identifiable {
        case manual = "Manual"
        case hourly = "Hourly"
        case daily = "Daily"
        case weekly = "Weekly"

        var id: String { rawValue }

        var interval: TimeInterval? {
            switch self {
            case .manual: return nil
            case .hourly: return 3600
            case .daily: return 86400
            case .weekly: return 604800
            }
        }

        var displayName: String { rawValue }
    }

    @Published private(set) var currentSchedule: Schedule = .manual
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var nextScanDate: Date?
    @Published private(set) var isRunning = false

    private var timer: Timer?
    private let scanAction: () -> Void

    init(schedule: Schedule = .manual, scanAction: @escaping () -> Void) {
        self.scanAction = scanAction
        self.currentSchedule = schedule
        if let interval = schedule.interval {
            scheduleNextScan(after: interval)
        }
    }

    /// Update the scan schedule.
    func setSchedule(_ schedule: Schedule) {
        timer?.invalidate()
        timer = nil
        currentSchedule = schedule

        if let interval = schedule.interval {
            scheduleNextScan(after: interval)
        } else {
            nextScanDate = nil
        }
    }

    /// Trigger an immediate scan.
    func scanNow() {
        lastScanDate = Date()
        isRunning = true
        scanAction()
        isRunning = false

        // Schedule next scan if not manual
        if let interval = currentSchedule.interval {
            scheduleNextScan(after: interval)
        }
    }

    private func scheduleNextScan(after interval: TimeInterval) {
        nextScanDate = Date().addingTimeInterval(interval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.scanNow()
        }
    }

    deinit {
        timer?.invalidate()
    }
}