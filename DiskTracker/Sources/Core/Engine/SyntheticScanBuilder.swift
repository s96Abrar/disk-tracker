//
//  SyntheticScanBuilder.swift
//  DiskTracker
//
//  ponytail: Stand-in scan tree until Rust FFI (DirectoryScannerBridge) is wired.
//  Phase 4 needs a queryable DiskNode tree to exercise smart filters + free space.
//  Delete once real FFI scans produce rootNode in AppModel.startScan.
//

import Foundation

enum SyntheticScanBuilder {
    /// Build a small deterministic tree rooted at `path`.
    static func makeTree(path: String) -> DiskNode {
        // Times relative to now to exercise old-file filter (6-month default threshold).
        let now = Int64(Date().timeIntervalSince1970)
        let day: Int64 = 86_400
        let month: Int64 = day * 30

        let apps = leaf(name: "Keynote.app", ext: "app", size: 1_900_000_000,
                        modTime: now - 2 * day, depth: 2)
        let oldDmg = leaf(name: "old-installer.dmg", ext: "dmg", size: 4_200_000_000,
                         modTime: now - 10 * month, depth: 2)
        let archive = leaf(name: "2024-archive.zip", ext: "zip", size: 2_500_000_000,
                           modTime: now - 1 * month, depth: 2)

        let img1 = leaf(name: "photo.heic", ext: "heic", size: 3_200_000,
                        modTime: now - 5 * day, depth: 3)
        let img2 = leaf(name: "render.png", ext: "png", size: 12_800_000,
                        modTime: now - 15 * day, depth: 3)
        let emptySub = dir(name: "EmptyReuse", children: [], modTime: now - 40 * day, depth: 3)
        let pictures = dir(name: "Pictures", children: [img1, img2, emptySub],
                           modTime: now - 6 * day, depth: 2)

        let docs = dir(name: "Documents", children: [
            leaf(name: "notes.txt", ext: "txt", size: 4_200, modTime: now - 8 * month, depth: 3),
            leaf(name: "report.pdf", ext: "pdf", size: 8_400_000, modTime: now - 20 * day, depth: 3),
        ], modTime: now - 3 * day, depth: 2)

        let homeChildren = [apps, oldDmg, archive, pictures, docs]
        let home = dir(name: (path as NSString).lastPathComponent, children: homeChildren,
                       modTime: now - 1 * day, depth: 1)

        // Root represents the scanned path itself.
        return dir(name: path, children: [home], modTime: now, depth: 0)
    }

    // MARK: - Helpers

    private static func dir(name: String, children: [DiskNode], modTime: Int64, depth: UInt16) -> DiskNode {
        let totalSize = children.reduce(UInt64(0)) { $0 + $1.totalPhysicalSize }
        return DiskNode(recordIndex: 0, name: name, path: name,
                        logicalSize: totalSize, physicalSize: 0,
                        fileKind: .directory, isSystemProtected: false,
                        modTimeSecs: modTime, depth: depth,
                        childCount: UInt32(children.count), children: children,
                        totalPhysicalSize: totalSize)
    }

    private static func leaf(name: String, ext: String, size: UInt64,
                            modTime: Int64, depth: UInt16) -> DiskNode {
        let kind = classify(ext: ext)
        return DiskNode(recordIndex: 0, name: name, path: name,
                        logicalSize: size, physicalSize: size,
                        fileKind: kind, isSystemProtected: false,
                        modTimeSecs: modTime, depth: depth,
                        childCount: 0, children: nil,
                        totalPhysicalSize: size)
    }

    private static func classify(ext: String) -> FileKind {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg", "bmp", "tiff": return .image
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv":                          return .video
        case "mp3", "wav", "aac", "flac", "m4a", "aiff":                       return .audio
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "xlsx", "pptx":      return .document
        case "zip", "tar", "gz", "bz2", "7z", "rar", "dmg", "pkg":             return .archive
        case "app", "dylib", "so", "exe":                                      return .application
        default:                                                                return .other
        }
    }
}
