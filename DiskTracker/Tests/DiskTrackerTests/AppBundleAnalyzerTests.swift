//
//  AppBundleAnalyzerTests.swift
//  DiskTrackerTests
//
//  Phase 5 TDD: .app bundle detection by name suffix + size threshold.
//

import XCTest
@testable import DiskTracker

final class AppBundleAnalyzerTests: XCTestCase {

    // MARK: - Test helpers

    private func app(name: String, size: UInt64, children: [DiskNode]? = nil,
                     depth: UInt16 = 1) -> DiskNode {
        // .app bundles are always directories in the production code path.
        // Ponytail tests: keep fileKind=.directory unconditionally — passing children:nil
        // builds an empty subdirectory.
        DiskNode(recordIndex: 0, name: name, path: "/Applications/\(name)",
                 logicalSize: size, physicalSize: size,
                 fileKind: .directory,
                 isSystemProtected: false,
                 modTimeSecs: 1, depth: depth, children: children ?? [])
    }

    private var defaultConfig: SmartFilterConfig {
        SmartFilterConfig(includeSystemPaths: false, includeHiddenFiles: false)
    }

    // MARK: - Threshold

    func testDefaultThresholdIs100MB() {
        XCTAssertEqual(AppBundleAnalyzer.defaultThreshold, 100 * 1_000_000)
    }

    func testFindsBundleAboveDefaultThreshold() {
        let bigApp = app(name: "Huge.app", size: 200_000_000)
        let root = app(name: "root", size: 0,
                       children: [bigApp, app(name: "Tiny.app", size: 1_000)], depth: 0)
        let results = AppBundleAnalyzer.findLargeBundles(in: root, config: defaultConfig)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].node.name, "Huge.app")
    }

    func testSkipsBundlesBelowThreshold() {
        let tiny = app(name: "Small.app", size: 1_000)
        let root = app(name: "root", size: 0, children: [tiny], depth: 0)
        let results = AppBundleAnalyzer.findLargeBundles(in: root, config: defaultConfig)
        XCTAssertTrue(results.isEmpty)
    }

    func testCustomThreshold() {
        let medium = app(name: "Mid.app", size: 50_000_000)
        let root = app(name: "root", size: 0, children: [medium], depth: 0)
        // Below default, above custom threshold (10 MB)
        let results = AppBundleAnalyzer.findLargeBundles(in: root, config: defaultConfig,
                                                         threshold: 10_000_000)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].node.name, "Mid.app")
    }

    // MARK: - Naming

    func testIgnoresNonAppNames() {
        let notApp = app(name: "file.txt", size: 200_000_000)
        let root = app(name: "root", size: 0, children: [notApp], depth: 0)
        let results = AppBundleAnalyzer.findLargeBundles(in: root, config: defaultConfig)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Sorting

    func testResultsSortedBySizeDesc() {
        let small  = app(name: "Small.app",  size: 110_000_000)
        let big    = app(name: "Big.app",    size: 500_000_000)
        let medium = app(name: "Medium.app", size: 200_000_000)
        let root = app(name: "root", size: 0,
                       children: [small, big, medium], depth: 0)
        let results = AppBundleAnalyzer.findLargeBundles(in: root, config: defaultConfig)
        let names = results.map { $0.node.name }
        XCTAssertEqual(names, ["Big.app", "Medium.app", "Small.app"])
    }

    func testHiddenFilesSkipped() {
        var cfg = defaultConfig; cfg.includeHiddenFiles = false
        let hidden = app(name: ".Hidden.app", size: 500_000_000)
        let root = app(name: "root", size: 0, children: [hidden], depth: 0)
        let results = AppBundleAnalyzer.findLargeBundles(in: root, config: cfg)
        XCTAssertTrue(results.isEmpty)
    }

    func testHiddenFilesSurfacedWhenEnabled() {
        var cfg = defaultConfig; cfg.includeHiddenFiles = true
        let hidden = app(name: ".Hidden.app", size: 500_000_000)
        let root = app(name: "root", size: 0, children: [hidden], depth: 0)
        let results = AppBundleAnalyzer.findLargeBundles(in: root, config: cfg)
        XCTAssertEqual(results.count, 1)
    }

    func testEmptyTreeNoResults() {
        let root = app(name: "root", size: 0, children: [], depth: 0)
        let results = AppBundleAnalyzer.findLargeBundles(in: root, config: defaultConfig)
        XCTAssertTrue(results.isEmpty)
    }
}
