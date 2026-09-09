//
//  DiskNodeTests.swift
//  DiskTrackerTests
//

import XCTest
import Foundation
@testable import DiskTracker // Import the main app module

final class DiskNodeTests: XCTestCase {

    func testDiskNodeInitialization() {
        let node = DiskNode(
            recordIndex: 0,
            name: "test.txt",
            path: "/path/to/test.txt",
            logicalSize: 1024,
            physicalSize: 512,
            fileKind: .document,
            isSystemProtected: false,
            modTimeSecs: 1678886400, // March 15, 2023 12:00:00 PM UTC
            depth: 2,
            children: nil
        )

        XCTAssertEqual(node.name, "test.txt")
        XCTAssertEqual(node.path, "/path/to/test.txt")
        XCTAssertEqual(node.logicalSize, 1024)
        XCTAssertEqual(node.physicalSize, 512)
        XCTAssertEqual(node.fileKind, .document)
        XCTAssertFalse(node.isSystemProtected)
    }

    func testFileKindDetection() {
        XCTAssertEqual(DiskNode.detectFileKind(extension: "jpg"), FileKind.image)
        XCTAssertEqual(DiskNode.detectFileKind(extension: "mp4"), FileKind.video)
        XCTAssertEqual(DiskNode.detectFileKind(extension: "mp3"), FileKind.audio)
        XCTAssertEqual(DiskNode.detectFileKind(extension: "doc"), FileKind.document)
        XCTAssertEqual(DiskNode.detectFileKind(extension: "zip"), FileKind.archive)
        XCTAssertEqual(DiskNode.detectFileKind(extension: "app"), FileKind.application)
        XCTAssertEqual(DiskNode.detectFileKind(extension: "DS_Store"), FileKind.other)
        XCTAssertEqual(DiskNode.detectFileKind(extension: "exe"), FileKind.application)
    }

    func testDiskNodeSizeCalculations() {
        let child1 = DiskNode(
            recordIndex: 0,
            name: "c1", path: "/p/c1",
            logicalSize: 100,
            physicalSize: 50,
            fileKind: .other,
            isSystemProtected: false,
            modTimeSecs: 0,
            depth: 1,
            children: nil
        )
        let child2 = DiskNode(
            recordIndex: 0,
            name: "c2", path: "/p/c2",
            logicalSize: 200,
            physicalSize: 100,
            fileKind: .other,
            isSystemProtected: false,
            modTimeSecs: 0,
            depth: 1,
            children: nil
        )

        let parent = DiskNode(
            recordIndex: 0,
            name: "parent", path: "/p",
            logicalSize: 0,
            physicalSize: 0,
            fileKind: .directory,
            isSystemProtected: false,
            modTimeSecs: 0,
            depth: 0,
            children: [child1, child2]
        )

        XCTAssertEqual(parent.totalLogicalSize, 300)

        // totalPhysicalSize is a stored field filled in by
        // DirectoryScannerBridge.computeTotalPhysicalSizes once the whole tree
        // exists — it is not derived on access, so it stays 0 until set.
        XCTAssertEqual(parent.totalPhysicalSize, 0)

        var summed = parent
        summed.totalPhysicalSize = parent.children!.reduce(0) { $0 + $1.physicalSize }
        XCTAssertEqual(summed.totalPhysicalSize, 150)
    }

    func testDiskNodeEqualityAndHashable() {
        let node1 = DiskNode(
            recordIndex: 1,
            name: "a", path: "/a",
            logicalSize: 1,
            physicalSize: 1,
            fileKind: .other,
            isSystemProtected: false,
            modTimeSecs: 0,
            depth: 0,
            children: nil
        )
        let node2 = DiskNode(
            recordIndex: 1,
            name: "a", path: "/a",
            logicalSize: 1,
            physicalSize: 1,
            fileKind: .other,
            isSystemProtected: false,
            modTimeSecs: 0,
            depth: 0,
            children: nil
        )
        let node3 = DiskNode(
            recordIndex: 2,
            name: "b", path: "/b",
            logicalSize: 1,
            physicalSize: 1,
            fileKind: .other,
            isSystemProtected: false,
            modTimeSecs: 0,
            depth: 0,
            children: nil
        )

        XCTAssertEqual(node1, node2)
        XCTAssertNotEqual(node1, node3)

        XCTAssertEqual(node1.hashValue, node2.hashValue)
        XCTAssertNotEqual(node1.hashValue, node3.hashValue)
    }
}
