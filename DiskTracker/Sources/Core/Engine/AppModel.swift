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
enum FileKind: UInt8, CaseIterable, Sendable, Codable {
    case image = 0, video = 1, audio = 2, document = 3
    case archive = 4, application = 5, other = 6, directory = 7

    /// Singular, human-facing name for one item of this kind.
    var displayName: String {
        switch self {
        case .image:       return "Image"
        case .video:       return "Video"
        case .audio:       return "Audio"
        case .document:    return "Document"
        case .archive:     return "Archive"
        case .application: return "Application"
        case .directory:   return "Folder"
        case .other:       return "File"
        }
    }

    var iconName: String {
        switch self {
        case .image:       return "photo"
        case .video:       return "film"
        case .audio:       return "music.note"
        case .document:    return "doc"
        case .archive:     return "doc.zipper"
        case .application: return "app"
        case .directory:   return "folder"
        case .other:       return "doc.questionmark"
        }
    }
}

/// One node in the flat array returned by the Rust engine.
struct DiskNode: Identifiable, Equatable, Sendable, Hashable, Codable {
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
    var childCount: UInt32 = 0
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

    /// Total physical size of this node and all descendants (recursive). Computed by
    /// `computeTotalPhysicalSizes` after the full tree is built.
    var totalPhysicalSize: UInt64 = 0

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

/// Top-level navigation phase. Drives the root window content in
/// `DiskTrackerApp`. Transitions are explicit via `navigate(to:)` so
/// tests + the UI agree on the state machine.
enum AppPhase: Equatable, Sendable {
    case onboarding
    case dashboard
    case scanResults
}

/// One of the categories shown in the Scan Results sidebar.
/// Mirrors the mock's category list (Directories/Images/Videos/Documents/
/// Applications/Archives/Other).
enum ScanCategory: String, CaseIterable, Identifiable, Sendable {
    case directories = "Directories"
    case images = "Images"
    case videos = "Videos"
    case documents = "Documents"
    case applications = "Applications"
    case archives = "Archives"
    case other = "Other"

    var id: String { rawValue }

    /// SF Symbol for the sidebar row. These were Material Icons names carried
    /// over from the HTML mock, which render as blank rows on macOS.
    var icon: String {
        switch self {
        case .directories:   return "folder"
        case .images:        return "photo"
        case .videos:        return "film"
        case .documents:     return "doc.text"
        case .applications:  return "app"
        case .archives:      return "doc.zipper"
        case .other:         return "ellipsis.circle"
        }
    }

    /// Corresponding `FileKind`s this category aggregates.
    var fileKinds: [FileKind] {
        switch self {
        case .directories:   return [.directory]
        case .images:        return [.image]
        case .videos:        return [.video]
        case .documents:     return [.document, .audio] // docs + audio grouped
        case .applications:  return [.application]
        case .archives:      return [.archive]
        case .other:         return [.other]
        }
    }
}

/// Global observable model.
@Observable
final class AppModel: @unchecked Sendable {
    var scanState: ScanState = .idle
    var rootNode: DiskNode? {
        didSet {
            cachedTreeStats = nil
            cachedMatches = nil
        }
    }
    var selectedNode: DiskNode?
    var currentView: ViewMode = .sunburst

    // MARK: - Navigation helpers

    /// Explicit phase transition. Keeps the navigation state machine in
    /// one place so tests can drive it and the UI never mutates `phase`
    /// directly.
    func navigate(to phase: AppPhase) {
        self.phase = phase
        if phase == .scanResults, rootNode == nil {
            // Defensive: should not happen, but if a caller enters scan
            // results with no tree, fall back to dashboard.
            self.phase = .dashboard
        }
    }

    /// Re-open Scan Results using a previously-recorded scan entry.
    /// Loads the serialized tree from disk and sets it as the current tree.
    /// No new filesystem scan is performed.
    func restoreScanFromHistory(_ entry: ScanHistoryEntry) {
        currentScanPath = entry.volumePath
        phase = .scanResults

        // Reading + decoding a recorded tree takes seconds on a large scan —
        // never on the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self,
                  let data = self.scanHistory.loadTree(for: entry),
                  let tree = try? JSONDecoder().decode(DiskNode.self, from: data) else { return }
            let stats = SmartFilterService.computeStats(in: tree)
            DispatchQueue.main.async {
                self.rootNode = tree
                self.cachedTreeStats = stats
                self.selectedNode = tree
                self.scanState = .completed(totalSize: entry.totalSize, fileCount: entry.totalFiles)
            }
        }
    }

    /// Whether the user is currently allowed to start a new scan. While a
    /// scan is in flight, the model blocks new scans (multi-scan is a
    /// later phase). Use this to disable the toolbar "Scan" button.
    var canStartNewScan: Bool {
        if case .scanning = scanState { return false }
        return true
    }

    /// Current root phase. Drives which view `ContentView` shows.
    var phase: AppPhase = .dashboard

    /// Selected category in the Scan Results sidebar.
    var selectedCategory: ScanCategory = .directories {
        didSet { if oldValue != selectedCategory { cachedMatches = nil } }
    }

    /// Text typed into the Scan Results search field.
    var searchQuery: String = "" {
        didSet { if oldValue != searchQuery { cachedMatches = nil } }
    }

    /// Whether the results area should show a flat, filtered list instead of
    /// the directory hierarchy.
    var isFiltering: Bool {
        selectedCategory != .directories || !searchQuery.isEmpty
    }

    /// Cap on flat results. A category match over a large scan can run to
    /// hundreds of thousands of rows, which no one scrolls through.
    static let maxFilterMatches = 1_000

    @ObservationIgnored
    private var cachedMatches: [DiskNode]?

    /// Files matching the selected category and search text, largest first.
    /// Cached because it walks the whole tree.
    var filteredNodes: [DiskNode] {
        guard let root = rootNode else { return [] }
        if let cached = cachedMatches { return cached }

        let kinds = Set(selectedCategory.fileKinds)
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var matches: [DiskNode] = []

        func walk(_ node: DiskNode) {
            // Category .directories means "no kind filter" when searching —
            // otherwise a search would only ever return folders.
            let kindMatches = selectedCategory == .directories || kinds.contains(node.fileKind)
            let textMatches = query.isEmpty || node.name.lowercased().contains(query)
            if kindMatches && textMatches && node.path != root.path {
                matches.append(node)
            }
            node.children?.forEach(walk)
        }
        walk(root)

        let sorted = matches
            .sorted { weightForSort($0) > weightForSort($1) }
            .prefix(Self.maxFilterMatches)
        let result = Array(sorted)
        cachedMatches = result
        return result
    }

    private func weightForSort(_ node: DiskNode) -> UInt64 {
        node.fileKind == .directory ? node.totalPhysicalSize : node.physicalSize
    }

    /// Number of items in a category, for the sidebar badge.
    func itemCount(for category: ScanCategory) -> Int {
        let counts = treeStats.fileTypeCounts
        return category.fileKinds.reduce(0) { $0 + (counts[$1] ?? 0) }
    }

    /// Path currently being scanned (or last scanned). Used by the toolbar
    /// + status bar so the user always sees which folder a running scan
    /// belongs to.
    var currentScanPath: String = NSHomeDirectory()

    /// Tracks which folder node IDs are expanded in the list view.
    var expandedNodeIds: Set<UUID> = []

    func toggleExpanded(_ node: DiskNode) {
        if expandedNodeIds.contains(node.id) {
            expandedNodeIds.remove(node.id)
        } else {
            expandedNodeIds.insert(node.id)
        }
    }

    func isExpanded(_ node: DiskNode) -> Bool {
        expandedNodeIds.contains(node.id)
    }

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
                let isFolderA = $0.fileKind == .directory
                let isFolderB = $1.fileKind == .directory
                if isFolderA != isFolderB {
                    return isFolderA // folders first
                }
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

    /// Serialize the current tree. Returns nil when there is no scan.
    ///
    /// O(tree) and allocates the whole document as a string — for a million
    /// files that is hundreds of megabytes, so callers run it off the main
    /// thread. `writeExport` is the one that does.
    func exportTree(format: ExportFormat) -> String? {
        guard let root = rootNode else { return nil }
        switch format {
        case .json: return ExportService.exportJSON(root: root)
        case .csv:  return ExportService.exportCSV(root: root)
        }
    }

    /// True while an export is being written. Disables the menu item so a
    /// second export cannot start on top of the first.
    var isExporting: Bool = false

    /// A default file name for the export, derived from what was scanned.
    ///
    /// Scanning a volume root is ordinary, and `URL(fileURLWithPath: "/")`
    /// reports "/" as its last component — which would put a path separator in
    /// the middle of a file name. Anything that is not a usable name falls back
    /// to "scan".
    func exportFileName(format: ExportFormat) -> String {
        let last = URL(fileURLWithPath: currentScanPath).lastPathComponent
        let cleaned = last.replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "scan" : cleaned
        let stamp = Self.exportDateFormatter.string(from: Date())
        return "\(base)-\(stamp).\(format.fileExtension)"
    }

    @ObservationIgnored
    private static let exportDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Serializes the tree and writes it to `url`, off the main thread.
    ///
    /// `completion` runs on the main thread with the error, or nil on success.
    func writeExport(format: ExportFormat, to url: URL, completion: @escaping @Sendable (Error?) -> Void) {
        guard rootNode != nil else {
            completion(ExportError.noScan)
            return
        }
        isExporting = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let document = self.exportTree(format: format)

            var failure: Error?
            if let document {
                do {
                    try document.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    failure = error
                }
            } else {
                failure = ExportError.noScan
            }

            DispatchQueue.main.async {
                self.isExporting = false
                completion(failure)
            }
        }
    }

    enum ExportError: LocalizedError {
        case noScan
        var errorDescription: String? {
            switch self {
            case .noScan: return "There is no scan to export."
            }
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

    /// Cache for `treeStats`. Invalidated whenever `rootNode` changes.
    /// Observation-ignored so filling it inside the getter can't invalidate a
    /// view mid-render; `treeStats` reads `rootNode` first, which is what
    /// registers the dependency.
    @ObservationIgnored
    private var cachedTreeStats: SmartFilterService.TreeStats?

    /// Aggregate tree statistics (powers the sidebar breakdown). Walks the
    /// whole tree, so the result is cached — a computed walk on every view
    /// body evaluation is a frame-rate killer on a large scan.
    var treeStats: SmartFilterService.TreeStats {
        guard let root = rootNode else { return SmartFilterService.TreeStats() }
        if let cached = cachedTreeStats { return cached }
        let stats = SmartFilterService.computeStats(in: root)
        cachedTreeStats = stats
        return stats
    }

    // MARK: - Scanning

    /// Entries the running (or last) scan has seen so far. The engine reports a
    /// count, not a fraction — the total is unknowable until the walk ends.
    var filesScanned: Int = 0

    /// Bumped on every start and cancel, so a scan that finishes after being
    /// cancelled (or superseded) can't overwrite newer state.
    @ObservationIgnored
    private var scanGeneration = 0

    func startScan(path: String) {
        // ponytail: allow re-scan from idle, completed, or failed state.
        switch scanState {
        case .idle, .completed, .failed: break
        case .scanning: return  // only block during active scan
        }
        currentScanPath = path
        phase = .scanResults
        scanState = .scanning(progress: 0.0)
        filesScanned = 0
        scanGeneration += 1
        let generation = scanGeneration
        let startTime = Date()
        // Read on the main thread; the scan closure must not touch model state.
        let scanConfig = ScanConfig(excludeHiddenFiles: !showHiddenFiles)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // Re-establish sandbox access to a folder chosen in an earlier
            // launch. Held for the whole scan; nil is normal for paths that
            // need no grant, and the scan proceeds either way.
            // Access ends when the grant deinits, so it is held explicitly for
            // the whole scan rather than left to the optimiser.
            let grant = ScopedAccess.access(path: path)
            defer { withExtendedLifetime(grant) {} }

            let scanned = self.scanner.scan(path: path, config: scanConfig) { count in
                DispatchQueue.main.async {
                    guard generation == self.scanGeneration else { return }
                    self.filesScanned = count
                }
            }
            guard let rootNode = scanned else {
                DispatchQueue.main.async {
                    // A cancelled scan also returns nil — it bumped the
                    // generation, so this is a real failure only if it didn't.
                    guard generation == self.scanGeneration else { return }
                    self.scanState = .failed(error: "Scan failed")
                }
                return
            }
            let duration = Date().timeIntervalSince(startTime)

            // Stats, serialization and the history write are all O(tree) and
            // used to run on the main thread — that was the post-scan freeze.
            let stats = SmartFilterService.computeStats(in: rootNode)
            let count = stats.totalFiles + stats.totalDirectories
            let size = rootNode.totalPhysicalSize
            let treeFile = (try? JSONEncoder().encode(rootNode)).flatMap { self.scanHistory.saveTree($0) }

            DispatchQueue.main.async {
                guard generation == self.scanGeneration else { return }
                self.rootNode = rootNode
                self.cachedTreeStats = stats
                self.activeSmartFilter = nil
                self.smartFilterResults = []
                self.scanState = .completed(totalSize: size, fileCount: count)

                // Only the metadata + tree file name go through UserDefaults.
                self.scanHistory.recordScan(
                    volumePath: path,
                    totalFiles: count,
                    totalSize: size,
                    duration: duration,
                    treeFile: treeFile
                )
                self.startFreeSpaceMonitoring(for: URL(fileURLWithPath: path))
            }
        }
    }

    func cancelScan() {
        // Bump first: the engine process dies, the in-flight scan returns nil,
        // and the stale generation keeps it from reporting a failure.
        scanGeneration += 1
        scanner.cancel()
        scanState = .idle
        rootNode = nil
        filesScanned = 0
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
        freeSpaceMonitor.thresholdPercent = LowSpaceSettings.thresholdPercent
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

    /// The selected nodes themselves, for the batch bar's size and kind checks.
    ///
    /// A selected folder's descendants are not included: they go to Trash with
    /// the folder, and listing them separately would double-count the bytes and
    /// make the confirmation dialog claim far more items than it deletes.
    var selectedDiskNodes: [DiskNode] {
        guard let root = rootNode else { return [] }
        var found: [DiskNode] = []
        func walk(_ node: DiskNode) {
            if selectedNodes.contains(node.id) {
                found.append(node)
                return
            }
            node.children?.forEach(walk)
        }
        walk(root)
        return found
    }

    /// Total size of all selected nodes — what deleting them would reclaim.
    var selectedTotalSize: UInt64 {
        guard let root = rootNode else { return 0 }
        var total: UInt64 = 0
        collectSelectedSizes(from: root, into: &total)
        return total
    }

    private func collectSelectedSizes(from node: DiskNode, into total: inout UInt64) {
        if selectedNodes.contains(node.id) {
            // A selected folder reclaims everything under it, so the recursive
            // total is the honest number. `physicalSize` alone is 0 for a
            // directory, which made a folder selection read as "0 bytes".
            total += node.fileKind == .directory ? node.totalPhysicalSize : node.physicalSize
            // Descendants of a selected folder go with it; counting them again
            // would double their bytes.
            return
        }
        node.children?.forEach { collectSelectedSizes(from: $0, into: &total) }
    }

    // MARK: - Tree mutation

    /// Removes nodes from the in-memory tree after they have been trashed, and
    /// recomputes the folder totals above them.
    ///
    /// Re-scanning instead would be simpler, but a scan of a large volume takes
    /// seconds and the user just deleted one file — the tree they are looking
    /// at has to stay put.
    func removeFromTree(paths: [String]) {
        guard var root = rootNode, !paths.isEmpty else { return }
        let doomed = Set(paths)
        // Deleting the scan root itself leaves nothing to show.
        guard !doomed.contains(root.path) else {
            rootNode = nil
            scanState = .idle
            clearSelection()
            return
        }

        prune(&root, doomed: doomed)
        // Assigning through the property runs the didSet that drops the
        // treeStats and filteredNodes caches; both are derived from the tree.
        rootNode = root

        // A deleted node must not stay selected — selection drives the detail
        // pane and the batch bar.
        selectedNodes = selectedNodes.filter { id in Self.contains(root, id: id) }
        if let selected = selectedNode, doomed.contains(selected.path) {
            selectedNode = nil
        }

        if case .completed = scanState {
            let stats = SmartFilterService.computeStats(in: root)
            scanState = .completed(
                totalSize: root.totalPhysicalSize,
                fileCount: stats.totalFiles + stats.totalDirectories
            )
        }
    }

    /// Drops `doomed` paths from `node`'s subtree and refreshes its total.
    /// Returns true when anything below this node changed, so unaffected
    /// branches are left alone rather than rebuilt.
    @discardableResult
    private func prune(_ node: inout DiskNode, doomed: Set<String>) -> Bool {
        guard var children = node.children, !children.isEmpty else { return false }

        var changed = false
        var kept: [DiskNode] = []
        kept.reserveCapacity(children.count)

        for i in children.indices {
            if doomed.contains(children[i].path) {
                changed = true
                continue
            }
            var child = children[i]
            if prune(&child, doomed: doomed) { changed = true }
            kept.append(child)
        }
        guard changed else { return false }

        children = kept
        node.children = children
        node.childCount = UInt32(children.count)
        node.totalPhysicalSize = children.isEmpty
            ? node.physicalSize
            : children.reduce(UInt64(0)) { $0 + $1.totalPhysicalSize }
        return true
    }

    private static func contains(_ node: DiskNode, id: UUID) -> Bool {
        if node.id == id { return true }
        return node.children?.contains { contains($0, id: id) } ?? false
    }
}
