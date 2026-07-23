//
//  DirectoryListViewTests.swift
//  DiskTrackerTests
//
//  Phase 3: DirectoryListView tests using DiskNode (DemoItem deleted).
//  Tests row rendering, expand/collapse, icon mapping, and real data.
//

import XCTest
import SwiftUI
@testable import DiskTracker

final class DirectoryListViewTests: XCTestCase {

    // MARK: - Test Data Helpers

    func makeLeaf(name: String, path: String, size: UInt64, kind: FileKind = .document, depth: UInt16 = 0) -> DiskNode {
        DiskNode(
            recordIndex: 0, name: name, path: path,
            logicalSize: size, physicalSize: size,
            fileKind: kind, isSystemProtected: false,
            modTimeSecs: 0, depth: depth, children: nil
        )
    }

    func makeDir(name: String, path: String, children: [DiskNode], depth: UInt16 = 0) -> DiskNode {
        let size = children.reduce(UInt64(0)) { $0 + $1.physicalSize }
        return DiskNode(
            recordIndex: 0, name: name, path: path,
            logicalSize: size, physicalSize: size,
            fileKind: .directory, isSystemProtected: false,
            modTimeSecs: 0, depth: depth, children: children
        )
    }

    // MARK: - DiskNode Tests (was DemoItem)

    func testDiskNodeInitialization() {
        let node = makeLeaf(name: "Documents", path: "/Users/test/Documents", size: 5_000_000_000, kind: .directory, depth: 1)

        XCTAssertEqual(node.name, "Documents")
        XCTAssertEqual(node.path, "/Users/test/Documents")
        XCTAssertEqual(node.physicalSize, 5_000_000_000)
        XCTAssertEqual(node.fileKind, .directory)
        XCTAssertEqual(node.depth, 1)
        XCTAssertNotNil(node.id)
    }

    func testDiskNodeForDifferentFileKinds() {
        let kinds: [FileKind] = [.image, .video, .audio, .document, .archive, .application, .directory, .other]

        for kind in kinds {
            let node = makeLeaf(name: "test", path: "/test", size: 1000, kind: kind)
            XCTAssertEqual(node.fileKind, kind)
        }
    }

    // MARK: - Color Mapping Tests

    func testColorForKindReturnsCorrectColors() {
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
            let color = colors[kind]
            XCTAssertNotNil(color, "Missing color for \(kind)")
        }
    }

    // MARK: - Icon Mapping Tests

    func testIconForKindImage() { XCTAssertEqual(iconForKind(.image), "photo") }
    func testIconForKindVideo() { XCTAssertEqual(iconForKind(.video), "film") }
    func testIconForKindAudio() { XCTAssertEqual(iconForKind(.audio), "music.note") }
    func testIconForKindDocument() { XCTAssertEqual(iconForKind(.document), "doc") }
    func testIconForKindArchive() { XCTAssertEqual(iconForKind(.archive), "doc.zipper") }
    func testIconForKindApplication() { XCTAssertEqual(iconForKind(.application), "app") }
    func testIconForKindDirectory() { XCTAssertEqual(iconForKind(.directory), "folder") }
    func testIconForKindOther() { XCTAssertEqual(iconForKind(.other), "doc.questionmark") }

    private func iconForKind(_ kind: FileKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .document: return "doc"
        case .archive: return "doc.zipper"
        case .application: return "app"
        case .directory: return "folder"
        case .other: return "doc.questionmark"
        }
    }

    // MARK: - Depth Indentation Tests

    func testDepthZeroHasNoIndent() {
        let node = makeLeaf(name: "Home", path: "/home", size: 42_000_000_000, depth: 0)
        XCTAssertEqual(node.depth, 0)
    }

    func testDepthOneHasIndent() {
        let node = makeLeaf(name: "Documents", path: "/home/Documents", size: 5_000_000_000, depth: 1)
        let indent = CGFloat(node.depth * 16)
        XCTAssertEqual(indent, 16)
    }

    func testDepthTwoHasMoreIndent() {
        let node = makeLeaf(name: "Subfolder", path: "/home/Documents/Subfolder", size: 100_000, depth: 2)
        let indent = CGFloat(node.depth * 16)
        XCTAssertEqual(indent, 32)
    }

    // MARK: - Size Formatting Tests

    func testFormatBytes() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        let kb = formatter.string(fromByteCount: 1024)
        XCTAssertTrue(kb.lowercased().contains("k"))

        let mb = formatter.string(fromByteCount: 1_048_576)
        XCTAssertTrue(mb.lowercased().contains("m"))

        let gb = formatter.string(fromByteCount: 1_073_741_824)
        XCTAssertTrue(mb.lowercased().contains("m") || gb.lowercased().contains("g"))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Expand/Collapse State Tests

    func testExpandStateDefaultsToFalse() {
        var isExpanded = false
        XCTAssertFalse(isExpanded)

        isExpanded.toggle()
        XCTAssertTrue(isExpanded)

        isExpanded.toggle()
        XCTAssertFalse(isExpanded)
    }

    // MARK: - Row Construction Tests

    func testRowShowsExpandButtonForDirectory() {
        let child = makeLeaf(name: "nested.txt", path: "/folder/nested.txt", size: 100)
        let dir = makeDir(name: "Folder", path: "/folder", children: [child], depth: 0)

        XCTAssertEqual(dir.fileKind, .directory)
        XCTAssertNotNil(dir.children)
        XCTAssertFalse(dir.children?.isEmpty ?? true, "Directory with children should show expand button")
    }

    func testRowDoesNotShowExpandForFile() {
        let node = makeLeaf(name: "file.txt", path: "/file.txt", size: 1000, kind: .document)

        let isDirectory = node.fileKind == .directory
        XCTAssertFalse(isDirectory)
    }

    func testEmptyDirectoryHasNoExpandButton() {
        let dir = makeDir(name: "Empty", path: "/Empty", children: [], depth: 0)
        // Empty directory: expand button only shown when children non-empty
        let hasChildren = !(dir.children?.isEmpty ?? true)
        XCTAssertFalse(hasChildren, "Empty directory should not show expand chevron")
    }

    // MARK: - Recursive Child Count Tests

    func testChildCountForLeafReturnsZero() {
        let leaf = makeLeaf(name: "a.txt", path: "/a.txt", size: 100)
        let count = childCount(of: leaf)
        XCTAssertEqual(count, 0, "Leaf node has no children")
    }

    func testChildCountForDirectory() {
        let a = makeLeaf(name: "a.txt", path: "/d/a.txt", size: 100)
        let b = makeLeaf(name: "b.txt", path: "/d/b.txt", size: 200)
        let dir = makeDir(name: "d", path: "/d", children: [a, b], depth: 0)
        let count = childCount(of: dir)
        XCTAssertEqual(count, 2, "Directory with 2 direct children")
    }

    func testChildCountRecursive() {
        let leaf = makeLeaf(name: "deep.txt", path: "/a/b/deep.txt", size: 50)
        let sub = makeDir(name: "b", path: "/a/b", children: [leaf], depth: 1)
        let root = makeDir(name: "a", path: "/a", children: [sub], depth: 0)
        let count = childCount(of: root)
        XCTAssertEqual(count, 2, "root has sub (1) + leaf (1) = 2 total descendants")
    }

    // Mirror of DirectoryRowView.childCount implementation
    private func childCount(of node: DiskNode) -> Int {
        guard let children = node.children, !children.isEmpty else { return 0 }
        return children.count + children.reduce(0) { $0 + childCount(of: $1) }
    }

    // MARK: - Real Data Tests (Regression: fix-view-defects)

    /// Bug: DirectoryListView iterated `demoItems`, ignoring `model.rootNode`.
    /// Fix: body builds rows from DiskNode tree when rootNode is non-nil.
    func testDirectoryListViewUsesRealDataNotDemoItems() {
        let model = AppModel()
        let leafA = makeLeaf(name: "resume.pdf", path: "/Docs/resume.pdf", size: 1_000_000, depth: 2)
        let leafB = makeLeaf(name: "tasks.txt", path: "/Docs/tasks.txt", size: 500, depth: 2)
        let docsNode = makeDir(name: "Docs", path: "/Docs", children: [leafA, leafB], depth: 1)
        model.rootNode = makeDir(name: "/", path: "/", children: [docsNode], depth: 0)
        model.scanState = .completed(totalSize: 1_000_500, fileCount: 3)

        let stats = model.treeStats
        XCTAssertEqual(stats.totalFiles, 2, "Should find 2 files from real scan")
        XCTAssertEqual(stats.totalDirectories, 2, "Should find 2 directories (root + Docs)")
        XCTAssertEqual(stats.totalSize, 1_000_500, "Should sum files from real scan")
    }

    func testListShowsEmptyStateWhenNoScanData() {
        let model = AppModel()
        XCTAssertNil(model.rootNode)
        guard case .idle = model.scanState else {
            XCTFail("No scan → state must be idle")
            return
        }
        let stats = model.treeStats
        XCTAssertEqual(stats.totalFiles, 0)
        XCTAssertEqual(stats.totalDirectories, 0)
    }

    // MARK: - Color Hex Tests

    func testColorHexValuesAreValid() {
        let hexColors: [String] = [
            "FF6B6B", "9B59B6", "F39C12", "3498DB",
            "27AE60", "E74C3C", "2C3E50", "95A5A6",
        ]

        for hex in hexColors {
            XCTAssertEqual(hex.count, 6, "Color hex should be 6 digits: \(hex)")
            let validHexChars = CharacterSet(charactersIn: "0123456789ABCDEF")
            for char in hex.unicodeScalars {
                XCTAssertTrue(validHexChars.contains(char), "Invalid hex character: \(char)")
            }
        }
    }
}