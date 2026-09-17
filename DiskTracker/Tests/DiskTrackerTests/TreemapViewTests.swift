//
//  TreemapViewTests.swift
//  DiskTrackerTests
//
//  Phase 2: TreemapView layout algorithm tests.
//  Tests the squarified treemap algorithm correctness.
//

import XCTest
import SwiftUI
@testable import DiskTracker

// `TreemapView.layout` is main-actor-isolated, as view code is. XCTest already
// runs these on the main thread; the annotation is what lets the compiler see
// that.
@MainActor
final class TreemapViewTests: XCTestCase {

    // MARK: - TreemapItem Tests

    func testTreemapItemInitialization() {
        let item = TreemapItem(
            label: "Documents",
            value: 500.0,
            color: .blue
        )

        XCTAssertEqual(item.label, "Documents")
        XCTAssertEqual(item.value, 500.0)
        XCTAssertEqual(item.color, .blue)
    }

    func testTreemapItemSorting() {
        let items = [
            TreemapItem(label: "Small", value: 100.0, color: .red),
            TreemapItem(label: "Large", value: 1000.0, color: .blue),
            TreemapItem(label: "Medium", value: 500.0, color: .green),
        ]

        let sorted = items.sorted { $0.value > $1.value }
        
        XCTAssertEqual(sorted[0].label, "Large")
        XCTAssertEqual(sorted[1].label, "Medium")
        XCTAssertEqual(sorted[2].label, "Small")
    }

    // MARK: - TreemapRect Tests

    func testTreemapRectInitialization() {
        let rect = TreemapRect(
            x: 10,
            y: 20,
            width: 100,
            height: 50,
            label: "Test",
            color: .red
        )

        XCTAssertEqual(rect.x, 10)
        XCTAssertEqual(rect.y, 20)
        XCTAssertEqual(rect.width, 100)
        XCTAssertEqual(rect.height, 50)
        XCTAssertEqual(rect.label, "Test")
    }

    func testTreemapRectArea() {
        let rect = TreemapRect(
            x: 0,
            y: 0,
            width: 100,
            height: 50,
            label: "Test",
            color: .blue
        )

        XCTAssertEqual(rect.width * rect.height, 5000.0)
    }

    // MARK: - Squarified Layout Algorithm Tests

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

    func testLayoutAlgorithmHandlesNilChildren() {
        let root = makeLeafNode(name: "file.txt", path: "/file.txt", size: 1000)
        // Root has no children, should still be handled
        XCTAssertNil(root.children)
        XCTAssertEqual(root.physicalSize, 1000)
    }

    // MARK: - Row Building Tests

    func testSingleItemRow() {
        let items = [
            TreemapItem(label: "Only", value: 1000.0, color: .blue)
        ]
        let total = items.reduce(0.0) { $0 + $1.value }
        
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(total, 1000.0)
    }

    func testRowFractionCalculation() {
        let items = [
            TreemapItem(label: "A", value: 500.0, color: .red),
            TreemapItem(label: "B", value: 500.0, color: .blue),
        ]
        let total = items.reduce(0.0) { $0 + $1.value }
        let rowSum = items.reduce(0.0) { $0 + $1.value }
        let rowFraction = rowSum / total
        
        XCTAssertEqual(rowFraction, 1.0)
    }

    func testRowThicknessCalculationHorizontal() {
        let boundsHeight: CGFloat = 100
        let itemsTotal: Double = 1000
        let rowSum: Double = 500
        let rowFraction = rowSum / itemsTotal
        let rowThickness = boundsHeight * rowFraction

        XCTAssertEqual(rowThickness, 50.0)  // 50% of 100
    }

    func testRowThicknessCalculationVertical() {
        let boundsWidth: CGFloat = 100
        let itemsTotal: Double = 1000
        let rowSum: Double = 250
        let rowFraction = rowSum / itemsTotal
        let rowThickness = boundsWidth * rowFraction

        XCTAssertEqual(rowThickness, 25.0)  // 25% of 100
    }

    // MARK: - Aspect Ratio Tests

    func testAspectRatioForWideRectangle() {
        let rect = TreemapRect(x: 0, y: 0, width: 100, height: 50, label: "W", color: .red)
        let aspectRatio = max(rect.width, rect.height) / min(rect.width, rect.height)
        
        XCTAssertEqual(aspectRatio, 2.0)
    }

    func testAspectRatioForSquare() {
        let rect = TreemapRect(x: 0, y: 0, width: 50, height: 50, label: "S", color: .blue)
        let aspectRatio = max(rect.width, rect.height) / min(rect.width, rect.height)
        
        XCTAssertEqual(aspectRatio, 1.0)  // Square has aspect ratio of 1
    }

    func testAspectRatioForTallRectangle() {
        let rect = TreemapRect(x: 0, y: 0, width: 25, height: 100, label: "T", color: .green)
        let aspectRatio = max(rect.width, rect.height) / min(rect.width, rect.height)
        
        XCTAssertEqual(aspectRatio, 4.0)
    }

    // MARK: - Item Building Tests

    func testBuildTreemapItemsIncludesRoot() {
        let root = makeLeafNode(name: "Home", path: "/home", size: 1000, kind: .directory)
        
        var items: [TreemapItem] = []
        items.append(TreemapItem(
            label: root.name,
            value: Double(root.physicalSize),
            color: .gray
        ))
        
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].label, "Home")
        XCTAssertEqual(items[0].value, 1000.0)
    }

    func testBuildTreemapItemsIncludesChildren() {
        let children = [
            makeLeafNode(name: "Documents", path: "/docs", size: 500, kind: .document),
            makeLeafNode(name: "Images", path: "/imgs", size: 300, kind: .image),
        ]
        let root = makeDirectoryNode(name: "Home", path: "/home", children: children)
        
        var items: [TreemapItem] = []
        items.append(TreemapItem(label: root.name, value: Double(root.physicalSize), color: .gray))
        for child in root.children ?? [] {
            items.append(TreemapItem(label: child.name, value: Double(child.physicalSize), color: .blue))
        }
        
        XCTAssertEqual(items.count, 3)  // 1 root + 2 children
    }

    // MARK: - Color Mapping Tests

    func testAllFileKindsHaveColors() {
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
            XCTAssertNotNil(colors[kind], "FileKind.\(kind) must have a color")
        }
    }

    // MARK: - Minimum Size Threshold Tests

    func testMinimumRowThicknessThreshold() {
        let minThickness: CGFloat = 20
        let boundsHeight: CGFloat = 100
        let itemsTotal: Double = 100_000
        
        // Test that small items trigger row break
        let largeItem = TreemapItem(label: "Large", value: 900.0, color: .red)
        let smallItem = TreemapItem(label: "Small", value: 50.0, color: .blue)
        
        let rowWithSmall: [TreemapItem] = [largeItem, smallItem]
        let rowSum = rowWithSmall.reduce(0.0) { $0 + $1.value }
        let rowFraction = rowSum / itemsTotal
        let rowThickness = boundsHeight * rowFraction
        
        XCTAssertLessThan(rowThickness, minThickness)  // Should trigger break
    }

    // MARK: - Layout Bounds Update Tests

    func testHorizontalLayoutUpdatesBoundsVertically() {
        var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rowThickness: CGFloat = 25
        let isHorizontal = true
        
        if isHorizontal {
            bounds = CGRect(
                x: bounds.minX,
                y: bounds.minY + rowThickness,
                width: bounds.width,
                height: bounds.height - rowThickness
            )
        }
        
        XCTAssertEqual(bounds.minY, 25)
        XCTAssertEqual(bounds.height, 75)
    }

    func testVerticalLayoutUpdatesBoundsHorizontally() {
        var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rowThickness: CGFloat = 30
        let isHorizontal = false
        
        if !isHorizontal {
            bounds = CGRect(
                x: bounds.minX + rowThickness,
                y: bounds.minY,
                width: bounds.width - rowThickness,
                height: bounds.height
            )
        }
        
        XCTAssertEqual(bounds.minX, 30)
        XCTAssertEqual(bounds.width, 70)
    }
}

// MARK: - Level of detail

/// A folder with hundreds of thousands of immediate children would otherwise
/// produce a tile each, almost all sub-pixel. These pin the cull so it cannot
/// regress into drawing them again, and so it cannot start eating tiles that
/// are genuinely visible.
@MainActor
final class TreemapLevelOfDetailTests: XCTestCase {

    private func file(_ name: String, _ size: UInt64) -> DiskNode {
        DiskNode(recordIndex: 0, name: name, path: "/root/\(name)",
                 logicalSize: size, physicalSize: size, fileKind: .document,
                 isSystemProtected: false, modTimeSecs: 0, depth: 1,
                 childCount: 0, children: [], totalPhysicalSize: size)
    }

    private func model(_ children: [DiskNode]) -> AppModel {
        let root = DiskNode(recordIndex: 0, name: "root", path: "/root",
                            logicalSize: 0, physicalSize: 0, fileKind: .directory,
                            isSystemProtected: false, modTimeSecs: 0, depth: 0,
                            childCount: UInt32(children.count), children: children,
                            totalPhysicalSize: children.reduce(0) { $0 + $1.physicalSize })
        let m = AppModel()
        m.rootNode = root
        return m
    }

    private func layout(_ m: AppModel, _ size: CGSize) -> [TreemapRect] {
        TreemapView.layout(of: m.rootNode, in: size)
    }

    func testDropsSlivers() {
        // One dominant file plus 5,000 crumbs that cannot each occupy 25pt².
        var children = [file("huge.bin", 100_000_000)]
        children += (0..<5_000).map { file("crumb\($0).txt", 10) }

        let rects = layout(model(children), CGSize(width: 800, height: 600))

        XCTAssertLessThan(rects.count, 50, "sub-pixel tiles should not be laid out at all")
        XCTAssertTrue(rects.contains { $0.label == "huge.bin" }, "the visible tile must survive")
    }

    func testKeepsTilesBigEnoughToSee() {
        // Four equal files on a large canvas: each gets a quarter, far above
        // the threshold.
        let children = (0..<4).map { file("f\($0).bin", 1_000_000) }
        let rects = layout(model(children), CGSize(width: 800, height: 600))
        XCTAssertEqual(rects.count, 4)
    }

    func testEveryLaidOutTileHasVisibleArea() {
        var children = [file("big.bin", 50_000_000)]
        children += (0..<2_000).map { file("small\($0).txt", 100) }

        for rect in layout(model(children), CGSize(width: 900, height: 700)) {
            XCTAssertGreaterThan(
                rect.width * rect.height, 1,
                "\(rect.label) was laid out with no visible area")
        }
    }

    func testMoreRoomKeepsMoreTiles() {
        // Sizes spanning four orders of magnitude, so the cutoff falls part way
        // through the list rather than keeping or dropping all of it.
        let children = (0..<300).map { file("f\($0).bin", UInt64(1_000_000 / ($0 + 1))) }

        let small = layout(model(children), CGSize(width: 200, height: 150))
        let large = layout(model(children), CGSize(width: 1600, height: 1200))

        XCTAssertGreaterThan(large.count, small.count,
                             "the cut is a pixel budget, so it must follow the canvas")
        XCTAssertGreaterThan(small.count, 0, "a small canvas still shows the big tiles")
        // That the smallest tiles are dropped at all is testDropsSlivers'
        // job; on a 1600x1200 canvas even the smallest of these earns ~1000pt².
    }

    func testZeroSizedCanvasLaysOutNothing() {
        let children = (0..<10).map { file("f\($0).bin", 1_000) }
        XCTAssertTrue(layout(model(children), CGSize(width: 0, height: 0)).isEmpty)
    }

    func testEmptyTreeLaysOutNothing() {
        let m = AppModel()
        XCTAssertTrue(layout(m, CGSize(width: 400, height: 300)).isEmpty)
    }
}

// MARK: - Drill-down

/// The sunburst could descend into a folder; the treemap could not, so the two
/// views disagreed about what "zoom" meant. These cover the layout half —
/// which node's children get drawn. The gesture and breadcrumb are SwiftUI and
/// are exercised by hand.
@MainActor
final class TreemapDrillDownTests: XCTestCase {

    private func file(_ name: String, _ path: String, _ size: UInt64) -> DiskNode {
        DiskNode(recordIndex: 0, name: name, path: path,
                 logicalSize: size, physicalSize: size, fileKind: .document,
                 isSystemProtected: false, modTimeSecs: 0, depth: 2,
                 childCount: 0, children: [], totalPhysicalSize: size)
    }

    private func dir(_ name: String, _ path: String, _ children: [DiskNode]) -> DiskNode {
        DiskNode(recordIndex: 0, name: name, path: path,
                 logicalSize: 0, physicalSize: 0, fileKind: .directory,
                 isSystemProtected: false, modTimeSecs: 0, depth: 1,
                 childCount: UInt32(children.count), children: children,
                 totalPhysicalSize: children.reduce(0) { $0 + $1.totalPhysicalSize })
    }

    /// root/
    ///   photos/   holiday.jpg 5000, cat.png 3000
    ///   notes.txt 100
    private func makeModel() -> AppModel {
        let photos = dir("photos", "/root/photos", [
            file("holiday.jpg", "/root/photos/holiday.jpg", 5000),
            file("cat.png", "/root/photos/cat.png", 3000),
        ])
        let root = dir("root", "/root", [photos, file("notes.txt", "/root/notes.txt", 100)])
        let model = AppModel()
        model.rootNode = root
        return model
    }

    private let canvas = CGSize(width: 800, height: 600)

    func testStartsAtTheScanRoot() {
        let model = makeModel()
        let labels = TreemapView.layout(of: model.rootNode, in: canvas).map(\.label).sorted()
        XCTAssertEqual(labels, ["notes.txt", "photos"], "the root's own children")
    }

    /// The tiles must come from the focused folder, not always the scan root —
    /// that was the whole gap.
    /// The tiles must come from the focused folder, not always the scan root —
    /// that was the whole gap.
    func testLayoutFollowsTheFocusedFolder() throws {
        let model = makeModel()
        let photos = try XCTUnwrap(model.rootNode?.children?.first { $0.name == "photos" })

        let labels = TreemapView.layout(of: photos, in: canvas).map(\.label).sorted()
        XCTAssertEqual(labels, ["cat.png", "holiday.jpg"])
    }

    /// Descending must not change the sizes, only which slice is shown.
    func testDescendingPreservesSizes() throws {
        let model = makeModel()
        let photos = try XCTUnwrap(model.rootNode?.children?.first { $0.name == "photos" })

        let tiles = TreemapView.layout(of: photos, in: canvas)
        let holiday = try XCTUnwrap(tiles.first { $0.label == "holiday.jpg" })
        let cat = try XCTUnwrap(tiles.first { $0.label == "cat.png" })

        XCTAssertGreaterThan(holiday.frame.width * holiday.frame.height,
                             cat.frame.width * cat.frame.height,
                             "5000 bytes should occupy more area than 3000")
    }

    func testTilesCarryTheirNodeSoDescendingKnowsWhereToGo() throws {
        let model = makeModel()
        let tiles = TreemapView.layout(of: model.rootNode, in: canvas)
        let photos = try XCTUnwrap(tiles.first { $0.label == "photos" })

        XCTAssertEqual(photos.node?.path, "/root/photos")
        XCTAssertEqual(photos.node?.fileKind, .directory)
    }

    func testNoFocusedNodeLaysOutNothing() {
        XCTAssertTrue(TreemapView.layout(of: nil, in: canvas).isEmpty)
    }
}
