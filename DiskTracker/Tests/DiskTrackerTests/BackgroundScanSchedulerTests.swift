//
//  BackgroundScanSchedulerTests.swift
//  DiskTrackerTests
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

import XCTest
import Foundation
@testable import DiskTracker

final class BackgroundScanSchedulerTests: XCTestCase {

    func testScheduleInitialization() {
        var scanTriggered = false
        let scheduler = BackgroundScanScheduler(schedule: .manual) {
            scanTriggered = true
        }

        XCTAssertEqual(scheduler.currentSchedule, .manual)
        XCTAssertNil(scheduler.nextScanDate)
        XCTAssertFalse(scheduler.isRunning)
    }

    func testScheduleSetSchedule() {
        let scheduler = BackgroundScanScheduler(schedule: .manual) { }

        scheduler.setSchedule(.hourly)

        XCTAssertEqual(scheduler.currentSchedule, .hourly)
        XCTAssertNotNil(scheduler.nextScanDate)
    }

    func testScanNowSetsLastScanDate() {
        let scheduler = BackgroundScanScheduler(schedule: .manual) { }

        XCTAssertNil(scheduler.lastScanDate)
        scheduler.scanNow()
        XCTAssertNotNil(scheduler.lastScanDate)
    }

    func testScanNowTriggersAction() {
        var scanCount = 0
        let scheduler = BackgroundScanScheduler(schedule: .manual) {
            scanCount += 1
        }

        scheduler.scanNow()
        XCTAssertEqual(scanCount, 1)
    }

    func testHourlyIntervalIsCorrect() {
        XCTAssertEqual(BackgroundScanScheduler.Schedule.hourly.interval, 3600)
    }

    func testDailyIntervalIsCorrect() {
        XCTAssertEqual(BackgroundScanScheduler.Schedule.daily.interval, 86400)
    }

    func testWeeklyIntervalIsCorrect() {
        XCTAssertEqual(BackgroundScanScheduler.Schedule.weekly.interval, 604800)
    }
}

#endif  // DISKTRACKER_V05
