//
//  SmartFilterServiceTests.swift
//  DiskTrackerTests
//
//  Phase 4 TDD: large/old/empty file detection, file-type filter, aggregate stats.
//

import XCTest
@testable import DiskTracker

final class SmartFilterServiceTests: XCTestCase {

    // MARK: - Tree builders

    private func leaf(name: String, physicalSize: UInt64, modTime: Int64 = 1, depth: UInt16 = 1) -> DiskNode {
        DiskNode(recordIndex: 0, name: name, path: "/root/\(name)",
                 logicalSize: physicalSize, physicalSize: physicalSize,
                 fileKind: DiskNode.detectFileKind(extension: (name as NSString).pathExtension),
                 isSystemProtected: false, modTimeSecs: modTime, depth: depth, children: nil)
    }

    private func dir(name: String, children: [DiskNode], modTime: Int64 = 1, depth: UInt16 = 0) -> DiskNode {
        DiskNode(recordIndex: 0, name: name, path: "/root/\(name)",
                 logicalSize: 0, physicalSize: 0, fileKind: .directory,
                 isSystemProtected: false, modTimeSecs: modTime, depth: depth, children: children)
    }

    private var defaultConfig: SmartFilterConfig {
        SmartFilterConfig(largeFileThresholdGB: 1.0, oldFileThresholdMonths: 6,
                          includeSystemPaths: false, includeHiddenFiles: false)
    }

    // MARK: - Large File Finder

    func testFindLargeFilesExcludesBelowThreshold() {
        let root = dir(name: "r", children: [
            leaf(name: "small.txt", physicalSize: 100),
            leaf(name: "big.dmg",   physicalSize: 2_000_000_000),
        ])
        let results = SmartFilterService.findLargeFiles(in: root, config: defaultConfig)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].matchReason, .largeFile)
    }

    func testFindLargeFileExactlyAtThreshold() {
        let threshold = defaultConfig.largeFileThresholdBytes
        let root = dir(name: "r", children: [
            leaf(name: "exact.dat", physicalSize: threshold),
        ])
        let results = SmartFilterService.findLargeFiles(in: root, config: defaultConfig)
        XCTAssertEqual(results.count, 1)
    }

    func testFindLargeFileSortedBySizeDesc() {
        let root = dir(name: "r", children: [
            leaf(name: "mid.dmg",   physicalSize: 3_000_000_000),
            leaf(name: "big.dmg",   physicalSize: 5_000_000_000),
            leaf(name: "small.dmg", physicalSize: 1_500_000_000),
        ])
        let results = SmartFilterService.findLargeFiles(in: root, config: defaultConfig)
        let sizes = results.map { $0.node.physicalSize }
        XCTAssertEqual(sizes, [5_000_000_000, 3_000_000_000, 1_500_000_000])
    }

    func testFindLargeFileIgnoresDirectories() {
        let root = dir(name: "r", children: [
            dir(name: "bigFolder", children: [leaf(name: "tiny.txt", physicalSize: 0)]),
        ])
        let results = SmartFilterService.findLargeFiles(in: root, config: defaultConfig)
        XCTAssertTrue(results.isEmpty)
    }

    func testFindLargeFileRespectsHiddenFilter() {
        var cfg = defaultConfig; cfg.includeHiddenFiles = false
        let root = dir(name: "r", children: [
            leaf(name: ".secret.iso", physicalSize: 5_000_000_000),
        ])
        let results = SmartFilterService.findLargeFiles(in: root, config: cfg)
        XCTAssertTrue(results.isEmpty)
    }

    func testFindLargeFileShowsHiddenWhenEnabled() {
        var cfg = defaultConfig; cfg.includeHiddenFiles = true
        let root = dir(name: "r", children: [
            leaf(name: ".secret.iso", physicalSize: 5_000_000_000),
        ])
        let results = SmartFilterService.findLargeFiles(in: root, config: cfg)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Old File Finder

    func testOldFileRecentNotIncluded() {
        let now = Int64(Date().timeIntervalSince1970)
        let root = dir(name: "r", children: [
            leaf(name: "fresh.txt", physicalSize: 100, modTime: now - 2 * 86_400),
        ])
        let results = SmartFilterService.findOldFiles(in: root, config: defaultConfig)
        XCTAssertTrue(results.isEmpty)
    }

    func testOldFileOlderThanThreshold() {
        let now = Int64(Date().timeIntervalSince1970)
        let eightMonthsAgo = now - 8 * 30 * 86_400
        let root = dir(name: "r", children: [
            leaf(name: "stale.dmg", physicalSize: 100, modTime: eightMonthsAgo),
        ])
        let results = SmartFilterService.findOldFiles(in: root, config: defaultConfig)
        XCTAssertEqual(results.count, 1)
    }

    func testOldFileSortedByAscendingTime() {
        let now = Int64(Date().timeIntervalSince1970)
        let veryOld = now - 12 * 30 * 86_400
        let older   = now - 10 * 30 * 86_400
        let root = dir(name: "r", children: [
            leaf(name: "b.dmg", physicalSize: 100, modTime: older),
            leaf(name: "a.dmg", physicalSize: 100, modTime: veryOld),
        ])
        let results = SmartFilterService.findOldFiles(in: root, config: defaultConfig)
        let times = results.map { $0.node.modTimeSecs }
        XCTAssertEqual(times, [veryOld, older])
    }

    func testOldFileSkipsModTimeZero() {
        let root = dir(name: "r", children: [
            leaf(name: "zero.dmg", physicalSize: 100, modTime: 0),
        ])
        let results = SmartFilterService.findOldFiles(in: root, config: defaultConfig)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Empty Folder Finder

    func testEmptyFolderSingleEmptyDir() {
        let root = dir(name: "r", children: [
            dir(name: "Empty", children: []),
        ])
        let results = SmartFilterService.findEmptyFolders(in: root, config: defaultConfig)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].matchReason, .emptyFolder)
    }

    func testEmptyFolderDirWithFilesNotEmpty() {
        let root = dir(name: "r", children: [
            dir(name: "NotEmpty", children: [leaf(name: "file.txt", physicalSize: 100)]),
        ])
        let results = SmartFilterService.findEmptyFolders(in: root, config: defaultConfig)
        XCTAssertTrue(results.isEmpty)
    }

    func testEmptyFolderDeepestFirst() {
        let root = dir(name: "r", children: [
            dir(name: "A", children: [
                dir(name: "B", children: []), // depth=2
            ]), // depth=1
        ])
        let results = SmartFilterService.findEmptyFolders(in: root, config: defaultConfig)
        let names = results.map { $0.node.name }
        // deepest = B first; A is also empty (child B is empty) so it appears too
        XCTAssertEqual(names.first, "B")
        XCTAssertTrue(names.contains("A"))
    }

    func testEmptyFolderEmptyRootReturnsOnlyRoot() {
        let root = dir(name: "root", children: [])
        let results = SmartFilterService.findEmptyFolders(in: root, config: defaultConfig)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].node.name, "root")
    }

    // MARK: - File Type Filter

    func testFileTypeFilterMatchesOnlyKind() {
        let root = dir(name: "r", children: [
            leaf(name: "pic.jpg",   physicalSize: 1), // .image
            leaf(name: "song.mp3",  physicalSize: 2), // .audio
            leaf(name: "movie.mov", physicalSize: 3), // .video
        ])
        let images = SmartFilterService.findByFileType(in: root, kind: .image, config: defaultConfig)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].node.name, "pic.jpg")
    }

    func testFileTypeFilterRespectsHidden() {
        var cfg = defaultConfig; cfg.includeHiddenFiles = false
        let root = dir(name: "r", children: [
            leaf(name: ".secret.jpg", physicalSize: 1),
        ])
        let results = SmartFilterService.findByFileType(in: root, kind: .image, config: defaultConfig)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Tree Stats

    func testTreeStatsCountsFilesAndDirs() {
        let root = dir(name: "r", children: [
            leaf(name: "a.txt", physicalSize: 1024),
            leaf(name: "b.jpg", physicalSize: 2048),
        ])
        let stats = SmartFilterService.computeStats(in: root)
        XCTAssertEqual(stats.totalFiles, 2)
        XCTAssertEqual(stats.totalDirectories, 1)
        XCTAssertEqual(stats.totalSize, 1024 + 2048)
    }

    func testTreeStatsLargestAndOldest() {
        let now = Int64(Date().timeIntervalSince1970)
        let root = dir(name: "r", children: [
            leaf(name: "mid.txt",  physicalSize: 10_000, modTime: now - 1000),
            leaf(name: "big.txt",  physicalSize: 100_000, modTime: now - 100),
            leaf(name: "old.txt",  physicalSize: 1, modTime: now - 1_000_000),
        ])
        let stats = SmartFilterService.computeStats(in: root)
        XCTAssertEqual(stats.largestFile?.name, "big.txt")
        XCTAssertEqual(stats.oldestFile?.name, "old.txt")
    }

    func testTreeStatsFileTypeHistograms() {
        let root = dir(name: "r", children: [
            leaf(name: "a.jpg", physicalSize: 100),
            leaf(name: "b.jpg", physicalSize: 200),
            leaf(name: "c.mp3", physicalSize: 50),
        ])
        let stats = SmartFilterService.computeStats(in: root)
        XCTAssertEqual(stats.fileTypeCounts[.image], 2)
        XCTAssertEqual(stats.fileTypeCounts[.audio], 1)
        XCTAssertEqual(stats.fileTypeSizes[.image], 100 + 200)
        XCTAssertEqual(stats.fileTypeSizes[.audio], 50)
    }

    func testTreeStatsEmptyTree() {
        let root = dir(name: "r", children: [])
        let stats = SmartFilterService.computeStats(in: root)
        XCTAssertEqual(stats.totalFiles, 0)
        XCTAssertEqual(stats.totalDirectories, 1)
        XCTAssertEqual(stats.totalSize, 0)
    }
}