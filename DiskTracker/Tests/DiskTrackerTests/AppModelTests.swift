//
//  AppModelTests.swift
//  DiskTrackerTests
//
//  Phase 2: AppModel scan state management tests.
//  TDD RED test cases - these define expected behavior first.
//

import XCTest
import Foundation
@testable import DiskTracker

final class AppModelTests: XCTestCase {

    // MARK: - Test Data Helpers

    func makeLeafNode(name: String, path: String, size: UInt64 = 1024) -> DiskNode {
        DiskNode(
            recordIndex: 0,
            name: name,
            path: path,
            logicalSize: size,
            physicalSize: size,
            fileKind: .document,
            isSystemProtected: false,
            modTimeSecs: 0,
            depth: 0,
            children: nil
        )
    }

    func makeTreeNode(name: String, path: String, children: [DiskNode]) -> DiskNode {
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

    // MARK: - Scan State Tests

    func testInitialScanStateIsIdle() {
        let model = AppModel()
        guard case .idle = model.scanState else {
            XCTFail("Expected initial state to be .idle, got \(model.scanState)")
            return
        }
    }

    func testStartScanTransitionsToScanning() {
        let model = AppModel()
        model.startScan(path: "/test")
        
        guard case .scanning(let progress) = model.scanState else {
            XCTFail("Expected state to be .scanning, got \(model.scanState)")
            return
        }
        XCTAssertEqual(progress, 0.0)
    }

    func testStartScanRequiresIdleState() {
        let model = AppModel()
        model.startScan(path: "/test")
        // Starting a second scan should be ignored (already scanning)
        model.startScan(path: "/test2")
        
        // State should still be scanning, not changed by second call
        guard case .scanning = model.scanState else {
            XCTFail("Expected state to still be .scanning")
            return
        }
    }

    func testCancelScanResetsToIdle() {
        let model = AppModel()
        model.startScan(path: "/test")
        model.cancelScan()
        
        guard case .idle = model.scanState else {
            XCTFail("Expected state to be .idle after cancel, got \(model.scanState)")
            return
        }
    }

    func testCancelScanClearsRootNode() {
        let model = AppModel()
        model.startScan(path: "/test")
        model.cancelScan()
        
        XCTAssertNil(model.rootNode)
    }

    func testScanCompletionUpdatesState() {
        let model = AppModel()
        let expectation = XCTestExpectation(description: "Scan completes")
        
        model.startScan(path: "/test")
        
        // Wait for async scan to complete (synthetic scan takes 2 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard case .completed(let totalSize, let fileCount) = model.scanState else {
                XCTFail("Expected state to be .completed, got \(model.scanState)")
                return
            }
            XCTAssertGreaterThan(totalSize, 0)
            XCTAssertGreaterThan(fileCount, 0)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Selection Tests

    func testSelectNodeUpdatesSelectedNode() {
        let model = AppModel()
        let node = makeLeafNode(name: "test.txt", path: "/test/test.txt")
        
        model.selectNode(node)
        
        XCTAssertEqual(model.selectedNode?.name, "test.txt")
    }

    func testSelectNodeInBatchModeTogglesSelection() {
        let model = AppModel()
        model.isBatchMode = true
        let node = makeLeafNode(name: "test.txt", path: "/test/test.txt")
        
        model.selectNode(node)
        
        XCTAssertTrue(model.selectedNodes.contains(node.id))
    }

    func testToggleSelectionAddsAndRemoves() {
        let model = AppModel()
        model.isBatchMode = true
        let node = makeLeafNode(name: "test.txt", path: "/test/test.txt")
        
        model.toggleSelection(node)
        XCTAssertTrue(model.selectedNodes.contains(node.id))
        
        model.toggleSelection(node)
        XCTAssertFalse(model.selectedNodes.contains(node.id))
    }

    func testClearSelectionResetsAll() {
        let model = AppModel()
        model.isBatchMode = true
        let node1 = makeLeafNode(name: "a.txt", path: "/a.txt")
        let node2 = makeLeafNode(name: "b.txt", path: "/b.txt")
        
        model.toggleSelection(node1)
        model.toggleSelection(node2)
        XCTAssertEqual(model.selectedNodes.count, 2)
        
        model.clearSelection()
        
        XCTAssertTrue(model.selectedNodes.isEmpty)
        XCTAssertNil(model.selectedNode)
    }

    // MARK: - View Mode Tests

    func testDefaultViewModeIsSunburst() {
        let model = AppModel()
        XCTAssertEqual(model.currentView, .sunburst)
    }

    func testViewModeSwitching() {
        let model = AppModel()
        
        model.currentView = .treemap
        XCTAssertEqual(model.currentView, .treemap)
        
        model.currentView = .list
        XCTAssertEqual(model.currentView, .list)
        
        model.currentView = .sunburst
        XCTAssertEqual(model.currentView, .sunburst)
    }

    // MARK: - Hidden Files Toggle Tests

    func testShowHiddenFilesDefaultsToFalse() {
        let model = AppModel()
        XCTAssertFalse(model.showHiddenFiles)
    }

    func testHiddenFilesToggleTriggersCallback() {
        let model = AppModel()
        var callbackCount = 0
        model.onHiddenFilesChanged = { callbackCount += 1 }
        
        model.showHiddenFiles = true
        XCTAssertEqual(callbackCount, 1)
        
        model.showHiddenFiles = false
        XCTAssertEqual(callbackCount, 2)
    }

    func testSameValueDoesNotTriggerCallback() {
        let model = AppModel()
        var callbackCount = 0
        model.onHiddenFilesChanged = { callbackCount += 1 }
        
        model.showHiddenFiles = true
        model.showHiddenFiles = true  // Same value
        XCTAssertEqual(callbackCount, 1)  // Only triggered once
    }

    // MARK: - Tree Stats Tests

    func testTreeStatsReturnsZerosWhenNoRoot() {
        let model = AppModel()
        let stats = model.treeStats
        
        XCTAssertEqual(stats.totalFiles, 0)
        XCTAssertEqual(stats.totalDirectories, 0)
        XCTAssertEqual(stats.totalSize, 0)
    }

    // MARK: - Smart Filter Tests

    func testSmartFilterConfigDefaults() {
        let model = AppModel()

        XCTAssertEqual(model.smartFilterConfig.largeFileThresholdGB, 1.0)  // 1GB default
        XCTAssertEqual(model.smartFilterConfig.oldFileThresholdMonths, 6)  // 6 months default
    }

    func testActiveSmartFilterDefaultsToNil() {
        let model = AppModel()
        XCTAssertNil(model.activeSmartFilter)
    }

    func testRunSmartFilterWithNoRootDoesNothing() {
        let model = AppModel()
        
        model.activeSmartFilter = .large
        model.runSmartFilter()
        
        XCTAssertTrue(model.smartFilterResults.isEmpty)
    }
}
