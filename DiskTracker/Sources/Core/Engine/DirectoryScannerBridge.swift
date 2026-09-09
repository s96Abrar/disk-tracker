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

        var args = ["scan", path]
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

        // Never interpolate the buffer or the tree into a log line:
        // interpolation is eager, so it builds a multi-gigabyte string for a
        // real scan.
        guard let buffer = ScanBuffer(data) else {
            log.error("engine produced an unreadable scan buffer")
            return nil
        }
        log.info("decoded \(buffer.recordCount) records")
        return buildTree(buffer)
    }

    /// Parse a `progress <count>` line from the engine's stderr.
    /// Returns nil for anything else, which is treated as a diagnostic.
    static func parseProgress(_ line: Data) -> Int? {
        guard let text = String(data: line, encoding: .utf8),
              text.hasPrefix(progressPrefix) else { return nil }
        return Int(text.dropFirst(progressPrefix.count).trimmingCharacters(in: .whitespaces))
    }

    /// Build the `DiskNode` hierarchy from the flat record buffer.
    ///
    /// One pass. Paths, recursive physical totals and child ordering used to be
    /// three more full walks over the finished tree; they are all derivable
    /// during assembly, and a walk of a million-node tree is not free.
    func buildTree(_ buffer: ScanBuffer) -> DiskNode? {
        guard buffer.recordCount > 0 else { return nil }

        // `parent_id` is a node_id, not an array index, so children are grouped
        // by their parent's node_id.
        var childIndices: [UInt64: [Int]] = [:]
        childIndices.reserveCapacity(buffer.recordCount)
        for i in 0..<buffer.recordCount {
            childIndices[buffer.parentID(at: i), default: []].append(i)
        }

        // DiskNode is a value type, so a child must be complete before it is
        // appended — appending copies. Attaching grandchildren afterwards would
        // leave the parent holding a stale, childless copy, which is what used
        // to drop nested descendants from folder totals.
        func assemble(_ index: Int, parentPath: String) -> DiskNode {
            let name = buffer.name(at: index)
            let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"

            let nodeType = buffer.nodeType(at: index)
            let kind: FileKind = nodeType == 1
                ? .directory
                : DiskNode.detectFileKind(extension: (name as NSString).pathExtension)

            var children = (childIndices[buffer.nodeID(at: index)] ?? [])
                .map { assemble($0, parentPath: path) }
            // Directories first, then files, each alphabetically.
            children.sort { a, b in
                if (a.fileKind == .directory) != (b.fileKind == .directory) {
                    return a.fileKind == .directory
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }

            let physical = buffer.physicalSize(at: index)
            let total = children.isEmpty
                ? physical
                : children.reduce(UInt64(0)) { $0 + $1.totalPhysicalSize }

            return DiskNode(
                recordIndex: index,
                name: name,
                path: path,
                logicalSize: buffer.logicalSize(at: index),
                physicalSize: physical,
                fileKind: kind,
                isSystemProtected: buffer.isSystemProtected(at: index),
                modTimeSecs: buffer.modTimeSecs(at: index),
                depth: buffer.depth(at: index),
                childCount: buffer.childCount(at: index),
                children: children,
                totalPhysicalSize: total
            )
        }

        return assemble(0, parentPath: "")
    }
}
