//
//  BackgroundScanSchedulerTests.swift
//  DiskTrackerTests
//

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