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

private struct Logger {
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

private let log = Logger(category: "bridge")

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
        return buildTree(records: output.records, stringTable: Data(output.string_table))
    }

    /// Build DiskNode hierarchy from flat record list.
    private func buildTree(records: [RRecord], stringTable: Data) -> DiskNode? {
        guard !records.isEmpty else { return nil }

        var nodes: [DiskNode] = []
        nodes.reserveCapacity(records.count)

        // Pass 1: create all nodes from records
        for (i, r) in records.enumerated() {
            let kind: FileKind
            switch r.node_type {
            case 1: kind = .directory
            default: kind = .other
            }
            let node = DiskNode(
                recordIndex: i,
                name: r.name,
                path: r.name,
                logicalSize: r.logical_size,
                physicalSize: r.physical_size,
                fileKind: kind,
                isSystemProtected: r.is_system_protected,
                modTimeSecs: r.mod_time_secs,
                depth: r.depth,
                children: nil
            )
            nodes.append(node)
        }

        // Pass 2: wire parent-child relationships using parent_id
        // Records are ordered: parents before children (BFS)
        for (i, r) in records.enumerated() {
            if r.child_count > 0 && r.first_child_id > 0 {
                let firstIdx = Int(r.first_child_id) - 1
                let lastIdx = firstIdx + Int(r.child_count)
                guard firstIdx >= 0, lastIdx <= nodes.count else { continue }
                nodes[i].children = Array(nodes[firstIdx..<lastIdx])
            }
        }

        return nodes.first
    }

    func cancel() {}
    var isRunning: Bool { false }
}
