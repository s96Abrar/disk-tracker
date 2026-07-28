//
//  FSEventsMonitor.swift
//  DiskTracker
//
//  Phase 6: Real-time filesystem monitoring via FSEvents (CoreServices).
//  Reports changed paths so AppModel can refresh the affected subtree.
//

import Foundation
import CoreServices

/// Describes a filesystem event reported by FSEvents.
struct FSEventRecord: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let flags: FSEventStreamEventFlags   // raw UInt32
    let timestamp: Date

    private func has(_ flag: UInt32) -> Bool { (flags & flag) != 0 }

    var isDirty: Bool   { has(UInt32(kFSEventStreamEventFlagItemModified)) || has(UInt32(kFSEventStreamEventFlagItemCreated)) || has(UInt32(kFSEventStreamEventFlagItemRemoved)) }
    var isRemoved: Bool { has(UInt32(kFSEventStreamEventFlagItemRemoved)) }
    var isCreated: Bool { has(UInt32(kFSEventStreamEventFlagItemCreated)) || has(UInt32(kFSEventStreamEventFlagItemRenamed)) }
}

/// Wraps an FSEventStream for a single watched directory tree.
///
/// ponytail: one monitor per scan root. Callback-based FSEvents API scheduled
/// ceiling: callback scheduled. upgrade: event-based realtime.
/// on the main queue for simplicity. Main-thread callbacks keep model updates
/// race-free with SwiftUI.
final class FSEventsMonitor {

    private var stream: FSEventStreamRef?
    private let callback: @Sendable (FSEventRecord) -> Void

    init?(watching url: URL, callback: @escaping @Sendable (FSEventRecord) -> Void) {
        self.callback = callback
        guard start(watching: url) else { return nil }
    }

    deinit { stop() }

    // MARK: - Lifecycle

    private func start(watching url: URL) -> Bool {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [url.path] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, numEvents, eventPaths, eventFlags, _ in
                guard let info = info else { return }
                let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(info).takeUnretainedValue()
                let pathsArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
                let paths = (0..<CFArrayGetCount(pathsArray)).map { idx in
                    String(unsafeBitCast(CFArrayGetValueAtIndex(pathsArray, idx), to: NSString.self) as String)
                }
                for i in 0..<Int(numEvents) {
                    let record = FSEventRecord(
                        path: paths[i],
                        flags: eventFlags[i],
                        timestamp: Date()
                    )
                    monitor.callback(record)
                }
            },
            &context,
            pathsToWatch,
            UInt64(kFSEventStreamEventIdSinceNow),
            0.5,  // latency: 0.5s coalescing
            UInt32(kFSEventStreamCreateFlagNoDefer) | UInt32(kFSEventStreamCreateFlagFileEvents)
        ) else { return false }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        return true
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}