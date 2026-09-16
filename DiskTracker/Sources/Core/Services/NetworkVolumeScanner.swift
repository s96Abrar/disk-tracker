//
//  NetworkVolumeScanner.swift
//  DiskTracker
//
//  Phase 7: Network volume scanning (SMB/AFP/NFS).
//
//  NOT BUILT IN v0.1 — gated behind `DISKTRACKER_V05`.
//
//  No build configuration defines that condition, so this file compiles to
//  nothing today. It is kept rather than deleted because it works and is
//  tested; it is the starting point for the phase named above, tracked in
//  `documents/5_FUTURE_TARGETS.md` §3.
//
//  To build it, add to the DiskTracker target's build settings:
//      SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DISKTRACKER_V05
//
//  `./build-disk-tracker --v05` does exactly that, and is run in CI so this
//  code cannot rot into something that no longer compiles.
//

#if DISKTRACKER_V05

import Foundation

/// Represents a discovered network volume.
struct NetworkVolume: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let type: VolumeType
    let host: String

    enum VolumeType: String, Sendable, Equatable {
        case smb = "SMB"
        case afp = "AFP"
        case nfs = "NFS"
        case unknown = "Unknown"
    }
}

/// Discovers and scans network volumes (SMB/AFP/NFS).
enum NetworkVolumeScanner {

    /// Discover available network volumes.
    static func discoverVolumes() async -> [NetworkVolume] {
        var volumes: [NetworkVolume] = []

        volumes.append(contentsOf: await discoverSMBShares())
        volumes.append(contentsOf: discoverNFSMounts())

        return volumes
    }

    /// Discover SMB shares from /Volumes.
    private static func discoverSMBShares() async -> [NetworkVolume] {
        var volumes: [NetworkVolume] = []

        let volumesURL = URL(fileURLWithPath: "/Volumes")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: volumesURL,
            includingPropertiesForKeys: [.isVolumeKey, .volumeLocalizedNameKey]
        ) else {
            return volumes
        }

        for url in contents {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isVolumeKey]),
                  let isVolume = resourceValues.isVolume, isVolume,
                  let name = resourceValues.volumeLocalizedName else {
                continue
            }

            let shareType = testDetectShareType(name: name, url: url)
            if shareType != .unknown {
                let host = testExtractHost(from: url.path)
                volumes.append(NetworkVolume(
                    url: url,
                    name: name,
                    type: shareType,
                    host: host
                ))
            }
        }

        return volumes
    }

    /// Discover NFS mounts.
    private static func discoverNFSMounts() -> [NetworkVolume] {
        var volumes: [NetworkVolume] = []

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        process.arguments = ["-t", "nfs"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return volumes
            }

            for line in output.split(separator: "\n") where line.contains(" type nfs ") {
                let parts = line.split(separator: " ")
                guard parts.count >= 4 else { continue }
                let mountPoint = String(parts[3])
                let url = URL(fileURLWithPath: mountPoint)
                let hostPath = String(parts[2])
                let host = hostPath.contains(":") ? String(hostPath.split(separator: ":")[0]) : hostPath

                volumes.append(NetworkVolume(
                    url: url,
                    name: url.lastPathComponent,
                    type: .nfs,
                    host: host
                ))
            }
        } catch {
            // NFS not available
        }

        return volumes
    }

    /// Classify a `/Volumes/<name>` mount by name + URL.
    /// ponytail: heuristic, not a NetBIOS-style probe. Fast, good enough for UI.
    static func testDetectShareType(name: String, url: URL) -> NetworkVolume.VolumeType {
        let lowercased = name.lowercased()

        if lowercased.contains("smb") || lowercased.contains("cifs") ||
           url.path.hasPrefix("/Volumes/smb") || url.path.hasPrefix("/Volumes/SMB") {
            return .smb
        }
        if lowercased.contains("afp") || url.path.hasPrefix("/Volumes/afp") {
            return .afp
        }
        if lowercased.contains("nfs") {
            return .nfs
        }
        if url.path.contains("Network") || name.hasPrefix("//") {
            return .smb
        }

        return .unknown
    }

    /// Extract the host portion of a `/Volumes/<host>/...` or UNC `//<host>/...` path.
    static func testExtractHost(from path: String) -> String {
        if path.hasPrefix("/Volumes/") {
            let relative = String(path.dropFirst("/Volumes/".count))
            if let slashIndex = relative.firstIndex(of: "/") {
                return String(relative[..<slashIndex])
            }
            return relative
        }
        if path.hasPrefix("//") {
            let relative = String(path.dropFirst(2))
            if let slashIndex = relative.firstIndex(of: "/") {
                return String(relative[..<slashIndex])
            }
            return relative
        }
        return "Unknown"
    }

    /// Scan a network volume for disk usage.
    static func scanVolume(_ volume: NetworkVolume) -> NetworkVolumeScanResult? {
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: volume.url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var totalSize: UInt64 = 0
        var fileCount = 0

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDir = resourceValues.isDirectory, !isDir else {
                continue
            }

            totalSize += UInt64(resourceValues.fileSize ?? 0)
            fileCount += 1

            if fileCount > 100_000 { break }
        }

        return NetworkVolumeScanResult(
            volume: volume,
            totalSize: totalSize,
            fileCount: fileCount
        )
    }
}

/// Result of scanning a network volume.
struct NetworkVolumeScanResult {
    let volume: NetworkVolume
    let totalSize: UInt64
    let fileCount: Int
}

#endif  // DISKTRACKER_V05
