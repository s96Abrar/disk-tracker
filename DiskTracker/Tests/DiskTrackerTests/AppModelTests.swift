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

        model.startScan(path: NSHomeDirectory())

        // Wait for async scan to complete
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

    // MARK: - Re-scan Tests (Regression: fix-view-defects)

    /// Bug: startScan guards on `.idle` only. After a scan completes (state = .completed),
    /// subsequent calls are silently dropped. User cannot re-scan without manually cancelling first.
    /// Fix: startScan should accept `.idle`, `.completed`, and `.failed` as entry states.
    func testReScanAllowedAfterCompletion() {
        // Simulate completed state by setting rootNode + scanState
        let model = AppModel()
        let leaf = makeLeafNode(name: "prior.txt", path: "/prior.txt")
        model.rootNode = makeTreeNode(name: "/", path: "/", children: [leaf])
        model.scanState = .completed(totalSize: 1024, fileCount: 1)

        // Re-scan should be allowed — current code drops this silently (bug)
        model.startScan(path: "/Users")

        // Must transition to .scanning, NOT stay at .completed
        guard case .scanning = model.scanState else {
            XCTFail("Re-scan after completion must enter .scanning, got \(model.scanState)")
            return
        }
    }

    /// Bug: Same as re-scan after completion — failed scans should also allow retry.
    func testReScanAllowedAfterFailure() {
        let model = AppModel()
        model.scanState = .failed(error: "disk unavailable")

        model.startScan(path: "/Volumes/USB")

        guard case .scanning = model.scanState else {
            XCTFail("Re-scan after failure must enter .scanning, got \(model.scanState)")
            return
        }
    }

    // MARK: - Scan History Tests (Regression: fix-view-defects)

    /// Bug: ScanHistoryService exists but is never instantiated or called from AppModel.
    /// lastScanDate returns nil always (TODO comment in SidebarView).
    func testScanHistoryServiceExistsOnModel() {
        let model = AppModel()
        // Must expose a ScanHistoryService ref so views can read history
        XCTAssertNotNil(model.scanHistory, "AppModel must own ScanHistoryService")
    }

    /// Bug: Recorded scan history entry must match scan result.
    func testScanRecordsHistoryEntry() {
        let model = AppModel()
        model.scanHistory.clearHistory()

        let leaf = makeLeafNode(name: "a.txt", path: "/tmp/a.txt", size: 5000)
        let root = makeTreeNode(name: "tmp", path: "/tmp", children: [leaf])
        model.rootNode = root
        model.scanState = .completed(totalSize: 5000, fileCount: 1)

        // Record a scan in history (simulates what startScan should do on completion)
        model.scanHistory.recordScan(
            volumePath: "/tmp",
            totalFiles: 1,
            totalSize: 5000,
            duration: 2.5
        )

        XCTAssertEqual(model.scanHistory.entries.count, 1, "Must record scan entry")
        let entry = model.scanHistory.entries[0]
        XCTAssertEqual(entry.volumePath, "/tmp")
        XCTAssertEqual(entry.totalFiles, 1)
        XCTAssertEqual(entry.totalSize, 5000)
        XCTAssertEqual(entry.duration, 2.5)
    }

    /// Bug: mostRecentScan should be non-nil after recording.
    func testMostRecentScanAfterRecord() {
        let model = AppModel()
        model.scanHistory.clearHistory()

        model.scanHistory.recordScan(volumePath: "/", totalFiles: 42, totalSize: 1_000_000, duration: 3.0)

        XCTAssertNotNil(model.scanHistory.mostRecentScan)
        XCTAssertEqual(model.scanHistory.mostRecentScan?.volumePath, "/")
    }
}
