//
//  DuplicateFinderServiceTests.swift
//  DiskTrackerTests
//
//  Phase 5 TDD: content-aware duplicate detection.
//  Drives hashing via an in-memory `DuplicateContentSource` so tests don't touch disk.
//

import XCTest
import CryptoKit
@testable import DiskTracker

final class DuplicateFinderServiceTests: XCTestCase {

    // MARK: - Test helpers

    private func leaf(path: String, size: UInt64, modTime: Int64 = 1) -> DiskNode {
        DiskNode(recordIndex: 0, name: (path as NSString).lastPathComponent, path: path,
                 logicalSize: size, physicalSize: size,
                 fileKind: .other, isSystemProtected: false,
                 modTimeSecs: modTime, depth: 1, children: nil)
    }

    private func dir(path: String, children: [DiskNode]) -> DiskNode {
        DiskNode(recordIndex: 0, name: (path as NSString).lastPathComponent, path: path,
                 logicalSize: 0, physicalSize: 0, fileKind: .directory,
                 isSystemProtected: false, modTimeSecs: 1, depth: 0, children: children)
    }

    private var defaultConfig: SmartFilterConfig {
        SmartFilterConfig(includeSystemPaths: false, includeHiddenFiles: false)
    }

    /// In-memory content source. Map URL → raw bytes.
    /// ponytail: keeps duplicate tests hermetic; disk reads are otherwise unavoidable.
    /// ceiling: hermetic memory source. upgrade: when virtual filesystem mock available.
    private struct MemorySource: DuplicateContentSource {
        var bytes: [URL: Data]
        func read(url: URL, length: Int) -> Data? {
            bytes[url].map { Data($0.prefix(length)) }
        }
        func readAll(url: URL) -> Data? { bytes[url] }
    }

    // MARK: - Lifecycle

    override func setUp() {
        super.setUp()
        DuplicateFinderService.setContentSource(nil)
    }

    override func tearDown() {
        DuplicateFinderService.setContentSource(nil)
        super.tearDown()
    }

    // MARK: - Grouping

    func testIdenticalContentFormsGroup() {
        let bytes = Data(repeating: 0xAB, count: 4_096)
        let source = MemorySource(bytes: [
            URL(fileURLWithPath: "/a.dat"): bytes,
            URL(fileURLWithPath: "/b.dat"): bytes,
        ])
        DuplicateFinderService.setContentSource(source)

        let root = dir(path: "/", children: [
            leaf(path: "/a.dat", size: 4_096, modTime: 100),
            leaf(path: "/b.dat", size: 4_096, modTime: 200),
        ])
        let groups = DuplicateFinderService.findDuplicates(in: root, config: defaultConfig)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].nodes.count, 2)
    }

    func testSingletonsExcluded() {
        // Two files, different sizes, same content: not duplicates.
        let bytes = Data(repeating: 0xCD, count: 4_096)
        let source = MemorySource(bytes: [
            URL(fileURLWithPath: "/a.dat"): bytes,
            URL(fileURLWithPath: "/b.dat"): bytes,
        ])
        DuplicateFinderService.setContentSource(source)

        let root = dir(path: "/", children: [
            leaf(path: "/a.dat", size: 4_096),
            leaf(path: "/b.dat", size: 8_192),  // different size → different bucket
        ])
        let groups = DuplicateFinderService.findDuplicates(in: root, config: defaultConfig)
        XCTAssertTrue(groups.isEmpty)
    }

    func testBelowMinFileSizeIgnored() {
        // minFileSize = 1_024; smaller files skipped.
        let root = dir(path: "/", children: [
            leaf(path: "/tiny1.dat", size: 100),
            leaf(path: "/tiny2.dat", size: 100),
        ])
        let groups = DuplicateFinderService.findDuplicates(in: root, config: defaultConfig)
        XCTAssertTrue(groups.isEmpty)
    }

    func testMostRecentMarkedOriginal() {
        let bytes = Data(repeating: 0x42, count: 2_048)
        let source = MemorySource(bytes: [
            URL(fileURLWithPath: "/old.dat"): bytes,
            URL(fileURLWithPath: "/new.dat"): bytes,
        ])
        DuplicateFinderService.setContentSource(source)

        let root = dir(path: "/", children: [
            leaf(path: "/old.dat", size: 2_048, modTime: 100),
            leaf(path: "/new.dat", size: 2_048, modTime: 200),
        ])
        let groups = DuplicateFinderService.findDuplicates(in: root, config: defaultConfig)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].originalNode.path, "/new.dat")
    }

    func testWastedBytesExcludesOriginal() {
        let bytes = Data(repeating: 0x10, count: 1_024)
        var source = MemorySource(bytes: [:])
        for p in ["/x.dat", "/y.dat", "/z.dat"] {
            source.bytes[URL(fileURLWithPath: p)] = bytes
        }
        DuplicateFinderService.setContentSource(source)

        let root = dir(path: "/", children: [
            leaf(path: "/x.dat", size: 1_024, modTime: 50),
            leaf(path: "/y.dat", size: 1_024, modTime: 60),
            leaf(path: "/z.dat", size: 1_024, modTime: 100),
        ])
        let groups = DuplicateFinderService.findDuplicates(in: root, config: defaultConfig)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].wastedBytes, 2 * 1_024)
        XCTAssertEqual(groups[0].nodes.count, 3)
    }

    func testGroupsSortedByWastedBytesDesc() {
        let big = Data(repeating: 0xAA, count: 5_000)
        let small = Data(repeating: 0xBB, count: 1_500)

        var bytes: [URL: Data] = [:]
        for p in ["/big1.dat", "/big2.dat"] { bytes[URL(fileURLWithPath: p)] = big }
        for p in ["/sm1.dat", "/sm2.dat"] { bytes[URL(fileURLWithPath: p)] = small }
        DuplicateFinderService.setContentSource(MemorySource(bytes: bytes))

        let root = dir(path: "/", children: [
            leaf(path: "/big1.dat", size: 5_000),
            leaf(path: "/big2.dat", size: 5_000),
            leaf(path: "/sm1.dat",  size: 1_500),
            leaf(path: "/sm2.dat",  size: 1_500),
        ])
        let groups = DuplicateFinderService.findDuplicates(in: root, config: defaultConfig)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].wastedBytes, 5_000)
        XCTAssertEqual(groups[1].wastedBytes, 1_500)
    }

    func testHashMatchesKnownDigest() {
        let bytes = Data(repeating: 0xDE, count: 2_048)
        DuplicateFinderService.setContentSource(MemorySource(bytes: [
            URL(fileURLWithPath: "/a.dat"): bytes,
            URL(fileURLWithPath: "/b.dat"): bytes,
        ]))
        let root = dir(path: "/", children: [
            leaf(path: "/a.dat", size: 2_048),
            leaf(path: "/b.dat", size: 2_048),
        ])
        let groups = DuplicateFinderService.findDuplicates(in: root, config: defaultConfig)
        XCTAssertEqual(groups[0].hash.count, 32)  // SHA-256 = 32 bytes
        XCTAssertEqual(groups[0].hash, Data(SHA256.hash(data: bytes)))
    }

    func testRespectsHiddenFilter() {
        let bytes = Data(repeating: 0x11, count: 2_048)
        DuplicateFinderService.setContentSource(MemorySource(bytes: [
            URL(fileURLWithPath: "/.hidden.dat"): bytes,
        ]))

        var cfg = defaultConfig; cfg.includeHiddenFiles = false
        let root = dir(path: "/", children: [
            leaf(path: "/.hidden.dat", size: 2_048),
        ])
        let groups = DuplicateFinderService.findDuplicates(in: root, config: cfg)
        XCTAssertTrue(groups.isEmpty)
    }

    func testEmptyTreeNoGroups() {
        let root = dir(path: "/", children: [])
        let groups = DuplicateFinderService.findDuplicates(in: root, config: defaultConfig)
        XCTAssertTrue(groups.isEmpty)
    }

    func testDirectoriesNotHashed() {
        let bytes = Data(repeating: 0x55, count: 2_048)
        DuplicateFinderService.setContentSource(MemorySource(bytes: [
            URL(fileURLWithPath: "/a"): bytes,
            URL(fileURLWithPath: "/b"): bytes,
        ]))
        let root = dir(path: "/", children: [
            dir(path: "/a", children: []),
            dir(path: "/b", children: []),
        ])
        let groups = DuplicateFinderService.findDuplicates(in: root, config: defaultConfig)
        XCTAssertTrue(groups.isEmpty)
    }
}
