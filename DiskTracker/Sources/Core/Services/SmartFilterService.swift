//
//  SmartFilterService.swift
//  DiskTracker
//
//  Phase 4: Smart detection engine — large files, old files, empty folders.
//

import Foundation

// MARK: - Filter Configuration

/// Threshold and configuration for smart detection features.
struct SmartFilterConfig: Equatable, Sendable {
    var largeFileThresholdGB: Double = 1.0
    var oldFileThresholdMonths: Int = 6
    var includeSystemPaths: Bool = false
    var includeHiddenFiles: Bool = false

    /// Threshold in bytes for large file detection.
    var largeFileThresholdBytes: UInt64 {
        UInt64(largeFileThresholdGB * 1_024 * 1_024 * 1_024)
    }

    /// Threshold date for old file detection.
    var oldFileThresholdDate: Date {
        Calendar.current.date(byAdding: .month, value: -oldFileThresholdMonths, to: Date()) ?? Date.distantPast
    }
}

// MARK: - Detection Result

/// A single detected item from a smart filter query.
struct SmartFilterResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let node: DiskNode
    let matchedAt: Date
    let matchReason: MatchReason

    enum MatchReason: String, Sendable {
        case largeFile = "Large File"
        case oldFile = "Unused"
        case emptyFolder = "Empty Folder"
        case duplicate = "Duplicate"
    }
}

// MARK: - Smart Filter Service

/// Performs detection queries over a scanned DiskNode tree.
///
/// All methods traverse the tree recursively and collect matching nodes.
/// Results are sorted by relevance (size for large files, age for old files).
enum SmartFilterService {

    // MARK: - Large File Finder

    /// Find files exceeding the configured size threshold.
    ///
    /// - Parameters:
    ///   - root: Root of the scanned tree.
    ///   - config: Filter configuration (threshold, exclusions).
    /// - Returns: Detected large files, sorted by physical size descending.
    static func findLargeFiles(
        in root: DiskNode,
        config: SmartFilterConfig
    ) -> [SmartFilterResult] {
        var results: [SmartFilterResult] = []
        let threshold = config.largeFileThresholdBytes

        traverse(node: root, config: config) { node in
            guard node.fileKind != .directory else { return }
            if node.physicalSize >= threshold {
                results.append(SmartFilterResult(
                    node: node,
                    matchedAt: Date(),
                    matchReason: .largeFile
                ))
            }
        }

        return results.sorted { $0.node.physicalSize > $1.node.physicalSize }
    }

    // MARK: - Old / Unused File Finder

    /// Find files not modified since the configured threshold date.
    ///
    /// - Parameters:
    ///   - root: Root of the scanned tree.
    ///   - config: Filter configuration.
    /// - Returns: Detected old files, sorted by modification time ascending (oldest first).
    static func findOldFiles(
        in root: DiskNode,
        config: SmartFilterConfig
    ) -> [SmartFilterResult] {
        var results: [SmartFilterResult] = []
        let thresholdDate = config.oldFileThresholdDate

        // Get current timestamp for comparison
        let now = Date()
        let thresholdSecs = thresholdDate.timeIntervalSince1970

        traverse(node: root, config: config) { node in
            guard node.fileKind != .directory else { return }
            // modTimeSecs from Rust FFI — negative or zero means unavailable
            let modTime = node.modTimeSecs
            if modTime > 0 && Double(modTime) < thresholdSecs {
                results.append(SmartFilterResult(
                    node: node,
                    matchedAt: now,
                    matchReason: .oldFile
                ))
            }
        }

        return results.sorted { $0.node.modTimeSecs < $1.node.modTimeSecs }
    }

    // MARK: - Empty Folder Finder

    /// Find directories with no files (only empty subdirectories or truly empty).
    ///
    /// A folder is "empty" if it contains zero files at any depth.
    /// The root is only included if it has no children at all.
    ///
    /// - Parameters:
    ///   - root: Root of the scanned tree.
    ///   - config: Filter configuration.
    /// - Returns: Detected empty folders, deepest first.
    static func findEmptyFolders(
        in root: DiskNode,
        config: SmartFilterConfig
    ) -> [SmartFilterResult] {
        var results: [SmartFilterResult] = []
        let now = Date()

        // ponytail: tests leave recordIndex at 0 for every node, so we use a
        // content key instead. We compute depths once per call (O(n)) and
        // skip the root unless it's a true 0-child directory.
        // ceiling: content-based identity. upgrade: when DiskNode.id is stable.
        let depths = depthMap(from: root)
        func depthOf(_ node: DiskNode) -> Int {
            depths[Self.key(for: node)] ?? Int(node.depth)
        }

        if isLeafDirectory(root) {
            results.append(SmartFilterResult(
                node: root, matchedAt: now, matchReason: .emptyFolder
            ))
            return results.sorted { depthOf($0.node) > depthOf($1.node) }
        }

        collectEmptyDescendants(node: root, config: config,
                                results: &results, now: now)
        return results.sorted { depthOf($0.node) > depthOf($1.node) }
    }

    /// Recursively appends descendant directories that contain no files.
    static func collectEmptyDescendants(
        node: DiskNode,
        config: SmartFilterConfig,
        results: inout [SmartFilterResult],
        now: Date
    ) {
        for child in node.children ?? [] {
            if !config.includeHiddenFiles && child.name.hasPrefix(".") { continue }
            if !config.includeSystemPaths && child.isSystemProtected { continue }
            guard child.fileKind == .directory else { continue }
            if !hasFiles(at: child) {
                results.append(SmartFilterResult(
                    node: child, matchedAt: now, matchReason: .emptyFolder
                ))
            }
            collectEmptyDescendants(
                node: child, config: config,
                results: &results, now: now
            )
        }
    }

    /// Returns true if the node or any descendant is a file.
    private static func hasFiles(at node: DiskNode) -> Bool {
        guard let children = node.children else { return false }
        for child in children {
            // ponytail: FileKind has no symlink case; symlinks classify as .other.
            // Count .other as a file so empty-folder detection stays conservative.
            if child.fileKind != .directory {
                return true
            }
            if hasFiles(at: child) {
                return true
            }
        }
        return false
    }

    /// True when `node` is a directory with no children (truly empty dir).
    private static func isLeafDirectory(_ node: DiskNode) -> Bool {
        guard node.fileKind == .directory else { return false }
        return (node.children?.isEmpty ?? true)
    }

    /// Walks `root` once, mapping each node to its true depth (0-based).
    /// ponytail: O(n) per call; call sites pass the same root twice (sort +
    /// collect), so the result is reused.
    private static func depthMap(from root: DiskNode) -> [String: Int] {
        var out: [String: Int] = [:]
        func walk(_ n: DiskNode, _ d: Int) {
            out[Self.key(for: n)] = d
            for c in n.children ?? [] { walk(c, d + 1) }
        }
        walk(root, 0)
        return out
    }

    /// Map each node's identity to its 0-based depth from `root`.
    /// ponytail: O(n); runs once per findEmptyFilters call. Uses path+name as
    /// key because test fixtures give every node `recordIndex = 0`.
    private static func depthsIn(_ root: DiskNode) -> [String: Int] {
        var out: [String: Int] = [:]
        func walk(_ n: DiskNode, _ d: Int) {
            out[Self.key(for: n)] = d
            for c in n.children ?? [] { walk(c, d + 1) }
        }
        walk(root, 0)
        return out
    }

    /// Stable identity key for `DiskNode` without IDs (DiskNode.id is per-instance).
    private static func key(for node: DiskNode) -> String {
        "\(node.path)|\(node.name)|\(node.recordIndex)|\(node.physicalSize)"
    }

    // MARK: - File Type Filter

    /// Find all files matching a specific file kind.
    ///
    /// - Parameters:
    ///   - root: Root of the scanned tree.
    ///   - kind: The file kind to match.
    ///   - config: Filter configuration.
    /// - Returns: Matching files, sorted by physical size descending.
    static func findByFileType(
        in root: DiskNode,
        kind: FileKind,
        config: SmartFilterConfig
    ) -> [SmartFilterResult] {
        var results: [SmartFilterResult] = []
        let now = Date()

        traverse(node: root, config: config) { node in
            if node.fileKind == kind {
                results.append(SmartFilterResult(
                    node: node,
                    matchedAt: now,
                    matchReason: .largeFile  // Re-use — type-specific reason not needed
                ))
            }
        }

        return results.sorted { $0.node.physicalSize > $1.node.physicalSize }
    }

    // MARK: - Aggregate Statistics

    /// Compute aggregate statistics for the scanned tree.
    struct TreeStats: Sendable {
        var totalFiles: Int = 0
        var totalDirectories: Int = 0
        var totalSymlinks: Int = 0
        var totalSize: UInt64 = 0
        var largestFile: DiskNode?
        var oldestFile: DiskNode?
        var fileTypeCounts: [FileKind: Int] = [:]
        var fileTypeSizes: [FileKind: UInt64] = [:]
    }

    static func computeStats(in root: DiskNode) -> TreeStats {
        var stats = TreeStats()
        stats.fileTypeCounts = Dictionary(uniqueKeysWithValues: FileKind.allCases.map { ($0, 0) })
        stats.fileTypeSizes = Dictionary(uniqueKeysWithValues: FileKind.allCases.map { ($0, 0) })

        accumulateStats(node: root, into: &stats)
        return stats
    }

    private static func accumulateStats(node: DiskNode, into stats: inout TreeStats) {
        switch node.fileKind {
        case .directory:
            stats.totalDirectories += 1
        // ponytail: symlink tracking not in FileKind; all non-directory nodes
        // (including symlinks) count as files.
        default:
            stats.totalFiles += 1
            stats.totalSize += node.physicalSize

            if stats.largestFile == nil || node.physicalSize > stats.largestFile!.physicalSize {
                stats.largestFile = node
            }
            if stats.oldestFile == nil || node.modTimeSecs < stats.oldestFile!.modTimeSecs {
                stats.oldestFile = node
            }
        }

        stats.fileTypeCounts[node.fileKind, default: 0] += 1
        stats.fileTypeSizes[node.fileKind, default: 0] += node.physicalSize

        node.children?.forEach { accumulateStats(node: $0, into: &stats) }
    }

    // MARK: - Traversal Helpers

    /// Recursive tree traversal that respects filter configuration.
    private static func traverse(
        node: DiskNode,
        config: SmartFilterConfig,
        visitor: (DiskNode) -> Void
    ) {
        // Skip hidden files unless configured
        if !config.includeHiddenFiles && node.name.hasPrefix(".") { return }

        // Skip system paths unless configured
        if !config.includeSystemPaths && node.isSystemProtected { return }

        visitor(node)
        node.children?.forEach { traverse(node: $0, config: config, visitor: visitor) }
    }
}
