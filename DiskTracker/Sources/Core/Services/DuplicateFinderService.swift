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

// MARK: - Inline hasher protocol

/// Source of bytes for duplicate hashing — defaults to disk reads; tests inject in-memory data.
protocol DuplicateContentSource {
    /// Returns up to `length` bytes from the start of `url`. ponytail: shorter reads are valid.
    func read(url: URL, length: Int) -> Data?
    /// Streams the entire file in chunks. ponytail: tests can satisfy with one chunk.
    func readAll(url: URL) -> Data?
}

struct DiskContentSource: DuplicateContentSource {
    func read(url: URL, length: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return handle.readData(ofLength: length)
    }
    func readAll(url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var out = Data()
        while true {
            let chunk = handle.readData(ofLength: 1_048_576)
            if chunk.isEmpty { break }
            out.append(chunk)
        }
        return out
    }
}

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

    /// Default disk-backed source. Tests inject their own via `setContentSource(_:)`.
    /// ponytail: kept as a static var so tests can swap on/off. Equivalent in cost to
    /// a shared actor — duplicates are run on background queues anyway.
    nonisolated(unsafe) static var contentSource: DuplicateContentSource = DiskContentSource()

    /// Tests use this to install a fake content source; pass `nil` to restore defaults.
    static func setContentSource(_ source: DuplicateContentSource?) {
        contentSource = source ?? DiskContentSource()
    }

    // MARK: - Entry Point

    /// Scan the DiskNode tree and return duplicate groups sorted by wasted space descending.
    static func findDuplicates(
        in root: DiskNode,
        config: SmartFilterConfig = SmartFilterConfig()
    ) -> [DuplicateGroup] {
        // 1. Collect all non-directory files.
        var allFiles: [DiskNode] = []
        collectFiles(from: root, config: config, into: &allFiles)

        // 2. 3 steps: size-bucket (skip tiny + singletons), partial SHA, full SHA. Each
        // step's "count > 1" filter is the same shape — extracted via the helpers below.
        let sizeMatches = bucketsOf(allFiles, key: \.physicalSize)
            .filter { $0.value.count > 1 && $0.key >= minFileSize }
        guard !sizeMatches.isEmpty else { return [] }

        let partialMatches = hashedBuckets(sizeMatches, hash: partialSHA256(url:))
            .filter { $0.value.count > 1 }
        guard !partialMatches.isEmpty else { return [] }

        let fullBuckets = hashedBuckets(partialMatches, hash: fullSHA256(url:))

        var groups: [DuplicateGroup] = []
        for (hash, nodes) in fullBuckets where nodes.count > 1 {
            let orig = nodes.max(by: { $0.modTimeSecs < $1.modTimeSecs })!
            let wasted = nodes.filter { $0.id != orig.id }.reduce(UInt64(0)) { $0 + $1.physicalSize }
            groups.append(DuplicateGroup(
                hash: hash,
                nodes: nodes,
                wastedBytes: wasted
            ))
        }

        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    // MARK: - Hashing

    /// SHA-256 of the first `partialReadSize` bytes. Returns the raw digest as `Data`.
    private static func partialSHA256(url: URL) -> Data? {
        sha256(of: contentSource.read(url: url, length: partialReadSize))
    }

    /// Full-file SHA-256. Returns raw digest bytes.
    private static func fullSHA256(url: URL) -> Data? {
        sha256(of: contentSource.readAll(url: url))
    }

    /// ponytail: shared SHA-256 wrapper — nil for missing/empty input so the bucket
    /// step silently drops unreadable files instead of two hand-written guards.
    private static func sha256(of data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        return Data(SHA256.hash(data: data))
    }

    // MARK: - Bucketing

    /// Group a sequence by a hashable key (e.g. physicalSize).
    private static func bucketsOf<T>(_ items: [T], key: KeyPath<T, UInt64>) -> [UInt64: [T]] {
        var out: [UInt64: [T]] = [:]
        for item in items { out[item[keyPath: key], default: []].append(item) }
        return out
    }

    /// Re-bucket each input bucket by a content-derived hash. Items whose read fails
    /// are dropped from their destination bucket (matches the "skip silently" intent
    /// of the prior inline loops). ponytail: input key is `Hashable` so callers can
    /// hand in either size-buckets (`UInt64`) or partial-hash buckets (`Data`).
    private static func hashedBuckets<K: Hashable, T>(
        _ buckets: [K: [T]],
        hash: (URL) -> Data?
    ) -> [Data: [T]] {
        var out: [Data: [T]] = [:]
        for (_, items) in buckets {
            for item in items {
                guard let urlHash = hash(URL(fileURLWithPath: pathFor(item))) else { continue }
                out[urlHash, default: []].append(item)
            }
        }
        return out
    }

    /// ponytail: only DiskNode flows through today; routed through one accessor so a
    /// future caller type means a single line change, not every hash helper.
    private static func pathFor<T>(_ item: T) -> String {
        (item as? DiskNode)?.path ?? ""
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