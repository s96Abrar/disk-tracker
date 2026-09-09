//
//  DirectoryScannerBridge.swift
//  DiskTracker
//
//  Bridge to the Rust traversal engine via NSTask subprocess.
//  Parses JSON output from the compiled Rust CLI, then builds a
//  DiskNode tree directly (since Rust decodes names to strings).
//

import Foundation
import os

/// `os.Logger` already timestamps, tags by subsystem/category, and captures
/// source location — the hand-rolled wrapper that used to live here only
/// re-formatted that into a string.
private let log = Logger(subsystem: "com.disktracker", category: "bridge")

// MARK: - ScanConfig

/// Scan configuration.
struct ScanConfig {
    var excludeSystemPaths: Bool = true
    var excludeHiddenFiles: Bool = false
    var followSymlinks: Bool = false
    var maxDepth: UInt32 = .max
}

/// Byte sink for draining a pipe from another thread.
private final class DataSink: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    var value: Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}

/// High-level scanner bridge. Calls Rust CLI as subprocess.
final class DirectoryScannerBridge: @unchecked Sendable {
    private let rustBinary: URL

    // JSON record type from Rust CLI
    private struct RRecord: Codable {
        var node_id: UInt64
        var parent_id: UInt64
        var name: String
        var name_offset: UInt32
        var name_len: UInt32
        var logical_size: UInt64
        var physical_size: UInt64
        var node_type: UInt8
        var is_system_protected: Bool
        var mod_time_secs: Int64
        var depth: UInt16
        var child_count: UInt32
        var first_child_id: UInt64
    }

    private struct RScanOutput: Codable {
        var records: [RRecord]
        var string_table: [UInt8]
    }

    init() {
        var bundlePath: URL?
        if let resURL = Bundle.main.resourceURL {
            bundlePath = resURL.appendingPathComponent("disk-tracker-engine")
        }
        let candidates = [bundlePath].compactMap { $0 }
        self.rustBinary = candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) } ?? candidates[0]
        log.info("binary \(self.rustBinary.path, privacy: .public)")
    }

    /// Prefix of a progress line on the engine's stderr: `progress <count>`.
    private static let progressPrefix = "progress "

    /// The running engine process, so `cancel()` can kill it.
    private let taskLock = NSLock()
    private var currentTask: Process?

    /// Terminate the running scan, if any. Safe to call from any thread; the
    /// in-flight `scan(path:config:onProgress:)` then returns nil.
    func cancel() {
        taskLock.lock()
        let task = currentTask
        taskLock.unlock()
        task?.terminate()
    }

    /// Scan a path synchronously. Call from a background queue.
    /// `onProgress` fires from a background thread with the running count of
    /// entries the engine has seen.
    func scan(path: String, config: ScanConfig, onProgress: (@Sendable (Int) -> Void)? = nil) -> DiskNode? {
        log.info("scanning \(path, privacy: .public)")

        var args = ["scan", path, "--format=json"]
        if config.excludeHiddenFiles { args.append("--exclude-hidden") }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let task = Process()
        task.executableURL = rustBinary
        task.arguments = args
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            log.error("task failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        taskLock.lock()
        currentTask = task
        taskLock.unlock()
        defer {
            taskLock.lock()
            currentTask = nil
            taskLock.unlock()
        }

        // Drain both pipes *before* waiting on the child. A pipe buffer holds
        // 64KB; the engine emits far more than that for any real directory, so
        // it blocks in write() while we block in waitUntilExit() — a permanent
        // deadlock. Reading first is what makes the child able to finish.
        // stderr carries `progress <n>` lines during the walk, so it is read
        // line by line rather than in one shot at EOF.
        let errSink = DataSink()
        let errDrained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            let handle = errorPipe.fileHandleForReading
            var pending = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = Data(pending[pending.startIndex..<newline])
                    pending = Data(pending[(newline + 1)...])
                    if let scanned = Self.parseProgress(line) {
                        onProgress?(scanned)
                    } else {
                        errSink.append(line)  // keep real diagnostics for the failure path
                    }
                }
            }
            errSink.append(pending)
            errDrained.signal()
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        errDrained.wait()

        guard !data.isEmpty else {
            let errStr = String(data: errSink.value, encoding: .utf8) ?? ""
            log.error("stderr: \(errStr, privacy: .public)")
            return nil
        }

        // Parse JSON from Rust CLI
        let decoder = JSONDecoder()
        guard let output = try? decoder.decode(RScanOutput.self, from: data) else {
            log.error("JSON decode failed")
            return nil
        }

        // Build DiskNode tree from flat records.
        // Never interpolate `output` or the tree into a log line: interpolation
        // is eager, so it builds a multi-gigabyte string for a real scan.
        log.info("decoded \(output.records.count) records")
        guard var root = buildTree(records: output.records, stringTable: Data(output.string_table)) else {
            return nil
        }
        fixFullPaths(node: &root, parentPath: "")
        computeTotalPhysicalSizes(node: &root)
        return root
    }

    /// Parse a `progress <count>` line from the engine's stderr.
    /// Returns nil for anything else, which is treated as a diagnostic.
    static func parseProgress(_ line: Data) -> Int? {
        guard let text = String(data: line, encoding: .utf8),
              text.hasPrefix(progressPrefix) else { return nil }
        return Int(text.dropFirst(progressPrefix.count).trimmingCharacters(in: .whitespaces))
    }

    /// Recursively compute full paths for all nodes in the tree.
    private func fixFullPaths(node: inout DiskNode, parentPath: String) {
        node.path = parentPath.isEmpty ? node.name : "\(parentPath)/\(node.name)"
        if var children = node.children {
            for i in children.indices {
                fixFullPaths(node: &children[i], parentPath: node.path)
            }
            node.children = children
        }
    }

    /// Recursively compute totalPhysicalSize for each directory as sum of all descendant physical sizes.
    /// File nodes get their own physicalSize as total.
    private func computeTotalPhysicalSizes(node: inout DiskNode) {
        if var children = node.children, !children.isEmpty {
            for i in children.indices {
                computeTotalPhysicalSizes(node: &children[i])
            }
            let sum = children.reduce(UInt64(0)) { $0 + $1.totalPhysicalSize }
            node.totalPhysicalSize = sum
            node.children = children
        } else {
            node.totalPhysicalSize = node.physicalSize
        }
    }

    /// Sort children recursively: directories first, then files, both alphabetically.
    private func sortChildren(_ node: inout DiskNode) {
        guard var children = node.children, !children.isEmpty else { return }
        children.sort { a, b in
            if a.fileKind == .directory && b.fileKind != .directory {
                return true
            }
            if a.fileKind != .directory && b.fileKind == .directory {
                return false
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        for i in children.indices {
            sortChildren(&children[i])
        }
        node.children = children
    }

    /// Build DiskTree hierarchy from flat record list.
    private func buildTree(records: [RRecord], stringTable: Data) -> DiskNode? {
        guard !records.isEmpty else { return nil }

        // Group child record indices by their parent's node_id.
        // parent_id is a node_id, not a record index, so we look it up via nodeIdToIndex.
        var nodeIdToIndex: [UInt64: Int] = [:]
        nodeIdToIndex.reserveCapacity(records.count)
        var childrenOfParent: [UInt64: [Int]] = [:]
        childrenOfParent.reserveCapacity(records.count)
        for (i, r) in records.enumerated() {
            nodeIdToIndex[r.node_id] = i
            childrenOfParent[r.parent_id, default: []].append(i)
        }

        // Assemble the tree bottom-up from the root. Because DiskNode is a value
        // type, we must fully build each child — including all of its descendants —
        // *before* inserting it into its parent's children array. Appending a node
        // copies it at that instant, so wiring a node into its parent first and
        // attaching grandchildren later leaves the parent holding a stale,
        // childless copy — which is what previously dropped nested descendants
        // from folder size totals while leaving child_count (sourced directly from
        // Rust) correct.
        func assemble(_ index: Int) -> DiskNode {
            let r = records[index]
            let kind: FileKind
            switch r.node_type {
            case 1: kind = .directory
            default:
                let ext = (r.name as NSString).pathExtension
                kind = DiskNode.detectFileKind(extension: ext)
            }
            let childIndices = childrenOfParent[r.node_id] ?? []
            let children = childIndices.map { assemble($0) }

            return DiskNode(
                recordIndex: index,
                name: r.name,
                path: r.name,
                logicalSize: r.logical_size,
                physicalSize: r.physical_size,
                fileKind: kind,
                isSystemProtected: r.is_system_protected,
                modTimeSecs: r.mod_time_secs,
                depth: r.depth,
                childCount: r.child_count,
                children: children,
                totalPhysicalSize: r.physical_size
            )
        }

        var rootNode = assemble(0)

        // Sort children recursively: directories first, then files, both alphabetically.
        sortChildren(&rootNode)

        return rootNode
    }
}
