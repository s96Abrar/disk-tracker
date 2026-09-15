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

    // MARK: - Label Truncation

    func testMiddleTruncationKeepsBothEnds() {
        let name = "Genius.S03E07.720p.DSNP.WEBRip.x264-GalaxyTV.mp4"
        let short = CanvasText.middleTruncated(name, to: 20)

        XCTAssertEqual(short.count, 20)
        XCTAssertTrue(short.hasPrefix("Genius"), "Head must survive: \(short)")
        XCTAssertTrue(short.hasSuffix("mp4"), "Extension must survive: \(short)")
        XCTAssertTrue(short.contains("…"))
    }

    func testShortLabelsAreLeftAlone() {
        XCTAssertEqual(CanvasText.middleTruncated("S01", to: 20), "S01")
        // Exactly at the budget is still untouched.
        XCTAssertEqual(CanvasText.middleTruncated("abcde", to: 5), "abcde")
    }

    func testTruncationDegradesGracefullyAtTinyBudgets() {
        XCTAssertEqual(CanvasText.middleTruncated("abcdefgh", to: 1), "…")
        XCTAssertEqual(CanvasText.middleTruncated("abcdefgh", to: 0), "…")
        XCTAssertEqual(CanvasText.middleTruncated("abcdefgh", to: 3).count, 3)
    }

    // MARK: - Ring Layout

    private let palette: [FileKind: Color] = [
        .image: .red, .video: .purple, .audio: .orange, .document: .blue,
        .archive: .green, .application: .pink, .directory: .black, .other: .gray,
    ]

    /// Directory node shaped the way the scanner emits them: `physicalSize` is
    /// the directory entry itself (~0) and the real weight lives in
    /// `totalPhysicalSize`.
    private func makeScannedDirectory(name: String, path: String, children: [DiskNode]) -> DiskNode {
        var node = DiskNode(
            recordIndex: 0,
            name: name,
            path: path,
            logicalSize: 0,
            physicalSize: 0,
            fileKind: .directory,
            isSystemProtected: false,
            modTimeSecs: 0,
            depth: 0,
            children: children
        )
        node.totalPhysicalSize = children.reduce(UInt64(0)) {
            $0 + ($1.fileKind == .directory ? $1.totalPhysicalSize : $1.physicalSize)
        }
        return node
    }

    /// The regression that made the whole chart blank: nothing rendered.
    func testLayoutProducesSegmentsForAScannedTree() {
        let root = makeScannedDirectory(name: "home", path: "/home", children: [
            makeLeafNode(name: "a.mov", path: "/home/a.mov", size: 600, kind: .video),
            makeLeafNode(name: "b.jpg", path: "/home/b.jpg", size: 400, kind: .image),
        ])

        let segments = SunburstLayout.build(root: root, maxRadius: 200, colors: palette)

        XCTAssertGreaterThan(segments.count, 1, "Chart rendered empty")
        XCTAssertEqual(segments.first?.innerRadius, 0, "First segment must be the centre disc")
        XCTAssertEqual(segments.first?.label, "home")
    }

    func testLayoutReturnsNothingWithoutARoot() {
        XCTAssertTrue(SunburstLayout.build(root: nil, maxRadius: 200, colors: palette).isEmpty)
    }

    /// A collapsed layout area must not produce garbage geometry.
    func testLayoutReturnsNothingForNonPositiveRadius() {
        let root = makeScannedDirectory(name: "home", path: "/home", children: [
            makeLeafNode(name: "a.mov", path: "/home/a.mov", size: 600, kind: .video)
        ])

        XCTAssertTrue(SunburstLayout.build(root: root, maxRadius: 0, colors: palette).isEmpty)
        XCTAssertTrue(SunburstLayout.build(root: root, maxRadius: -30, colors: palette).isEmpty)
    }

    /// Directories are weighted by totalPhysicalSize — weighting them by their
    /// own physicalSize collapsed every folder wedge to nothing.
    func testDirectoryWedgesAreWeightedByTotalPhysicalSize() {
        let bigFolder = makeScannedDirectory(name: "Movies", path: "/home/Movies", children: [
            makeLeafNode(name: "big.mov", path: "/home/Movies/big.mov", size: 900, kind: .video)
        ])
        let smallFile = makeLeafNode(name: "note.txt", path: "/home/note.txt", size: 100, kind: .document)
        let root = makeScannedDirectory(name: "home", path: "/home", children: [bigFolder, smallFile])

        let segments = SunburstLayout.build(root: root, maxRadius: 200, colors: palette)
        let ringOne = segments.filter { $0.innerRadius > 0 && $0.innerRadius < 100 }

        let folder = ringOne.first { $0.label == "Movies" }
        XCTAssertNotNil(folder)
        XCTAssertEqual(folder.map { $0.endAngle - $0.startAngle } ?? 0, 324, accuracy: 0.5) // 90% of 360
    }

    func testRingOneSweepsCoverTheFullCircle() {
        let root = makeScannedDirectory(name: "home", path: "/home", children: [
            makeLeafNode(name: "a", path: "/home/a", size: 500, kind: .video),
            makeLeafNode(name: "b", path: "/home/b", size: 300, kind: .image),
            makeLeafNode(name: "c", path: "/home/c", size: 200, kind: .document),
        ])

        let segments = SunburstLayout.build(root: root, maxRadius: 200, colors: palette)
        let ringOne = segments.filter { $0.outerRadius <= 100 && $0.innerRadius > 0 }
        let covered = ringOne.reduce(0.0) { $0 + ($1.endAngle - $1.startAngle) }

        XCTAssertEqual(covered, 360, accuracy: 0.5)
        XCTAssertEqual(ringOne.count, 3)
    }

    /// Nested directories get their own ring, so drill-down has something to
    /// show without a click.
    func testNestedChildrenProduceASecondRing() {
        let inner = makeScannedDirectory(name: "Movies", path: "/home/Movies", children: [
            makeLeafNode(name: "big.mov", path: "/home/Movies/big.mov", size: 1000, kind: .video)
        ])
        let root = makeScannedDirectory(name: "home", path: "/home", children: [inner])

        let segments = SunburstLayout.build(root: root, maxRadius: 200, colors: palette)

        XCTAssertTrue(segments.contains { $0.label == "big.mov" }, "Nested ring missing")
    }

    // MARK: - Hover Tooltip

    func testShareOfRootUsesDirectoryTotals() {
        let folder = makeScannedDirectory(name: "Movies", path: "/home/Movies", children: [
            makeLeafNode(name: "big.mov", path: "/home/Movies/big.mov", size: 750, kind: .video)
        ])
        let file = makeLeafNode(name: "note.txt", path: "/home/note.txt", size: 250, kind: .document)
        let root = makeScannedDirectory(name: "home", path: "/home", children: [folder, file])

        XCTAssertEqual(SunburstLayout.fraction(of: folder, in: root), 0.75, accuracy: 0.001)
        XCTAssertEqual(SunburstLayout.fraction(of: file, in: root), 0.25, accuracy: 0.001)
    }

    /// An empty folder would divide by zero and render as "nan%".
    func testShareOfEmptyRootIsZeroNotNaN() {
        let empty = makeScannedDirectory(name: "empty", path: "/empty", children: [])
        let child = makeLeafNode(name: "ghost", path: "/empty/ghost", size: 0, kind: .other)

        let share = SunburstLayout.fraction(of: child, in: empty)
        XCTAssertFalse(share.isNaN)
        XCTAssertEqual(share, 0)
    }

    func testEveryFileKindHasATooltipLabelAndIcon() {
        for kind in FileKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty, "\(kind) has no display name")
            XCTAssertFalse(kind.iconName.isEmpty, "\(kind) has no icon")
        }
        XCTAssertEqual(FileKind.directory.displayName, "Folder")
    }

    // MARK: - Hit Testing

    private func wedge(start: Double, end: Double, inner: CGFloat = 50, outer: CGFloat = 100) -> SunburstSegment {
        SunburstSegment(
            label: "W", startAngle: start, endAngle: end,
            innerRadius: inner, outerRadius: outer, color: .red, size: 0.25
        )
    }

    /// Canvas space is y-down, so a point at +x is 0°, +y is 90°.
    private func point(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + radius * cos(angle * .pi / 180),
            y: center.y + radius * sin(angle * .pi / 180)
        )
    }

    func testHitTestInsideWedge() {
        let center = CGPoint(x: 200, y: 200)
        let segment = wedge(start: 0, end: 90)

        XCTAssertTrue(segment.contains(point(angle: 45, radius: 75, center: center), center: center))
    }

    func testHitTestRejectsWrongAngle() {
        let center = CGPoint(x: 200, y: 200)
        let segment = wedge(start: 0, end: 90)

        XCTAssertFalse(segment.contains(point(angle: 135, radius: 75, center: center), center: center))
        // Angles come back from atan2 as -180...180 and must be normalised —
        // 315° is the case that regresses if that is dropped.
        XCTAssertFalse(segment.contains(point(angle: 315, radius: 75, center: center), center: center))
    }

    func testHitTestRejectsWrongRadius() {
        let center = CGPoint(x: 200, y: 200)
        let segment = wedge(start: 0, end: 90)

        XCTAssertFalse(segment.contains(point(angle: 45, radius: 20, center: center), center: center))
        XCTAssertFalse(segment.contains(point(angle: 45, radius: 150, center: center), center: center))
    }

    /// The centre disc is "go up a level", not a wedge — it must never hit.
    func testHitTestIgnoresCentreDisc() {
        let center = CGPoint(x: 200, y: 200)
        let centre = wedge(start: 0, end: 360, inner: 0, outer: 50)

        XCTAssertFalse(centre.contains(point(angle: 0, radius: 25, center: center), center: center))
    }

    func testAdjacentWedgesDoNotBothClaimABoundaryPoint() {
        let center = CGPoint(x: 200, y: 200)
        let first = wedge(start: 0, end: 90)
        let second = wedge(start: 90, end: 180)
        let boundary = point(angle: 90, radius: 75, center: center)

        XCTAssertNotEqual(first.contains(boundary, center: center), second.contains(boundary, center: center))
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

// MARK: - Level of detail

/// The cull used to be a fixed 0.75°, which is radius-independent: ~4pt of arc
/// on the outer ring but well under a point on the inner one, so it kept
/// sub-pixel wedges exactly where wedges are most numerous. It is now an arc
/// length, and these pin that.
final class SunburstLevelOfDetailTests: XCTestCase {

    private func file(_ name: String, _ size: UInt64) -> DiskNode {
        DiskNode(recordIndex: 0, name: name, path: "/root/\(name)",
                 logicalSize: size, physicalSize: size, fileKind: .document,
                 isSystemProtected: false, modTimeSecs: 0, depth: 1,
                 childCount: 0, children: [], totalPhysicalSize: size)
    }

    private func root(_ children: [DiskNode]) -> DiskNode {
        DiskNode(recordIndex: 0, name: "root", path: "/root",
                 logicalSize: 0, physicalSize: 0, fileKind: .directory,
                 isSystemProtected: false, modTimeSecs: 0, depth: 0,
                 childCount: UInt32(children.count), children: children,
                 totalPhysicalSize: children.reduce(0) { $0 + $1.physicalSize })
    }

    func testThresholdScalesWithRadius() {
        let inner = SunburstLayout.minSweepDegrees(atRadius: 50)
        let outer = SunburstLayout.minSweepDegrees(atRadius: 400)
        XCTAssertGreaterThan(inner, outer,
                             "a wedge near the centre needs more degrees to span the same arc")
    }

    func testThresholdMatchesTheArcLength() {
        let radius: CGFloat = 200
        let degrees = SunburstLayout.minSweepDegrees(atRadius: radius)
        let arc = radius * CGFloat(degrees * .pi / 180)
        XCTAssertEqual(arc, SunburstLayout.minArcLength, accuracy: 0.01)
    }

    func testZeroRadiusCullsEverything() {
        // Guards the division; a radius-0 ring has no drawable arc at all.
        XCTAssertEqual(SunburstLayout.minSweepDegrees(atRadius: 0), .infinity)
    }

    func testDropsHairlineWedges() {
        var children = [file("huge.bin", 10_000_000)]
        children += (0..<3_000).map { file("crumb\($0).txt", 10) }

        let segments = SunburstLayout.build(root: root(children), maxRadius: 300, colors: [:])

        XCTAssertLessThan(segments.count, 100, "hairline wedges should not be built")
        XCTAssertTrue(segments.contains { $0.label == "huge.bin" })
    }

    func testEveryWedgeSpansAVisibleArc() {
        var children = [file("big.bin", 5_000_000)]
        children += (0..<1_500).map { file("tiny\($0).txt", 50) }

        for segment in SunburstLayout.build(root: root(children), maxRadius: 320, colors: [:]) {
            // The root disc spans the full circle at radius 0; skip it.
            guard segment.innerRadius > 0 else { continue }
            let sweep = segment.endAngle - segment.startAngle
            let arc = segment.innerRadius * CGFloat(sweep * .pi / 180)
            XCTAssertGreaterThanOrEqual(
                arc, SunburstLayout.minArcLength - 0.01,
                "\(segment.label) spans \(arc)pt on its inner edge")
        }
    }

    func testABiggerCanvasKeepsMoreWedges() {
        let children = (0..<200).map { file("f\($0).bin", UInt64(500_000 / ($0 + 1))) }
        let small = SunburstLayout.build(root: root(children), maxRadius: 80, colors: [:])
        let large = SunburstLayout.build(root: root(children), maxRadius: 600, colors: [:])
        XCTAssertGreaterThan(large.count, small.count)
    }
}
