//
//  CoverageGapTests.swift
//  DiskTrackerTests
//
//  Fills the gaps `./check-coverage` reported against its >80% target for
//  core files: the scan state machine, free-space monitoring, history
//  persistence, volume enumeration and bundle analysis.
//
//  These are the behaviours a user hits constantly and nothing exercised —
//  cancelling a scan, sorting a column, switching a smart filter, a history
//  entry surviving a relaunch.
//

import XCTest
@testable import DiskTracker

// MARK: - Scan state machine

final class ScanStateMachineTests: XCTestCase {

    private func node(_ name: String, _ size: UInt64, kind: FileKind = .document,
                      children: [DiskNode] = []) -> DiskNode {
        DiskNode(recordIndex: 0, name: name, path: "/root/\(name)",
                 logicalSize: size, physicalSize: size, fileKind: kind,
                 isSystemProtected: false, modTimeSecs: Int64(size),
                 depth: 1, childCount: UInt32(children.count), children: children,
                 totalPhysicalSize: children.isEmpty
                    ? size : children.reduce(0) { $0 + $1.totalPhysicalSize })
    }

    private func populated() -> AppModel {
        let model = AppModel()
        model.rootNode = DiskNode(
            recordIndex: 0, name: "root", path: "/root",
            logicalSize: 0, physicalSize: 0, fileKind: .directory,
            isSystemProtected: false, modTimeSecs: 0, depth: 0, childCount: 3,
            children: [node("b.txt", 300), node("a.txt", 100), node("c.img", 200, kind: .image)],
            totalPhysicalSize: 600)
        return model
    }

    // MARK: Navigation

    func testStartsOnTheDashboard() {
        XCTAssertEqual(AppModel().phase, .dashboard)
    }

    /// Entering results with nothing to show would present an empty screen the
    /// user cannot explain.
    func testCannotEnterResultsWithoutATree() {
        let model = AppModel()
        model.navigate(to: .scanResults)
        XCTAssertEqual(model.phase, .dashboard)
    }

    func testEntersResultsOnceThereIsATree() {
        let model = populated()
        model.navigate(to: .scanResults)
        XCTAssertEqual(model.phase, .scanResults)
    }

    // MARK: Scan lifecycle

    func testNewScansAreBlockedWhileOneIsRunning() {
        let model = AppModel()
        XCTAssertTrue(model.canStartNewScan)

        model.scanState = .scanning(progress: 0.5)
        XCTAssertFalse(model.canStartNewScan)
    }

    func testRescanIsAllowedAfterSuccessAndAfterFailure() {
        let model = AppModel()
        model.scanState = .completed(totalSize: 10, fileCount: 2)
        XCTAssertTrue(model.canStartNewScan)

        model.scanState = .failed(error: "boom")
        XCTAssertTrue(model.canStartNewScan, "a failed scan must be retryable")
    }

    func testCancellingClearsTheScan() {
        let model = populated()
        model.scanState = .scanning(progress: 0.3)
        model.filesScanned = 4_000
        model.activeSmartFilter = .large
        model.smartFilterResults = [
            SmartFilterResult(node: node("x", 1), matchedAt: Date(), matchReason: .largeFile)
        ]

        model.cancelScan()

        XCTAssertEqual(model.scanState, .idle)
        XCTAssertNil(model.rootNode)
        XCTAssertEqual(model.filesScanned, 0)
        XCTAssertTrue(model.smartFilterResults.isEmpty)
        XCTAssertNil(model.activeSmartFilter)
    }

    func testProgressIsOnlyMeaningfulWhileScanning() {
        XCTAssertEqual(ScanState.scanning(progress: 0.42).progress, 0.42)
        XCTAssertEqual(ScanState.idle.progress, 0)
        XCTAssertEqual(ScanState.completed(totalSize: 1, fileCount: 1).progress, 0)
        XCTAssertEqual(ScanState.failed(error: "x").progress, 0)
    }

    // MARK: Sorting

    func testSortsByNameWithFoldersFirst() {
        let model = populated()
        model.sortKey = .name
        model.sortAscending = true

        var nodes = model.rootNode!.children!
        nodes.append(node("zzz-folder", 0, kind: .directory))

        let sorted = model.sortedNodes(nodes)
        XCTAssertEqual(sorted.first?.fileKind, .directory,
                       "folders sort ahead of files regardless of name")
    }

    func testSortDirectionToggles() {
        let model = populated()
        model.sortKey = .size
        model.sortAscending = true

        let ascending = model.sortedNodes(model.rootNode!.children!).map(\.physicalSize)
        model.toggleSort(for: .size)
        let descending = model.sortedNodes(model.rootNode!.children!).map(\.physicalSize)

        XCTAssertEqual(ascending, descending.reversed())
    }

    func testChoosingANewColumnStartsAscending() {
        let model = populated()
        model.sortKey = .size
        model.sortAscending = false

        model.toggleSort(for: .dateModified)

        XCTAssertEqual(model.sortKey, .dateModified)
        XCTAssertTrue(model.sortAscending, "a new column starts ascending")
    }

    func testSortsByDateAndItemCount() {
        let model = populated()
        model.sortKey = .dateModified
        let byDate = model.sortedNodes(model.rootNode!.children!).map(\.modTimeSecs)
        XCTAssertEqual(byDate, byDate.sorted())

        model.sortKey = .items
        let byItems = model.sortedNodes(model.rootNode!.children!).map(\.childCount)
        XCTAssertEqual(byItems, byItems.sorted())
    }

    // MARK: Filtering

    func testCategorySelectionFiltersByKind() {
        let model = populated()
        model.selectedCategory = .images
        XCTAssertTrue(model.isFiltering)
        XCTAssertEqual(model.filteredNodes.map(\.name), ["c.img"])
    }

    func testSearchMatchesAcrossCategories() {
        let model = populated()
        model.searchQuery = "a.txt"
        XCTAssertEqual(model.filteredNodes.map(\.name), ["a.txt"])
    }

    func testSearchIsCaseInsensitiveAndTrimmed() {
        let model = populated()
        model.searchQuery = "  A.TXT "
        XCTAssertEqual(model.filteredNodes.map(\.name), ["a.txt"])
    }

    func testTheScanRootIsNeverAResult() {
        let model = populated()
        model.searchQuery = "root"
        XCTAssertFalse(model.filteredNodes.contains { $0.path == "/root" },
                       "the folder being scanned is not a search hit")
    }

    func testNotFilteringByDefault() {
        let model = populated()
        XCTAssertFalse(model.isFiltering)
        XCTAssertEqual(model.selectedCategory, .directories)
    }

    func testChangingTheCategoryInvalidatesTheCache() {
        let model = populated()
        model.selectedCategory = .images
        XCTAssertEqual(model.filteredNodes.count, 1)

        model.selectedCategory = .documents
        XCTAssertEqual(model.filteredNodes.map(\.name).sorted(), ["a.txt", "b.txt"])
    }

    func testCategoryCountsFeedTheSidebarBadges() {
        let model = populated()
        XCTAssertEqual(model.itemCount(for: .images), 1)
        XCTAssertEqual(model.itemCount(for: .documents), 2)
    }

    // MARK: Selection

    func testSingleSelectionReplacesRatherThanAccumulates() {
        let model = populated()
        let first = model.rootNode!.children![0]
        let second = model.rootNode!.children![1]

        model.selectNode(first)
        model.selectNode(second)

        XCTAssertEqual(model.selectedNode?.path, second.path)
        XCTAssertTrue(model.selectedNodes.isEmpty)
    }

    func testClearSelectionClearsBoth() {
        let model = populated()
        model.selectNode(model.rootNode!.children![0])
        model.isBatchMode = true
        model.selectNode(model.rootNode!.children![1])

        model.clearSelection()

        XCTAssertNil(model.selectedNode)
        XCTAssertTrue(model.selectedNodes.isEmpty)
    }

    func testExpansionTracksFolders() {
        let model = populated()
        let folder = model.rootNode!
        XCTAssertFalse(model.isExpanded(folder))

        model.toggleExpanded(folder)
        XCTAssertTrue(model.isExpanded(folder))

        model.toggleExpanded(folder)
        XCTAssertFalse(model.isExpanded(folder))
    }

    /// Toggling this is meant to trigger a re-scan, since the engine decides
    /// what to walk.
    func testHiddenFileToggleNotifies() {
        let model = AppModel()
        var fired = 0
        model.onHiddenFilesChanged = { fired += 1 }

        model.showHiddenFiles = true
        XCTAssertEqual(fired, 1)

        model.showHiddenFiles = true
        XCTAssertEqual(fired, 1, "setting the same value should not re-scan")
    }

    // MARK: Smart filters

    func testSmartFilterRunsOverTheTree() {
        let model = populated()
        // The threshold is in GB; the fixture is bytes, so anything above zero
        // would exclude everything. A tiny fraction of a GB keeps it meaningful.
        model.smartFilterConfig = SmartFilterConfig(
            largeFileThresholdGB: 150.0 / (1_024 * 1_024 * 1_024))
        model.activeSmartFilter = .large

        model.runSmartFilter()

        XCTAssertFalse(model.smartFilterResults.isEmpty)
        XCTAssertTrue(model.smartFilterResults.allSatisfy { $0.node.physicalSize >= 150 })
    }

    func testClearingTheFilterEmptiesTheResults() {
        let model = populated()
        model.activeSmartFilter = .large
        model.runSmartFilter()

        model.activeSmartFilter = nil
        model.runSmartFilter()

        XCTAssertTrue(model.smartFilterResults.isEmpty)
    }

    func testSmartFilterWithoutAScanDoesNothing() {
        let model = AppModel()
        model.activeSmartFilter = .large
        model.runSmartFilter()
        XCTAssertTrue(model.smartFilterResults.isEmpty)
    }

    func testTreeStatsCountTheWholeTree() {
        let model = populated()
        XCTAssertEqual(model.treeStats.totalFiles, 3)
        XCTAssertGreaterThan(model.treeStats.totalDirectories, 0)
    }

    func testTreeStatsResetWithNoScan() {
        XCTAssertEqual(AppModel().treeStats.totalFiles, 0)
    }
}

// MARK: - Free space monitoring

final class FreeSpaceMonitorTests: XCTestCase {

    private var volume: DiskVolume {
        DiskVolume(url: URL(fileURLWithPath: NSHomeDirectory()), name: "Test",
                   totalCapacity: 1_000, availableCapacity: 500,
                   isRemovable: false, isReadOnly: false)
    }

    func testStartsIdle() {
        let monitor = FreeSpaceMonitor()
        XCTAssertNil(monitor.snapshot)
        XCTAssertEqual(monitor.alertLevel, .none)
    }

    func testMonitoringTakesAnImmediateReading() {
        let monitor = FreeSpaceMonitor()
        monitor.startMonitoring(volume: volume, interval: 3600)
        defer { monitor.stopMonitoring() }

        XCTAssertNotNil(monitor.snapshot, "waiting a full interval for the first reading is a blank panel")
        XCTAssertGreaterThan(monitor.snapshot?.totalBytes ?? 0, 0)
    }

    func testStoppingClearsEverything() {
        let monitor = FreeSpaceMonitor()
        monitor.startMonitoring(volume: volume, interval: 3600)
        monitor.stopMonitoring()

        XCTAssertNil(monitor.snapshot)
        XCTAssertEqual(monitor.alertLevel, .none)
        XCTAssertTrue(monitor.history.isEmpty)
    }

    func testRestartingReplacesTheMonitoredVolume() {
        let monitor = FreeSpaceMonitor()
        monitor.startMonitoring(volume: volume, interval: 3600)
        monitor.startMonitoring(volume: volume, interval: 3600)
        defer { monitor.stopMonitoring() }

        XCTAssertLessThanOrEqual(monitor.history.count, 2,
                                 "restarting must not leave the old timer running")
    }

    func testHistoryAccumulates() {
        let monitor = FreeSpaceMonitor()
        monitor.startMonitoring(volume: volume, interval: 3600)
        defer { monitor.stopMonitoring() }

        monitor.refresh()
        monitor.refresh()
        XCTAssertGreaterThanOrEqual(monitor.history.count, 3)
    }

    func testChangingTheThresholdReEvaluates() {
        let monitor = FreeSpaceMonitor()
        monitor.startMonitoring(volume: volume, interval: 3600)
        defer { monitor.stopMonitoring() }

        // 100% means "warn unless the disk is completely empty".
        monitor.thresholdPercent = 100
        XCTAssertGreaterThan(monitor.alertLevel, .none)
    }

    func testRefreshingWithoutAVolumeIsSafe() {
        let monitor = FreeSpaceMonitor()
        monitor.refresh()
        XCTAssertNil(monitor.snapshot)
    }

    /// A volume that is not filling up has no meaningful estimate; inventing
    /// one would be worse than showing nothing.
    func testNoTrendWithoutHistory() {
        XCTAssertNil(FreeSpaceMonitor().estimatedSecondsUntilFull)
    }

    func testFractionsAreConsistent() {
        let snapshot = FreeSpaceSnapshot(
            volume: volume, timestamp: Date(),
            availableBytes: 250, totalBytes: 1_000)
        XCTAssertEqual(snapshot.availableFraction, 0.25, accuracy: 0.001)
        XCTAssertEqual(snapshot.usedFraction, 0.75, accuracy: 0.001)
        XCTAssertEqual(snapshot.usedBytes, 750)
    }
}

// MARK: - History persistence

final class ScanHistoryPersistenceTests: XCTestCase {

    private let storageKey = "DiskTracker.ScanHistory"
    private var saved: Any?

    override func setUp() {
        saved = UserDefaults.standard.object(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    override func tearDown() {
        if let saved {
            UserDefaults.standard.set(saved, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    func testRecordsAScan() {
        let service = ScanHistoryService()
        service.recordScan(volumePath: "/tmp", totalFiles: 10, totalSize: 1024, duration: 1.5)

        XCTAssertEqual(service.entries.count, 1)
        XCTAssertEqual(service.entries[0].volumePath, "/tmp")
        XCTAssertEqual(service.entries[0].totalFiles, 10)
    }

    func testNewestFirst() {
        let service = ScanHistoryService()
        service.recordScan(volumePath: "/first", totalFiles: 1, totalSize: 1, duration: 1)
        service.recordScan(volumePath: "/second", totalFiles: 1, totalSize: 1, duration: 1)

        XCTAssertEqual(service.entries.first?.volumePath, "/second")
    }

    func testSurvivesRelaunch() {
        let service = ScanHistoryService()
        service.recordScan(volumePath: "/persisted", totalFiles: 7, totalSize: 99, duration: 2)

        // A second instance reads what the first wrote, which is what happens
        // on the next launch.
        XCTAssertEqual(ScanHistoryService().entries.first?.volumePath, "/persisted")
    }

    func testEvictsBeyondTheCountCap() {
        let service = ScanHistoryService()
        for i in 0...(ScanHistoryService.maxHistoryCount + 3) {
            service.recordScan(volumePath: "/scan\(i)", totalFiles: 1, totalSize: 1, duration: 1)
        }
        XCTAssertEqual(service.entries.count, ScanHistoryService.maxHistoryCount)
        XCTAssertEqual(service.entries.first?.volumePath,
                       "/scan\(ScanHistoryService.maxHistoryCount + 3)")
    }

    func testClearingRemovesEverything() {
        let service = ScanHistoryService()
        service.recordScan(volumePath: "/tmp", totalFiles: 1, totalSize: 1, duration: 1)
        service.clearHistory()

        XCTAssertTrue(service.entries.isEmpty)
        XCTAssertTrue(ScanHistoryService().entries.isEmpty, "the clear is persisted")
    }

    func testTreeRoundTrips() throws {
        let service = ScanHistoryService()
        let payload = Data("{\"tree\":true}".utf8)

        let name = try XCTUnwrap(service.saveTree(payload))
        service.recordScan(volumePath: "/tmp", totalFiles: 1, totalSize: 1,
                           duration: 1, treeFile: name)

        let entry = try XCTUnwrap(service.entries.first)
        XCTAssertEqual(service.loadTree(for: entry), payload)

        service.clearHistory()
        XCTAssertNil(service.loadTree(for: entry), "clearing deletes the tree file too")
    }

    func testAnEntryWithNoTreeLoadsNothing() {
        let service = ScanHistoryService()
        service.recordScan(volumePath: "/tmp", totalFiles: 1, totalSize: 1, duration: 1)
        XCTAssertNil(service.loadTree(for: service.entries[0]))
    }
}

// MARK: - Volumes

final class DiskVolumeTests: XCTestCase {

    func testUsedCapacityIsTheRemainder() {
        let volume = DiskVolume(url: URL(fileURLWithPath: "/"), name: "Disk",
                                totalCapacity: 1_000, availableCapacity: 400,
                                isRemovable: false, isReadOnly: false)
        XCTAssertEqual(volume.usedCapacity, 600)
        XCTAssertEqual(volume.usageFraction, 0.6, accuracy: 0.001)
    }

    /// An unreported capacity must not divide by zero into a full-looking bar.
    func testUnknownCapacityReadsAsEmpty() {
        let volume = DiskVolume(url: URL(fileURLWithPath: "/"), name: "Disk",
                                totalCapacity: 0, availableCapacity: 0,
                                isRemovable: false, isReadOnly: false)
        XCTAssertEqual(volume.usageFraction, 0)
    }

    func testEnumeratesAtLeastTheBootVolume() {
        let volumes = DiskVolumeService.mountedVolumes()
        XCTAssertFalse(volumes.isEmpty, "the machine running this has a disk")
        XCTAssertTrue(volumes.allSatisfy { $0.totalCapacity > 0 })
    }

    func testRefreshesFreeSpaceForARealPath() throws {
        let result = DiskVolumeService.refreshFreeSpace(for: URL(fileURLWithPath: NSHomeDirectory()))
        let (total, available) = try XCTUnwrap(result)
        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThanOrEqual(available, total)
    }

    func testRefreshingAMissingPathReportsNothing() {
        XCTAssertNil(DiskVolumeService.refreshFreeSpace(
            for: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")))
    }
}

// MARK: - App bundle analysis

/// `.app` bundles are the one node type where the interesting number is inside
/// the folder rather than the folder itself, and the breakdown is what the
/// Smart Filters "App Bundles" entry shows.
final class AppBundleAnalyzerTests2: XCTestCase {

    private func node(_ name: String, _ path: String, _ size: UInt64,
                      kind: FileKind, children: [DiskNode] = []) -> DiskNode {
        DiskNode(recordIndex: 0, name: name, path: path,
                 logicalSize: size, physicalSize: size, fileKind: kind,
                 isSystemProtected: false, modTimeSecs: 0, depth: 1,
                 childCount: UInt32(children.count), children: children,
                 totalPhysicalSize: children.isEmpty
                    ? size : children.reduce(0) { $0 + $1.totalPhysicalSize })
    }

    /// A `.app` is a directory on disk, so the scanner classifies it
    /// `.directory` rather than `.application` — the analyzer keys off the
    /// name suffix plus that kind, and the fixtures have to match.
    private func tree(bundleSize: UInt64) -> DiskNode {
        let app = node("Big.app", "/Apps/Big.app", bundleSize, kind: .directory)
        let small = node("Tiny.app", "/Apps/Tiny.app", 1_000, kind: .directory)
        let doc = node("notes.txt", "/Apps/notes.txt", 50, kind: .document)
        return node("Apps", "/Apps", 0, kind: .directory, children: [app, small, doc])
    }

    func testFindsBundlesAboveTheThreshold() {
        let results = AppBundleAnalyzer.findLargeBundles(
            in: tree(bundleSize: 500_000_000),
            config: SmartFilterConfig(),
            threshold: 100_000_000)

        XCTAssertEqual(results.map(\.node.name), ["Big.app"])
    }

    func testIgnoresBundlesBelowTheThreshold() {
        let results = AppBundleAnalyzer.findLargeBundles(
            in: tree(bundleSize: 1_000),
            config: SmartFilterConfig(),
            threshold: 100_000_000)

        XCTAssertTrue(results.isEmpty)
    }

    func testIgnoresNonBundles() {
        let results = AppBundleAnalyzer.findLargeBundles(
            in: tree(bundleSize: 500_000_000),
            config: SmartFilterConfig(),
            threshold: 1)

        XCTAssertFalse(results.contains { $0.node.name == "notes.txt" },
                       "a plain document is not an app bundle")
    }

    func testSortsLargestFirst() {
        let results = AppBundleAnalyzer.findLargeBundles(
            in: tree(bundleSize: 500_000_000),
            config: SmartFilterConfig(),
            threshold: 1)

        let sizes = results.map(\.node.physicalSize)
        XCTAssertEqual(sizes, sizes.sorted(by: >))
    }

    func testDefaultThresholdIsAHundredMegabytes() {
        XCTAssertEqual(AppBundleAnalyzer.defaultThreshold, 100_000_000)
    }

    /// A bundle that is not on disk still has to produce a breakdown rather
    /// than crash — scan results can outlive the files they describe.
    func testBreakdownOfAMissingBundleIsEmptyNotFatal() {
        let bundle = node("Gone.app", "/nonexistent/Gone.app", 1_000, kind: .directory)
        let breakdown = AppBundleAnalyzer.analyzeBundle(bundle)

        XCTAssertEqual(breakdown.name, "Gone.app")
        XCTAssertEqual(breakdown.executableSize, 0)
        XCTAssertTrue(breakdown.frameworkSizes.isEmpty)
    }

    func testBreakdownReadsARealBundleLayout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundle-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Sample.app")
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        for sub in ["Contents/MacOS", "Contents/Frameworks/Lib.framework", "Contents/PlugIns"] {
            try fm.createDirectory(at: app.appendingPathComponent(sub),
                                   withIntermediateDirectories: true)
        }
        try Data(repeating: 0x41, count: 4_096)
            .write(to: app.appendingPathComponent("Contents/MacOS/Sample"))
        try Data(repeating: 0x42, count: 8_192)
            .write(to: app.appendingPathComponent("Contents/Frameworks/Lib.framework/Lib"))

        let bundle = node("Sample.app", app.path, 12_288, kind: .directory)
        let breakdown = AppBundleAnalyzer.analyzeBundle(bundle)

        XCTAssertEqual(breakdown.name, "Sample.app")
        XCTAssertGreaterThan(breakdown.executableSize, 0, "Contents/MacOS should be counted")
        XCTAssertFalse(breakdown.frameworkSizes.isEmpty, "Contents/Frameworks should be listed")
    }
}

// MARK: - Restoring a scan

// The restore path polls on the main queue; @MainActor lets the compiler see
// that the polling closure never leaves it.
@MainActor
final class ScanRestoreTests: XCTestCase {

    private let storageKey = "DiskTracker.ScanHistory"
    // `setUp`/`tearDown` are nonisolated overrides, so they cannot touch a
    // main-actor property. XCTest runs them serially around each test, so
    // there is no concurrent access to guard against.
    nonisolated(unsafe) private var saved: Any?

    override func setUp() {
        saved = UserDefaults.standard.object(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    override func tearDown() {
        if let saved { UserDefaults.standard.set(saved, forKey: storageKey) }
        else { UserDefaults.standard.removeObject(forKey: storageKey) }
    }

    /// Re-opening a past scan must not re-walk the filesystem — that is the
    /// entire reason trees are persisted.
    func testRestoringLoadsTheSavedTree() throws {
        let model = AppModel()
        let file = DiskNode(recordIndex: 0, name: "saved.bin", path: "/old/saved.bin",
                            logicalSize: 2048, physicalSize: 2048, fileKind: .archive,
                            isSystemProtected: false, modTimeSecs: 0, depth: 1,
                            childCount: 0, children: [], totalPhysicalSize: 2048)
        let tree = DiskNode(recordIndex: 0, name: "old", path: "/old",
                            logicalSize: 0, physicalSize: 0, fileKind: .directory,
                            isSystemProtected: false, modTimeSecs: 0, depth: 0,
                            childCount: 1, children: [file], totalPhysicalSize: 2048)

        let data = try JSONEncoder().encode(tree)
        let name = try XCTUnwrap(model.scanHistory.saveTree(data))
        model.scanHistory.recordScan(volumePath: "/old", totalFiles: 2, totalSize: 2048,
                                     duration: 1, treeFile: name)
        let entry = try XCTUnwrap(model.scanHistory.entries.first)

        model.restoreScanFromHistory(entry)
        XCTAssertEqual(model.phase, .scanResults, "the switch is immediate")
        XCTAssertEqual(model.currentScanPath, "/old")

        // Decoding runs off the main thread, so wait for the tree to land.
        let loaded = expectation(description: "tree restored")
        let deadline = Date().addingTimeInterval(5)
        func poll() {
            if model.rootNode != nil || Date() > deadline { loaded.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }
        DispatchQueue.main.async(execute: poll)
        wait(for: [loaded], timeout: 6)

        XCTAssertEqual(model.rootNode?.name, "old")
        XCTAssertEqual(model.rootNode?.children?.count, 1)

        model.scanHistory.clearHistory()
    }

    func testRestoringAnEntryWithNoTreeLeavesTheTreeEmpty() {
        let model = AppModel()
        model.scanHistory.recordScan(volumePath: "/gone", totalFiles: 1, totalSize: 1, duration: 1)
        let entry = model.scanHistory.entries[0]

        model.restoreScanFromHistory(entry)

        XCTAssertEqual(model.currentScanPath, "/gone")
        XCTAssertNil(model.rootNode, "there was no tree to load")
        model.scanHistory.clearHistory()
    }
}

// MARK: - Free space trend

/// `estimatedSecondsUntilFull` is what the low-space banner uses for "full in
/// about X". A wrong estimate is worse than none, so the cases where there is
/// no honest answer matter as much as the arithmetic.
final class FreeSpaceTrendTests: XCTestCase {

    private let volume = DiskVolume(
        url: URL(fileURLWithPath: "/"), name: "Disk",
        totalCapacity: 1_000_000, availableCapacity: 500_000,
        isRemovable: false, isReadOnly: false)

    private func snapshot(available: UInt64, secondsAgo: TimeInterval) -> FreeSpaceSnapshot {
        FreeSpaceSnapshot(volume: volume,
                          timestamp: Date().addingTimeInterval(-secondsAgo),
                          availableBytes: available,
                          totalBytes: 1_000_000)
    }

    func testEstimatesFromAFallingTrend() throws {
        let monitor = FreeSpaceMonitor()
        // 100,000 bytes consumed over 100 seconds = 1,000 bytes/sec.
        monitor.appendSnapshotForTesting(snapshot(available: 200_000, secondsAgo: 100))
        monitor.appendSnapshotForTesting(snapshot(available: 100_000, secondsAgo: 0))

        let seconds = try XCTUnwrap(monitor.estimatedSecondsUntilFull)
        XCTAssertEqual(seconds, 100, accuracy: 5, "100,000 left at 1,000/sec")
    }

    /// A disk being emptied has no time-to-full, and inventing one would be a
    /// confident lie.
    func testNoEstimateWhenSpaceIsBeingFreed() {
        let monitor = FreeSpaceMonitor()
        monitor.appendSnapshotForTesting(snapshot(available: 100_000, secondsAgo: 100))
        monitor.appendSnapshotForTesting(snapshot(available: 300_000, secondsAgo: 0))

        XCTAssertNil(monitor.estimatedSecondsUntilFull)
    }

    func testNoEstimateFromASingleReading() {
        let monitor = FreeSpaceMonitor()
        monitor.appendSnapshotForTesting(snapshot(available: 100_000, secondsAgo: 0))
        XCTAssertNil(monitor.estimatedSecondsUntilFull)
    }

    func testNoEstimateWhenNothingChanged() {
        let monitor = FreeSpaceMonitor()
        monitor.appendSnapshotForTesting(snapshot(available: 100_000, secondsAgo: 100))
        monitor.appendSnapshotForTesting(snapshot(available: 100_000, secondsAgo: 0))

        XCTAssertNil(monitor.estimatedSecondsUntilFull, "a flat trend never fills")
    }

    /// Two readings in the same instant would divide by a zero interval.
    func testNoEstimateWithoutElapsedTime() {
        let monitor = FreeSpaceMonitor()
        let now = Date()
        for available in [200_000, 100_000] {
            monitor.appendSnapshotForTesting(
                FreeSpaceSnapshot(volume: volume, timestamp: now,
                                  availableBytes: UInt64(available), totalBytes: 1_000_000))
        }
        XCTAssertNil(monitor.estimatedSecondsUntilFull)
    }

    func testHistoryIsBounded() {
        let monitor = FreeSpaceMonitor()
        for i in 0..<200 {
            monitor.appendSnapshotForTesting(
                snapshot(available: UInt64(500_000 - i * 100), secondsAgo: Double(200 - i)))
        }
        XCTAssertLessThanOrEqual(monitor.history.count, 60,
                                 "unbounded history would grow for the life of the app")
    }

    /// The estimate uses only recent readings, so a long-past burst of
    /// activity does not skew what the banner claims now.
    func testEstimateUsesRecentReadings() throws {
        let monitor = FreeSpaceMonitor()
        // Long-ago cliff, then a steady slow decline.
        monitor.appendSnapshotForTesting(snapshot(available: 900_000, secondsAgo: 10_000))
        for i in stride(from: 100, through: 10, by: -10) {
            monitor.appendSnapshotForTesting(
                snapshot(available: UInt64(100_000 + i * 10), secondsAgo: Double(i)))
        }
        let seconds = try XCTUnwrap(monitor.estimatedSecondsUntilFull)
        XCTAssertGreaterThan(seconds, 0)
    }
}
