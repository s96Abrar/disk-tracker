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

    /// Nothing under a Library folder goes to Trash; only the home dot-folder
    /// caches do.
    func testOnlyDotFolderCachesAreTrashable() {
        XCTAssertEqual(
            DevCache.all.filter(\.trashable).map(\.relativePath),
            [".npm/_cacache", ".cargo/registry/cache", ".cargo/git",
             ".gradle/caches", ".gradle/daemon", ".gradle/wrapper", ".android/cache"])
    }

    func testRealHomeIsNotTheContainer() {
        XCTAssertFalse(ScopedAccess.realHome.contains("/Library/Containers/"))
        XCTAssertTrue(ScopedAccess.realHome.hasPrefix("/"))
    }

    func testOnlyArchivesCarriesAWarning() {
        XCTAssertEqual(DevCache.all.filter { $0.warning != nil }.map(\.label), ["Archives"])
    }

    /// Simulator devices hold installed apps and data — measure, never trash.
    /// The Library rule covers it; this pins that down.
    func testSimulatorDevicesAreMeasureOnly() {
        let devices = DevCache.all.first { $0.relativePath.hasSuffix("CoreSimulator/Devices") }
        XCTAssertEqual(devices?.trashable, false)
        XCTAssertNotNil(devices?.command)
    }
}
