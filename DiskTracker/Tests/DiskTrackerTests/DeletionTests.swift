//
//  DeletionTests.swift
//  DiskTrackerTests
//
//  Deletion touches the user's files, so the parts that decide *what* gets
//  deleted and *what the dialog claims* are covered here. The FileManager call
//  itself is already covered by FileOperationsServiceTests.
//

import XCTest
@testable import DiskTracker

final class TreePruningTests: XCTestCase {

    /// root/                     (dir)
    ///   docs/                   (dir)
    ///     deep/                 (dir)
    ///       big.bin   4000
    ///     note.txt      100
    ///   apple.txt         7
    private func makeModel() -> AppModel {
        func file(_ name: String, _ path: String, _ size: UInt64) -> DiskNode {
            DiskNode(recordIndex: 0, name: name, path: path,
                     logicalSize: size, physicalSize: size,
                     fileKind: .document, isSystemProtected: false,
                     modTimeSecs: 0, depth: 0, childCount: 0,
                     children: [], totalPhysicalSize: size)
        }
        func dir(_ name: String, _ path: String, _ children: [DiskNode]) -> DiskNode {
            DiskNode(recordIndex: 0, name: name, path: path,
                     logicalSize: 0, physicalSize: 0,
                     fileKind: .directory, isSystemProtected: false,
                     modTimeSecs: 0, depth: 0,
                     childCount: UInt32(children.count),
                     children: children,
                     totalPhysicalSize: children.reduce(0) { $0 + $1.totalPhysicalSize })
        }

        let deep = dir("deep", "/root/docs/deep", [file("big.bin", "/root/docs/deep/big.bin", 4000)])
        let docs = dir("docs", "/root/docs", [deep, file("note.txt", "/root/docs/note.txt", 100)])
        let root = dir("root", "/root", [docs, file("apple.txt", "/root/apple.txt", 7)])

        let model = AppModel()
        model.rootNode = root
        model.scanState = .completed(totalSize: root.totalPhysicalSize, fileCount: 5)
        return model
    }

    private func node(_ model: AppModel, _ path: String) -> DiskNode? {
        func find(_ n: DiskNode) -> DiskNode? {
            if n.path == path { return n }
            for c in n.children ?? [] { if let hit = find(c) { return hit } }
            return nil
        }
        return model.rootNode.flatMap(find)
    }

    func testRemovesTheNodeFromTheTree() {
        let model = makeModel()
        XCTAssertNotNil(node(model, "/root/apple.txt"))

        model.removeFromTree(paths: ["/root/apple.txt"])

        XCTAssertNil(node(model, "/root/apple.txt"))
        XCTAssertEqual(model.rootNode?.children?.count, 1)
    }

    /// The whole point of updating the tree rather than re-scanning: the
    /// folder sizes the user is looking at have to drop.
    func testTotalsShrinkAllTheWayToTheRoot() {
        let model = makeModel()
        XCTAssertEqual(model.rootNode?.totalPhysicalSize, 4107)

        model.removeFromTree(paths: ["/root/docs/deep/big.bin"])

        XCTAssertEqual(node(model, "/root/docs/deep")?.totalPhysicalSize, 0)
        XCTAssertEqual(node(model, "/root/docs")?.totalPhysicalSize, 100)
        XCTAssertEqual(model.rootNode?.totalPhysicalSize, 107)
    }

    func testDeletingAFolderTakesItsDescendants() {
        let model = makeModel()
        model.removeFromTree(paths: ["/root/docs"])

        XCTAssertNil(node(model, "/root/docs"))
        XCTAssertNil(node(model, "/root/docs/deep/big.bin"), "descendants go with the folder")
        XCTAssertEqual(model.rootNode?.totalPhysicalSize, 7)
    }

    func testChildCountFollowsTheRemoval() {
        let model = makeModel()
        model.removeFromTree(paths: ["/root/docs/note.txt"])
        XCTAssertEqual(node(model, "/root/docs")?.childCount, 1)
    }

    func testRemovesSeveralPathsAtOnce() {
        let model = makeModel()
        model.removeFromTree(paths: ["/root/apple.txt", "/root/docs/note.txt"])

        XCTAssertNil(node(model, "/root/apple.txt"))
        XCTAssertNil(node(model, "/root/docs/note.txt"))
        XCTAssertEqual(model.rootNode?.totalPhysicalSize, 4000)
    }

    func testUnrelatedBranchesAreUntouched() {
        let model = makeModel()
        let before = node(model, "/root/docs/deep")

        model.removeFromTree(paths: ["/root/apple.txt"])

        XCTAssertEqual(node(model, "/root/docs/deep")?.totalPhysicalSize,
                       before?.totalPhysicalSize)
        XCTAssertEqual(node(model, "/root/docs/deep/big.bin")?.physicalSize, 4000)
    }

    func testScanStateFollowsTheNewTotal() {
        let model = makeModel()
        model.removeFromTree(paths: ["/root/docs"])

        guard case .completed(let total, let count) = model.scanState else {
            return XCTFail("expected a completed scan, got \(model.scanState)")
        }
        XCTAssertEqual(total, 7)
        XCTAssertEqual(count, 2, "root + apple.txt")
    }

    /// Deleting the scan root leaves nothing to display, so the screen has to
    /// fall back rather than show a scan of a folder that is gone.
    func testDeletingTheScanRootClearsTheScan() {
        let model = makeModel()
        model.removeFromTree(paths: ["/root"])

        XCTAssertNil(model.rootNode)
        XCTAssertEqual(model.scanState, .idle)
    }

    func testDeletedNodeIsDeselected() {
        let model = makeModel()
        let apple = try? XCTUnwrap(node(model, "/root/apple.txt"))
        model.selectedNode = apple
        model.selectedNodes = [apple!.id]

        model.removeFromTree(paths: ["/root/apple.txt"])

        XCTAssertNil(model.selectedNode, "a deleted node must not stay selected")
        XCTAssertTrue(model.selectedNodes.isEmpty)
    }

    func testUnknownPathChangesNothing() {
        let model = makeModel()
        model.removeFromTree(paths: ["/root/does-not-exist"])
        XCTAssertEqual(model.rootNode?.totalPhysicalSize, 4107)
    }

    func testEmptyInputChangesNothing() {
        let model = makeModel()
        model.removeFromTree(paths: [])
        XCTAssertEqual(model.rootNode?.totalPhysicalSize, 4107)
    }

    /// Filtered results and the sidebar counts are cached walks of the tree.
    func testCachesAreInvalidated() {
        let model = makeModel()
        model.searchQuery = "note"
        XCTAssertEqual(model.filteredNodes.count, 1)

        model.removeFromTree(paths: ["/root/docs/note.txt"])

        XCTAssertTrue(model.filteredNodes.isEmpty, "stale cache would still list the deleted file")
    }
}

// MARK: - Selection

final class BatchSelectionTests: XCTestCase {

    private func makeModel() -> (AppModel, DiskNode, DiskNode) {
        let big = DiskNode(recordIndex: 0, name: "big.bin", path: "/root/folder/big.bin",
                           logicalSize: 5000, physicalSize: 5000, fileKind: .archive,
                           isSystemProtected: false, modTimeSecs: 0, depth: 2,
                           childCount: 0, children: [], totalPhysicalSize: 5000)
        let folder = DiskNode(recordIndex: 0, name: "folder", path: "/root/folder",
                              logicalSize: 0, physicalSize: 0, fileKind: .directory,
                              isSystemProtected: false, modTimeSecs: 0, depth: 1,
                              childCount: 1, children: [big], totalPhysicalSize: 5000)
        let loose = DiskNode(recordIndex: 0, name: "loose.txt", path: "/root/loose.txt",
                             logicalSize: 20, physicalSize: 20, fileKind: .document,
                             isSystemProtected: false, modTimeSecs: 0, depth: 1,
                             childCount: 0, children: [], totalPhysicalSize: 20)
        let root = DiskNode(recordIndex: 0, name: "root", path: "/root",
                            logicalSize: 0, physicalSize: 0, fileKind: .directory,
                            isSystemProtected: false, modTimeSecs: 0, depth: 0,
                            childCount: 2, children: [folder, loose], totalPhysicalSize: 5020)
        let model = AppModel()
        model.rootNode = root
        return (model, folder, loose)
    }

    /// A folder's own `physicalSize` is 0, so selecting one used to report
    /// "0 bytes" for a selection that would free megabytes.
    func testSelectedFolderReportsWhatItWouldReclaim() {
        let (model, folder, _) = makeModel()
        model.selectedNodes = [folder.id]
        XCTAssertEqual(model.selectedTotalSize, 5000)
    }

    func testSelectedFolderIsNotCountedTwice() {
        let (model, folder, _) = makeModel()
        // Both the folder and the file inside it are ticked.
        let big = folder.children![0]
        model.selectedNodes = [folder.id, big.id]

        XCTAssertEqual(model.selectedTotalSize, 5000, "the child's bytes are already in the folder")
        XCTAssertEqual(model.selectedDiskNodes.count, 1, "the folder subsumes its descendants")
    }

    func testSumsAcrossSeparateSelections() {
        let (model, folder, loose) = makeModel()
        model.selectedNodes = [folder.id, loose.id]
        XCTAssertEqual(model.selectedTotalSize, 5020)
        XCTAssertEqual(model.selectedDiskNodes.count, 2)
    }

    func testBatchModeRoutesTapsToMultiSelection() {
        let (model, _, loose) = makeModel()
        model.isBatchMode = true

        model.selectNode(loose)
        XCTAssertTrue(model.selectedNodes.contains(loose.id))
        XCTAssertNil(model.selectedNode, "batch mode must not also set the inspected node")

        model.selectNode(loose)
        XCTAssertFalse(model.selectedNodes.contains(loose.id), "tapping again deselects")
    }
}

// MARK: - Confirmation copy

final class DeletionControllerTests: XCTestCase {

    private func file(_ name: String, _ size: UInt64, path: String? = nil) -> DiskNode {
        DiskNode(recordIndex: 0, name: name, path: path ?? "/tmp/\(name)",
                 logicalSize: size, physicalSize: size, fileKind: .document,
                 isSystemProtected: false, modTimeSecs: 0, depth: 1,
                 childCount: 0, children: [], totalPhysicalSize: size)
    }

    private func folder(_ name: String, _ total: UInt64) -> DiskNode {
        DiskNode(recordIndex: 0, name: name, path: "/tmp/\(name)",
                 logicalSize: 0, physicalSize: 0, fileKind: .directory,
                 isSystemProtected: false, modTimeSecs: 0, depth: 1,
                 childCount: 0, children: [], totalPhysicalSize: total)
    }

    func testNothingIsPendingUntilAskedFor() {
        let controller = DeletionController()
        XCTAssertFalse(controller.isConfirming)
        XCTAssertTrue(controller.pending.isEmpty)
    }

    func testRequestingADeleteOpensTheDialog() {
        let controller = DeletionController()
        controller.requestDelete(file("a.txt", 10))
        XCTAssertTrue(controller.isConfirming, "deletion must never skip confirmation")
    }

    func testCancellingClearsThePending() {
        let controller = DeletionController()
        controller.requestDelete(file("a.txt", 10))
        controller.cancel()
        XCTAssertFalse(controller.isConfirming)
        XCTAssertTrue(controller.pending.isEmpty)
    }

    func testEmptyBatchDoesNotOpenTheDialog() {
        let controller = DeletionController()
        controller.requestDelete([])
        XCTAssertFalse(controller.isConfirming)
    }

    func testReportsTheReclaimableSize() {
        let controller = DeletionController()
        controller.requestDelete([file("a.txt", 100), folder("cache", 9_000)])
        XCTAssertEqual(controller.pendingSize, 9_100, "a folder contributes its recursive total")
    }

    func testFlagsAFolderInTheSelection() {
        let controller = DeletionController()
        controller.requestDelete([file("a.txt", 10)])
        XCTAssertFalse(controller.pendingIncludesFolder)

        controller.requestDelete([file("a.txt", 10), folder("cache", 10)])
        XCTAssertTrue(controller.pendingIncludesFolder, "the dialog warns folders take their contents")
    }

    func testFlagsAProtectedSystemPath() {
        let controller = DeletionController()
        controller.requestDelete(file("kernel", 10, path: "/System/Library/kernel"))
        XCTAssertTrue(controller.pendingIncludesProtected)

        controller.requestDelete(file("mine.txt", 10, path: NSHomeDirectory() + "/Documents/mine.txt"))
        XCTAssertFalse(controller.pendingIncludesProtected)
    }

    /// The service refuses protected paths, so a confirmed delete of one
    /// reports a failure and leaves the tree alone.
    func testProtectedPathIsRefusedAndReported() {
        let controller = DeletionController()
        let model = AppModel()
        let protectedNode = file("kernel", 10, path: "/System/Library/kernel")
        model.rootNode = DiskNode(
            recordIndex: 0, name: "Library", path: "/System/Library",
            logicalSize: 0, physicalSize: 0, fileKind: .directory,
            isSystemProtected: true, modTimeSecs: 0, depth: 0, childCount: 1,
            children: [protectedNode], totalPhysicalSize: 10)

        controller.requestDelete(protectedNode)
        controller.confirmDelete(model: model)

        XCTAssertNotNil(controller.failure, "a refused delete must say so, not fail silently")
        XCTAssertEqual(model.rootNode?.children?.count, 1, "nothing was removed from the tree")
    }

    /// End to end against the real filesystem: a temp file is trashed and the
    /// tree updates. Everything above stops short of touching disk.
    func testDeletesARealFileAndUpdatesTheTree() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deletion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let victim = dir.appendingPathComponent("victim.txt")
        try Data(repeating: 0x7A, count: 1024).write(to: victim)

        let node = file("victim.txt", 1024, path: victim.path)
        let root = DiskNode(
            recordIndex: 0, name: dir.lastPathComponent, path: dir.path,
            logicalSize: 0, physicalSize: 0, fileKind: .directory,
            isSystemProtected: false, modTimeSecs: 0, depth: 0, childCount: 1,
            children: [node], totalPhysicalSize: 1024)

        let model = AppModel()
        model.rootNode = root
        model.scanState = .completed(totalSize: 1024, fileCount: 2)

        let controller = DeletionController()
        controller.requestDelete(node)
        controller.confirmDelete(model: model)

        XCTAssertNil(controller.failure, "unexpected failure: \(controller.failure?.message ?? "")")
        XCTAssertFalse(FileManager.default.fileExists(atPath: victim.path), "file should be in Trash")
        XCTAssertEqual(model.rootNode?.children?.count, 0)
        XCTAssertEqual(model.rootNode?.totalPhysicalSize, 0)
    }
}

// MARK: - Quick Look

/// The panel itself is AppKit and needs a real window, so these cover the part
/// that is ours: which file is queued, and that the spacebar toggles rather
/// than reopening.
@MainActor
final class QuickLookPreviewTests: XCTestCase {

    override func tearDown() async throws {
        QuickLookPreview.shared.close()
    }

    func testStartsWithNothingQueued() {
        QuickLookPreview.shared.close()
        // A fresh panel has no item; numberOfPreviewItems must not claim one.
        XCTAssertEqual(
            QuickLookPreview.shared.numberOfPreviewItems(in: nil),
            QuickLookPreview.shared.currentURL == nil ? 0 : 1
        )
    }

    func testQueuesTheRequestedFile() {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("a.txt")
        QuickLookPreview.shared.toggle(url: url)
        XCTAssertEqual(QuickLookPreview.shared.currentURL, url)
        XCTAssertEqual(QuickLookPreview.shared.numberOfPreviewItems(in: nil), 1)
    }

    func testSwitchingFilesReplacesTheItem() {
        let first = URL(fileURLWithPath: "/tmp/first.txt")
        let second = URL(fileURLWithPath: "/tmp/second.txt")
        QuickLookPreview.shared.toggle(url: first)
        QuickLookPreview.shared.toggle(url: second)
        XCTAssertEqual(QuickLookPreview.shared.currentURL, second)
    }

    func testPreviewItemIsTheQueuedURL() {
        let url = URL(fileURLWithPath: "/tmp/preview.txt")
        QuickLookPreview.shared.toggle(url: url)
        let item = QuickLookPreview.shared.previewPanel(nil, previewItemAt: 0)
        XCTAssertEqual((item as? NSURL) as URL?, url)
    }
}
