//
//  APFSSnapshotServiceTests.swift
//  DiskTrackerTests
//
//  Phase 5 TDD: APFS snapshot listing (parser + injectable runner).
//
//  NOT BUILT IN v0.1 — gated behind `DISKTRACKER_V05`.
//
//  No build configuration defines that condition, so this file compiles to
//  nothing today. It is kept rather than deleted because it works and is
//  tested; it is the starting point for the phase named above, tracked in
//  `documents/5_FUTURE_TARGETS.md` §3.
//
//  To build it, add to the DiskTracker target's build settings:
//      SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DISKTRACKER_V05
//
//  `./build-disk-tracker --v05` does exactly that, and is run in CI so this
//  code cannot rot into something that no longer compiles.
//

#if DISKTRACKER_V05

import XCTest
@testable import DiskTracker

final class APFSSnapshotServiceTests: XCTestCase {

    // MARK: - Injectable runner

    private struct FakeRunner: APFSSnapshotService.ProcessRunner {
        var output: String? = nil
        func run(arguments: [String]) -> String? { output }
    }

    override func setUp() {
        super.setUp()
        APFSSnapshotService.setRunner(nil)
    }

    override func tearDown() {
        APFSSnapshotService.setRunner(nil)
        super.tearDown()
    }

    // MARK: - Parser

    func testParseSingleSnapshot() {
        let lines = "com.apple.TimeMachine.2026-07-12-123456"
        let snaps = APFSSnapshotService.parseSnapshots(rawOutput: lines, volumePath: "/")
        XCTAssertEqual(snaps.count, 1)
        XCTAssertEqual(snaps[0].snapshotName, "com.apple.TimeMachine.2026-07-12-123456")
        XCTAssertEqual(snaps[0].volumePath, "/")
    }

    func testParseMultipleSnapshots() {
        let output = """
        com.apple.TimeMachine.2026-07-12-123456
        com.apple.TimeMachine.2026-07-11-090100
        com.apple.TimeMachine.2026-07-10-180000
        """
        let snaps = APFSSnapshotService.parseSnapshots(rawOutput: output, volumePath: "/")
        XCTAssertEqual(snaps.count, 3)
    }

    func testParseSnapshotWithPrefix() {
        // Some tmutil builds emit a "Snapshots for volume /:" header + indented entries.
        let output = """
        Snapshots for volume /:
        	com.apple.TimeMachine.2026-07-12-123456
        """
        let snaps = APFSSnapshotService.parseSnapshots(rawOutput: output, volumePath: "/")
        XCTAssertGreaterThanOrEqual(snaps.count, 1)
    }

    func testParserIgnoresNonSnapshotLines() {
        let output = """
        Snapshots for volume /:
        Some other text
        com.apple.TimeMachine.2026-07-12-123456
        """
        let snaps = APFSSnapshotService.parseSnapshots(rawOutput: output, volumePath: "/")
        XCTAssertEqual(snaps.count, 1)
    }

    // MARK: - Date parsing

    func testParseDateCorrect() {
        let date = APFSSnapshotService.parseDate(from: "com.apple.TimeMachine.2026-07-12-123456")
        XCTAssertNotNil(date)
        var comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 7)
        XCTAssertEqual(comps.day, 12)
        XCTAssertEqual(comps.hour, 12)
        XCTAssertEqual(comps.minute, 34)
        XCTAssertEqual(comps.second, 56)
    }

    func testParseDateInvalid() {
        XCTAssertNil(APFSSnapshotService.parseDate(from: "com.apple.TimeMachine.bogus"))
        XCTAssertNil(APFSSnapshotService.parseDate(from: ""))
        XCTAssertNil(APFSSnapshotService.parseDate(from: "TimeMachine."))
    }

    // MARK: - Runner injection

    func testListSnapshotsUsesInjectedRunner() {
        APFSSnapshotService.setRunner(FakeRunner(output: "com.apple.TimeMachine.2026-07-12-123456\n"))
        let snaps = APFSSnapshotService.listSnapshots(for: "/")
        XCTAssertEqual(snaps.count, 1)
        XCTAssertEqual(snaps[0].snapshotName, "com.apple.TimeMachine.2026-07-12-123456")
    }

    func testListSnapshotsRunnerReturnsNilYieldsEmpty() {
        APFSSnapshotService.setRunner(FakeRunner(output: nil))
        let snaps = APFSSnapshotService.listSnapshots(for: "/")
        XCTAssertTrue(snaps.isEmpty)
    }

    func testListSnapshotsEmpty() {
        APFSSnapshotService.setRunner(FakeRunner(output: ""))
        let snaps = APFSSnapshotService.listSnapshots(for: "/")
        XCTAssertTrue(snaps.isEmpty)
    }

    // MARK: - Total size

    func testTotalSnapshotSizeReturnsZero() {
        // ponytail: tmutil per-snapshot sizes are not available without priv helper. ceiling: stock tmutil limit. upgrade: when helper exposes per-snap size.
        XCTAssertEqual(APFSSnapshotService.totalSnapshotSize(for: "/"), 0)
    }

    // MARK: - Empty input

    func testEmptyOutputIsEmptyList() {
        let snaps = APFSSnapshotService.parseSnapshots(rawOutput: "", volumePath: "/")
        XCTAssertTrue(snaps.isEmpty)
    }
}

#endif  // DISKTRACKER_V05
