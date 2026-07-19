//
//  DuplicateFinderService.swift
//  DiskTracker
//
//  Phase 5: Content-aware duplicate detection via partial + full SHA-256.
//  Bucketed by physical size to avoid O(n²) pairwise hash comparison.
//  Uses CryptoKit (native Swift, no bridging header needed).
//

import Foundation
import CryptoKit

// Note: DuplicateGroup struct is defined in AppModel.swift (file scope for @Observable macro compatibility)

// MARK: - Duplicate Finder Service

/// Content-aware duplicate detection.
///
/// Strategy:
/// 1. Bucket files by physical size (skip anything < 1 KB).
/// 2. For buckets with >1 file, hash first 64 KB (partial SHA-256).
/// 3. Partial matches get full SHA-256; full matches form DuplicateGroup.
enum DuplicateFinderService {

    /// Minimum file size to consider for hashing (skip tiny files).
    static let minFileSize: UInt64 = 1_024

    /// Bytes to read for the partial-hash filter pass.
    static let partialReadSize = 64 * 1_024

    // MARK: - Entry Point

    /// Scan the DiskNode tree and return duplicate groups sorted by wasted space descending.
    static func findDuplicates(
        in root: DiskNode,
        config: SmartFilterConfig = SmartFilterConfig()
    ) -> [DuplicateGroup] {
        // 1. Collect all non-directory files
        var allFiles: [DiskNode] = []
        collectFiles(from: root, config: config, into: &allFiles)

        // 2. Bucket by physical size, skip singletons and tiny files
        var sizeBuckets: [UInt64: [DiskNode]] = [:]
        for file in allFiles {
            guard file.physicalSize >= minFileSize else { continue }
            sizeBuckets[file.physicalSize, default: []].append(file)
        }
        let candidates = sizeBuckets.filter { $0.value.count > 1 }

        guard !candidates.isEmpty else { return [] }

        // 3. Partial-hash filter (first 64 KB)
        var partialBuckets: [SHA256Digest: [DiskNode]] = [:]
        for (_, files) in candidates {
            for file in files {
                guard let partial = partialSHA256(url: URL(fileURLWithPath: file.path)) else { continue }
                partialBuckets[partial, default: []].append(file)
            }
        }
        let partialMatches = partialBuckets.filter { $0.value.count > 1 }

        guard !partialMatches.isEmpty else { return [] }

        // 4. Full-hash confirmation; group duplicates
        var fullToGroup: [SHA256Digest: [DiskNode]] = [:]
        for (_, files) in partialMatches {
            for file in files {
                guard let full = fullSHA256(url: URL(fileURLWithPath: file.path)) else { continue }
                fullToGroup[full, default: []].append(file)
            }
        }

        var groups: [DuplicateGroup] = []
        for (hash, nodes) in fullToGroup where nodes.count > 1 {
            let orig = nodes.max(by: { $0.modTimeSecs < $1.modTimeSecs })!
            let wasted = nodes.filter { $0.id != orig.id }.reduce(UInt64(0)) { $0 + $1.physicalSize }
            groups.append(DuplicateGroup(
                hash: Data(hash),
                nodes: nodes,
                wastedBytes: wasted
            ))
        }

        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    // MARK: - Hashing

    /// SHA-256 of the first `partialReadSize` bytes.
    private static func partialSHA256(url: URL) -> SHA256Digest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: partialReadSize)
        guard !data.isEmpty else { return nil }
        return SHA256.hash(data: data)
    }

    /// Full-file SHA-256.  Uses streaming for large files.
    private static func fullSHA256(url: URL) -> SHA256Digest? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1_048_576)  // 1 MB chunks
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }

    // MARK: - Tree Traversal

    private static func collectFiles(
        from node: DiskNode,
        config: SmartFilterConfig,
        into files: inout [DiskNode]
    ) {
        if !config.includeHiddenFiles && node.name.hasPrefix(".") { return }
        if !config.includeSystemPaths && node.isSystemProtected { return }

        if node.fileKind != .directory {
            files.append(node)
        }
        node.children?.forEach { collectFiles(from: $0, config: config, into: &files) }
    }
}