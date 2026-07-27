//
//  AppModel.swift
//  DiskTracker
//
//  Central application state with Phase 3 file operations support.
//

import SwiftUI
import Combine

/// The canonical scan state.
enum ScanState: Equatable, Sendable {
    case idle
    case scanning(progress: Double)
    case completed(totalSize: UInt64, fileCount: Int)
    case failed(error: String)

    var progress: Double {
        if case .scanning(let p) = self { return p }
        return 0.0
    }
}

/// File type used for colour-coding the visualisation.
enum FileKind: UInt8, CaseIterable, Sendable {
    case image = 0, video = 1, audio = 2, document = 3
    case archive = 4, application = 5, other = 6, directory = 7
}

/// One node in the flat array returned by the Rust engine.
struct DiskNode: Identifiable, Equatable, Sendable, Hashable {
    let id = UUID()
    var recordIndex: Int
    var name: String
    var path: String
    var logicalSize: UInt64
    var physicalSize: UInt64
    var fileKind: FileKind
    var isSystemProtected: Bool
    var modTimeSecs: Int64
    var depth: UInt16
    var children: [DiskNode]?

    static func == (lhs: DiskNode, rhs: DiskNode) -> Bool {
        lhs.recordIndex == rhs.recordIndex && lhs.path == rhs.path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(recordIndex)
        hasher.combine(path)
    }

    /// Total logical size of this node and all descendants (recursive).
    var totalLogicalSize: UInt64 {
        children?.reduce(logicalSize) { $0 + $1.totalLogicalSize } ?? logicalSize
    }

    /// Total physical size of this node and all descendants (recursive).
    var totalPhysicalSize: UInt64 {
        children?.reduce(physicalSize) { $0 + $1.totalPhysicalSize } ?? physicalSize
    }

    /// Classify a file by its extension for colour-coding.
    static func detectFileKind(`extension`: String) -> FileKind {
        switch `extension`.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg", "bmp", "tiff": return .image
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv":                          return .video
        case "mp3", "wav", "aac", "flac", "m4a", "aiff":                        return .audio
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "xlsx", "pptx":       return .document
        case "zip", "tar", "gz", "bz2", "7z", "rar", "dmg", "pkg":              return .archive
        case "app", "dylib", "so", "exe":                                       return .application
        default:                                                                return .other
        }
    }
}

// Phase 5: DuplicateGroup at file scope (before @Observable class) for macro compatibility
// SwiftPM compiles Sources/Core/Engine/ before Sources/Core/Services/.
// The @Observable macro on AppModel generates code referencing DuplicateGroup.
// If DuplicateGroup is defined in DuplicateFinderService.swift (compiled later),
// macro expansion fails. Moving it here ensures it's in scope when macro runs.

/// A group of files with identical content (same full SHA-256).
struct DuplicateGroup: Identifiable, Sendable {
    let id = UUID()
    let hash: Data               // 32-byte SHA-256 digest
    let nodes: [DiskNode]
    let wastedBytes: UInt64

    /// Keep the file with the most recent modification time as the "original."
    var originalNode: DiskNode {
        nodes.max(by: { $0.modTimeSecs < $1.modTimeSecs }) ?? nodes[0]
    }

    var duplicateNodes: [DiskNode] {
        nodes.filter { $0.id != originalNode.id }
    }
}

/// Global observable model.
@Observable
final class AppModel: ObservableObject, @unchecked Sendable {
    var scanState: ScanState = .idle
    var rootNode: DiskNode?
    var selectedNode: DiskNode?
    var currentView: ViewMode = .sunburst

    /// Phase 3: Show or hide hidden files during scanning.
    var showHiddenFiles: Bool = false {
        didSet { if oldValue != showHiddenFiles { onHiddenFilesChanged?() } }
    }

    /// Phase 3: Multi-selection for batch operations.
    var selectedNodes: Set<UUID> = []

    /// Phase 3: Whether batch selection mode is active.
    var isBatchMode: Bool = false

    /// Callback when hidden file toggle changes (triggers re-scan).
    var onHiddenFilesChanged: (() -> Void)?

    enum ViewMode: String, CaseIterable, Identifiable {
        case sunburst = "Sunburst", treemap = "Treemap", list = "List"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .sunburst: return "sun.max"
            case .treemap:  return "square.grid.2x2"
            case .list:     return "list.bullet"
            }
        }
    }

    // MARK: - Phase 4: Smart Filters

    /// Configuration for smart detection (large/old/empty). Bound from the UI.
    var smartFilterConfig = SmartFilterConfig()

    /// Currently active smart filter, or nil for none.
    var activeSmartFilter: SmartFilterKind?

    /// Results of the active smart filter query.
    var smartFilterResults: [SmartFilterResult] = []

    /// Free-space monitor for the scanned volume.
    var freeSpaceMonitor = FreeSpaceMonitor()

    /// Scan history service (persists to UserDefaults).
    var scanHistory = ScanHistoryService()

    /// Rust scanner FFI bridge.
    private let scanner = DirectoryScannerBridge()

    /// Phase 5: Duplicate groups from the last duplicate scan.
    var duplicateGroups: [DuplicateGroup] = []

    /// Phase 5: Whether a duplicate scan is in progress (can be slow for large trees).
    var isDuplicateScanRunning: Bool = false

    /// Phase 4: Sort configuration for clickable header sorting.
    var sortKey: SortKey = .name
    var sortAscending: Bool = true

    enum SortKey: String, CaseIterable, Identifiable {
        case name = "Name"
        case size = "Size"
        case items = "Items"
        case dateModified = "Date Modified"
        var id: String { rawValue }
    }

    func toggleSort(for key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
    }

    func sortedNodes(_ nodes: [DiskNode]) -> [DiskNode] {
        nodes.sorted {
            switch sortKey {
            case .name:
                return sortAscending ? $0.name.localizedCompare($1.name) == .orderedAscending : $0.name.localizedCompare($1.name) == .orderedDescending
            case .size:
                return sortAscending ? $0.physicalSize < $1.physicalSize : $0.physicalSize > $1.physicalSize
            case .items:
                return sortAscending ? $0.childCount < $1.childCount : $0.childCount > $1.childCount
            case .dateModified:
                return sortAscending ? $0.modTimeSecs < $1.modTimeSecs : $0.modTimeSecs > $1.modTimeSecs
            }
        }
    }

    enum SmartFilterKind: String, CaseIterable, Identifiable {
        case large = "Large Files"
        case old = "Old / Unused"
        case empty = "Empty Folders"
        case duplicates = "Duplicates"
        case bundles = "App Bundles"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .large:      return "tray.and.arrow.up"
            case .old:        return "clock.badge.checkmark"
            case .empty:      return "folder.badge.plus"
            case .duplicates: return "doc.on.doc"
            case .bundles:    return "app.badge"
            }
        }
    }

    /// Phase 5: Export current tree as JSON/CSV. Returns nil on failure.
    func exportTree(format: ExportFormat) -> String? {
        guard let root = rootNode else { return nil }
        switch format {
        case .json: return ExportService.exportJSON(root: root)
        case .csv:  return ExportService.exportCSV(root: root)
        }
    }

    enum ExportFormat: String, CaseIterable, Identifiable {
        case json = "JSON"
        case csv = "CSV"
        var id: String { rawValue }
        var fileExtension: String { rawValue.lowercased() }
    }

    /// Run the active smart filter over the current tree.
    func runSmartFilter() {
        guard let root = rootNode, let kind = activeSmartFilter else {
            smartFilterResults = []
            return
        }
        let cfg = smartFilterConfig
        switch kind {
        case .large:
            smartFilterResults = SmartFilterService.findLargeFiles(in: root, config: cfg)
        case .old:
            smartFilterResults = SmartFilterService.findOldFiles(in: root, config: cfg)
        case .empty:
            smartFilterResults = SmartFilterService.findEmptyFolders(in: root, config: cfg)
        case .duplicates:
            // ponytail: duplicate scan is heavier — async, populates duplicateGroups.
            guard !isDuplicateScanRunning else { return }
            isDuplicateScanRunning = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, let root = self.rootNode else { return }
                let groups = DuplicateFinderService.findDuplicates(in: root, config: cfg)
                DispatchQueue.main.async {
                    self.duplicateGroups = groups
                    self.smartFilterResults = groups.flatMap { group in
                        group.duplicateNodes.map { node in
                            SmartFilterResult(node: node, matchedAt: Date(), matchReason: .duplicate)
                        }
                    }
                    self.isDuplicateScanRunning = false
                }
            }
        case .bundles:
            smartFilterResults = AppBundleAnalyzer.findLargeBundles(in: root, config: cfg)
        }
    }

    /// Aggregate tree statistics (powers the sidebar breakdown).
    var treeStats: SmartFilterService.TreeStats {
        rootNode.map { SmartFilterService.computeStats(in: $0) } ?? SmartFilterService.TreeStats()
    }

    // MARK: - Scanning

    func startScan(path: String) {
        // ponytail: allow re-scan from idle, completed, or failed state.
        switch scanState {
        case .idle, .completed, .failed: break
        case .scanning: return  // only block during active scan
        }
        scanState = .scanning(progress: 0.0)
        let startTime = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let rootNode = self.scanner.scan(path: path, config: ScanConfig())
            let duration = Date().timeIntervalSince(startTime)

            DispatchQueue.main.async {
                guard let rootNode = rootNode else {
                    self.scanState = .failed(error: "Scan failed")
                    return
                }
                self.rootNode = rootNode
                self.activeSmartFilter = nil
                self.smartFilterResults = []
                let size = rootNode.physicalSize
                let count = self.treeStats.totalFiles + self.treeStats.totalDirectories
                self.scanState = .completed(totalSize: size, fileCount: count)
                self.scanHistory.recordScan(
                    volumePath: path,
                    totalFiles: count,
                    totalSize: size,
                    duration: duration
                )
                self.startFreeSpaceMonitoring(for: URL(fileURLWithPath: path))
            }
        }
    }

    func cancelScan() {
        scanState = .idle
        rootNode = nil
        smartFilterResults = []
        activeSmartFilter = nil
    }

    // MARK: - Free Space

    /// Begin live free-space monitoring for the scanned volume.
    func startFreeSpaceMonitoring(for url: URL) {
        let volume = DiskVolumeService.mountedVolumes().first(where: { $0.url == url })
            ?? DiskVolume(url: url, name: url.lastPathComponent,
                          totalCapacity: 0, availableCapacity: 0,
                          isRemovable: false, isReadOnly: false)
        freeSpaceMonitor.startMonitoring(volume: volume, interval: 5.0)
    }

    // MARK: - Selection

    func selectNode(_ node: DiskNode) {
        if isBatchMode {
            toggleSelection(node)
        } else {
            selectedNode = node
        }
    }

    func toggleSelection(_ node: DiskNode) {
        if selectedNodes.contains(node.id) {
            selectedNodes.remove(node.id)
        } else {
            selectedNodes.insert(node.id)
        }
    }

    func clearSelection() {
        selectedNode = nil
        selectedNodes.removeAll()
    }

    func clearBatchSelection() {
        selectedNodes.removeAll()
    }

    // MARK: - Batch Operations

    /// Returns the set of selected node paths for batch deletion.
    var selectedPaths: [String] {
        var paths: [String] = []
        guard let root = rootNode else { return paths }
        collectSelectedPaths(from: root, into: &paths)
        return paths
    }

    private func collectSelectedPaths(from node: DiskNode, into paths: inout [String]) {
        if selectedNodes.contains(node.id) {
            paths.append(node.path)
        }
        node.children?.forEach { collectSelectedPaths(from: $0, into: &paths) }
    }

    /// Total size of all selected nodes.
    var selectedTotalSize: UInt64 {
        guard let root = rootNode else { return 0 }
        var total: UInt64 = 0
        collectSelectedSizes(from: root, into: &total)
        return total
    }

    private func collectSelectedSizes(from node: DiskNode, into total: inout UInt64) {
        if selectedNodes.contains(node.id) {
            total += node.physicalSize
        }
        node.children?.forEach { collectSelectedSizes(from: $0, into: &total) }
    }
}
