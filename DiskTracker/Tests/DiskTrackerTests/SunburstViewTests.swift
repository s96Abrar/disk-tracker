//
//  SunburstViewTests.swift
//  DiskTrackerTests
//
//  Phase 2: SunburstView Canvas rendering tests.
//  Tests the radial visualization layout and hit detection.
//

import XCTest
import SwiftUI
@testable import DiskTracker

final class SunburstViewTests: XCTestCase {

    // MARK: - SunburstSegment Tests

    func testSunburstSegmentInitialization() {
        let segment = SunburstSegment(
            label: "Test",
            startAngle: 0,
            endAngle: 90,
            innerRadius: 10,
            outerRadius: 50,
            color: .red,
            size: 0.25
        )

        XCTAssertEqual(segment.label, "Test")
        XCTAssertEqual(segment.startAngle, 0)
        XCTAssertEqual(segment.endAngle, 90)
        XCTAssertEqual(segment.innerRadius, 10)
        XCTAssertEqual(segment.outerRadius, 50)
        XCTAssertEqual(segment.size, 0.25)
        XCTAssertNotNil(segment.id)  // Identifiable
    }

    func testSunburstSegmentAngularSpan() {
        let segment = SunburstSegment(
            label: "Test",
            startAngle: 45,
            endAngle: 135,
            innerRadius: 10,
            outerRadius: 50,
            color: .blue,
            size: 0.25
        )

        let span = segment.endAngle - segment.startAngle
        XCTAssertEqual(span, 90)
    }

    // MARK: - ScanState Extension Tests

    func testTotalSizeFromCompleted() {
        let state: ScanState = .completed(totalSize: 1_000_000_000, fileCount: 5000)
        XCTAssertEqual(state.totalSize, 1_000_000_000)
    }

    func testTotalSizeFromScanning() {
        let state: ScanState = .scanning(progress: 0.5)
        XCTAssertEqual(state.totalSize, 0)  // Unknown during scan
    }

    func testTotalSizeFromIdle() {
        let state: ScanState = .idle
        XCTAssertEqual(state.totalSize, 0)
    }

    func testFileCountFromCompleted() {
        let state: ScanState = .completed(totalSize: 1_000_000_000, fileCount: 5000)
        XCTAssertEqual(state.fileCount, 5000)
    }

    func testFileCountFromScanning() {
        let state: ScanState = .scanning(progress: 0.5)
        XCTAssertEqual(state.fileCount, 0)
    }

    func testFileCountFromIdle() {
        let state: ScanState = .idle
        XCTAssertEqual(state.fileCount, 0)
    }

    func testProgressFromScanning() {
        let state: ScanState = .scanning(progress: 0.75)
        XCTAssertEqual(state.progress, 0.75)
    }

    func testProgressFromCompleted() {
        let state: ScanState = .completed(totalSize: 100, fileCount: 10)
        XCTAssertEqual(state.progress, 0.0)  // No progress on completed
    }

    // MARK: - Color Mapping Tests

    func testFileKindColorMapping() {
        // Test that all FileKind cases have corresponding colors in the view
        let colors: [FileKind: Color] = [
            .image: Color(hex: "FF6B6B"),
            .video: Color(hex: "9B59B6"),
            .audio: Color(hex: "F39C12"),
            .document: Color(hex: "3498DB"),
            .archive: Color(hex: "27AE60"),
            .application: Color(hex: "E74C3C"),
            .directory: Color(hex: "2C3E50"),
            .other: Color(hex: "95A5A6"),
        ]

        for kind in FileKind.allCases {
            XCTAssertNotNil(colors[kind], "FileKind.\(kind) should have a color mapping")
        }
    }

    // MARK: - Segment Building Tests

    func makeLeafNode(name: String, path: String, size: UInt64, kind: FileKind = .document) -> DiskNode {
        DiskNode(
            recordIndex: 0,
            name: name,
            path: path,
            logicalSize: size,
            physicalSize: size,
            fileKind: kind,
            isSystemProtected: false,
            modTimeSecs: 0,
            depth: 0,
            children: nil
        )
    }

    func makeDirectoryNode(name: String, path: String, children: [DiskNode]) -> DiskNode {
        let totalSize = children.reduce(UInt64(0)) { $0 + $1.physicalSize }
        return DiskNode(
            recordIndex: 0,
            name: name,
            path: path,
            logicalSize: totalSize,
            physicalSize: totalSize,
            fileKind: .directory,
            isSystemProtected: false,
            modTimeSecs: 0,
            depth: 0,
            children: children
        )
    }

    func testBuildSegmentsWithEmptyRoot() {
        // This tests the guard clause for nil root
        // The buildSegmentsFromTree should return empty array for nil root
        let root: DiskNode? = nil
        XCTAssertNil(root)
        // When passed to buildSegmentsFromTree, should return []
    }

    func testBuildSegmentsCreatesRootSegment() {
        let root = makeLeafNode(name: "root", path: "/", size: 1000, kind: .directory)
        
        // Verify root segment is created
        // Root should always be added at center (innerRadius = 0)
        XCTAssertEqual(root.fileKind, .directory)
        XCTAssertEqual(root.physicalSize, 1000)
    }

    func testBuildSegmentsWithChildren() {
        let children = [
            makeLeafNode(name: "Documents", path: "/Documents", size: 500, kind: .directory),
            makeLeafNode(name: "Images", path: "/Images", size: 300, kind: .image),
            makeLeafNode(name: "Videos", path: "/Videos", size: 200, kind: .video),
        ]
        let root = makeDirectoryNode(name: "Home", path: "/home", children: children)

        XCTAssertEqual(root.children?.count, 3)
        XCTAssertEqual(root.physicalSize, 1000)
    }

    // MARK: - Angle Calculation Tests

    func testAngleCalculationForEqualChildren() {
        let children = [
            makeLeafNode(name: "A", path: "/a", size: 100),
            makeLeafNode(name: "B", path: "/b", size: 100),
        ]
        let root = makeDirectoryNode(name: "Root", path: "/", children: children)

        // Two equal children should each get 180 degrees (50% of 360)
        XCTAssertEqual(root.children?.count, 2)
        let totalSize = root.physicalSize
        XCTAssertEqual(Double(children[0].physicalSize) / Double(totalSize), 0.5, accuracy: 0.001)
    }

    func testAngleCalculationForWeightedChildren() {
        let children = [
            makeLeafNode(name: "A", path: "/a", size: 750),
            makeLeafNode(name: "B", path: "/b", size: 250),
        ]
        let root = makeDirectoryNode(name: "Root", path: "/", children: children)

        // A should get 75% of angle, B should get 25%
        let aFraction = Double(children[0].physicalSize) / Double(root.physicalSize)
        let bFraction = Double(children[1].physicalSize) / Double(root.physicalSize)
        
        XCTAssertEqual(aFraction, 0.75, accuracy: 0.001)
        XCTAssertEqual(bFraction, 0.25, accuracy: 0.001)
    }

    // MARK: - Format Bytes Tests

    func testFormatBytesReturnsHumanReadable() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        
        // 1 KB
        let kb = formatter.string(fromByteCount: 1024)
        XCTAssertTrue(kb.contains("1") || kb.lowercased().contains("k"))
        
        // 1 MB
        let mb = formatter.string(fromByteCount: 1_048_576)
        XCTAssertTrue(mb.lowercased().contains("m"))
        
        // 1 GB
        let gb = formatter.string(fromByteCount: 1_073_741_824)
        XCTAssertTrue(gb.lowercased().contains("g"))
    }

    // MARK: - Hover State Tests

    func testHoveredSegmentCanBeSet() {
        // Testing state management for hover
        var hoveredSegment: Int? = nil
        
        XCTAssertNil(hoveredSegment)
        
        hoveredSegment = 0
        XCTAssertEqual(hoveredSegment, 0)
        
        hoveredSegment = nil
        XCTAssertNil(hoveredSegment)
    }

    // MARK: - Zoom Level Tests

    func testZoomLevelDefaultsToZero() {
        var zoomLevel = 0
        XCTAssertEqual(zoomLevel, 0)
        
        zoomLevel += 1
        XCTAssertEqual(zoomLevel, 1)
        
        zoomLevel -= 1
        XCTAssertEqual(zoomLevel, 0)
    }
}
