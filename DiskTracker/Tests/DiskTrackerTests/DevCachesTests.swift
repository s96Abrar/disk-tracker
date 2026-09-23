//
//  DevCachesTests.swift
//  DiskTrackerTests
//

import XCTest
@testable import DiskTracker

final class DevCachesTests: XCTestCase {

    func testPathsAreUniqueAndRelative() {
        let paths = DevCache.all.map(\.relativePath)
        XCTAssertEqual(Set(paths).count, paths.count)
        for path in paths {
            XCTAssertFalse(path.hasPrefix("/"), path)
            XCTAssertFalse(path.contains(".."), path)
        }
    }

    /// Guards the trash path: tightening the `~/Library` protection rule to the
    /// real home would otherwise turn every cache delete into a silent refusal.
    func testTrashableCachesAreNotSystemProtected() {
        for cache in DevCache.all where cache.trashable {
            XCTAssertFalse(
                FileOperationsService.shared.isSystemProtected(url: URL(fileURLWithPath: cache.path)),
                cache.path)
        }
    }

    func testRealHomeIsNotTheContainer() {
        XCTAssertFalse(DevCaches.realHome.contains("/Library/Containers/"))
        XCTAssertTrue(DevCaches.realHome.hasPrefix("/"))
    }

    func testOnlyArchivesCarriesAWarning() {
        XCTAssertEqual(DevCache.all.filter { $0.warning != nil }.map(\.label), ["Archives"])
    }

    /// Simulator devices hold installed apps and data — measure, never trash.
    func testSimulatorDevicesAreMeasureOnly() {
        let devices = DevCache.all.first { $0.relativePath.hasSuffix("CoreSimulator/Devices") }
        XCTAssertEqual(devices?.trashable, false)
        XCTAssertNotNil(devices?.command)
    }
}
