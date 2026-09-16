//
//  LaunchMetrics.swift
//  DiskTracker
//
//  Measures process exec → first frame.
//
//  `open` to process-start is easy to time from a shell and says almost
//  nothing: it stops before dyld, before SwiftUI builds a scene, and before
//  anything is on screen. The number a user experiences is the one that ends
//  when the window appears, and only the app can observe that.
//

import Foundation
import os

private let log = Logger(subsystem: "com.disktracker", category: "launch")

enum LaunchMetrics {

    /// Seconds from `execve` to now, or nil when the kernel won't say.
    ///
    /// Read from `kinfo_proc`, not from a timestamp taken in `main` — by the
    /// time any Swift runs, dyld has already loaded every framework, which on
    /// a cold launch is most of the cost.
    static func secondsSinceExec() -> TimeInterval? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        let ok = mib.withUnsafeMutableBufferPointer { pointer -> Bool in
            sysctl(pointer.baseAddress, u_int(pointer.count), &info, &size, nil, 0) == 0
        }
        guard ok else { return nil }

        let start = info.kp_proc.p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return Date().timeIntervalSince1970 - started
    }

    /// Logs the launch duration the first time a frame is drawn.
    ///
    /// Guarded because SwiftUI calls `onAppear` again on later navigation, and
    /// a second reading would be a much larger, meaningless number.
    ///
    /// `@MainActor` rather than a plain static: Swift 6 strict concurrency
    /// rejects mutable global state, and the only caller is a view's `onAppear`,
    /// which is already on the main actor.
    @MainActor private static var reported = false

    @MainActor
    static func reportFirstFrame() {
        guard !reported else { return }
        reported = true

        guard let seconds = secondsSinceExec() else {
            log.notice("first frame, but sysctl gave no process start time")
            return
        }
        // `notice`, not `info`: info-level messages live in a memory buffer
        // that `log show` skips unless asked, so ./measure-launch saw nothing.
        // Notice is persisted. Marked public so the value itself is readable
        // rather than redacted as <private>.
        log.notice("first frame after \(seconds, format: .fixed(precision: 3), privacy: .public) s")
    }
}
