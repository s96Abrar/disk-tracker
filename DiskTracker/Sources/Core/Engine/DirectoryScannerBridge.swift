//
//  DirectoryScannerBridge.swift
//  DiskTracker
//
//  Bridge to the Rust traversal engine via NSTask subprocess.
//  Parses JSON output from the compiled Rust CLI, then builds a
//  DiskNode tree directly (since Rust decodes names to strings).
//

import Foundation
import os.log

// MARK: - Logger

private enum LogLevel: String {
    case debug   = "DEBUG"
    case info    = "INFO"
    case warning = "WARNING"
    case error   = "ERROR"
    case fault   = "FAULT"

    var osType: OSLogType {
        switch self {
        case .debug:   return .debug
        case .info:    return .info
        case .warning: return .default
        case .error:   return .error
        case .fault:   return .fault
        }
    }
}

struct Logger {
    private let oslog: OSLog
    private let category: String

    init(category: String) {
        self.oslog = OSLog(subsystem: "com.disktracker", category: category)
        self.category = category
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    private func log(_ level: LogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        let entry = "[\(timestamp())] [\(level.rawValue)] [\(category)] \(filename):\(line) \(function) — \(message)"
        os_log("%{public}@", log: oslog, type: level.osType, entry)
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) { log(.debug, message, file: file, function: function, line: line) }
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line)  { log(.info, message, file: file, function: function, line: line) }
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) { log(.warning, message, file: file, function: function, line: line) }
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) { log(.error, message, file: file, function: function, line: line) }
    func fault(_ message: String, file: String = #file, function: String = #function, line: Int = #line) { log(.fault, message, file: file, function: function, line: line) }
}

let log = Logger(category: "bridge")

// MARK: - ScanConfig

/// Scan configuration.
struct ScanConfig {
    var excludeSystemPaths: Bool = true
    var excludeHiddenFiles: Bool = false
    var followSymlinks: Bool = false
    var maxDepth: UInt32 = .max
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
        log.info("binary \(rustBinary.path)")
    }

    /// Scan a path synchronously. Call from a background queue.
    func scan(path: String, config: ScanConfig) -> DiskNode? {
        log.info("scanning \(path)")

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
            task.waitUntilExit()
        } catch {
            log.error("task failed: \(error.localizedDescription)")
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            log.error("stderr: \(errStr)")
            return nil
        }

        // Parse JSON from Rust CLI
        let decoder = JSONDecoder()
        guard let output = try? decoder.decode(RScanOutput.self, from: data) else {
            log.error("JSON decode failed")
            return nil
        }

        // Build DiskNode tree from flat records
        log.debug("Output \(output)")
        guard var root = buildTree(records: output.records, stringTable: Data(output.string_table)) else {
            return nil
        }
        fixFullPaths(node: &root, parentPath: "")
        computeTotalPhysicalSizes(node: &root)
        return root
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
        log.debug("RootNode: \(String(describing: rootNode))")

        return rootNode
    }

    func cancel() {}
    var isRunning: Bool { false }
}
