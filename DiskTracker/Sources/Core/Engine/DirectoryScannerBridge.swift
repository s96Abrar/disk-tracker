//
//  DirectoryScannerBridge.swift
//  DiskTracker
//
//  Swift FFI bridge to the Rust traversal engine.
//  TODO: Wire to actual Rust dylib once cargo is available.
//

import Foundation
import os.log

/// C-compatible scan result returned by scanner_get_result().
struct CScanResult {
    var buffer: UnsafeMutablePointer<UInt8>?
    var bufferLen: UInt64
    var recordCount: UInt64
    var stringTableOffset: UInt64
}

/// Scan configuration mirrored from the Rust side.
struct ScanConfig {
    var excludeSystemPaths: Bool = true
    var excludeHiddenFiles: Bool = false
    var followSymlinks: Bool = false
    var maxDepth: UInt32 = .max
}

/// Bridge class that manages the Rust scanner via C FFI.
/// Currently a stub — FFI wiring deferred until Rust dylib is built.
final class DirectoryScannerBridge: @unchecked Sendable {
    private let log = OSLog(subsystem: "com.disktracker.scanner", category: "bridge")
    
    init() {
        os_log("DirectoryScannerBridge: Rust FFI not yet wired (TODO)", log: log, type: .info)
    }

    func startScan(path: String, config: ScanConfig, onProgress: @escaping (Double) -> Void) {
        os_log("Bridge.startScan called with path: %{public}@", log: log, type: .info, path)
        // TODO: Call Rust scanner_* FFI functions once dylib is available
        // The Rust FFI surface (from lib.rs) will be:
        //   scanner_create() -> OpaquePointer
        //   scanner_start(handle, path, config, onProgress)
        //   scanner_get_result(handle) -> CScanResult
        //   scanner_free_result(result)
    }

    func cancel() {
        os_log("Bridge.cancel called", log: log, type: .info)
        // TODO: scanner_cancel(handle)
    }

    var isRunning: Bool { false }

    func getResult() -> CScanResult? {
        os_log("Bridge.getResult called", log: log, type: .info)
        // TODO: Return actual result from Rust
        return nil
    }

    func freeResult(_ result: UnsafeMutablePointer<CScanResult>?) {
        // TODO: scanner_free_result(result)
    }
}

extension CScanResult {
    func records<T>() -> UnsafeBufferPointer<T>? { nil }
    func stringTable() -> UnsafeBufferPointer<UInt8>? { nil }
}
