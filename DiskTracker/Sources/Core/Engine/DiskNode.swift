//
//  DiskNode.swift
//  DiskTracker
//
//  Builds the DiskNode hierarchy from the flat FFI buffer.
//

import Foundation

/// Node type as stored by the Rust engine (matches NodeType enum).
/// 0 = File, 1 = Directory, 2 = Symlink, 3 = Package
enum DiskNodeType: UInt8 {
    case file = 0
    case directory = 1
    case symlink = 2
    case package = 3
}

/// One record in the flat FFI buffer.  Must match the Rust FileRecord layout.
/// Size: 64 bytes (C repr)
struct FileRecord {
    var nodeId: UInt64
    var parentId: UInt64
    var nameOffset: UInt32
    var nameLen: UInt32
    var logicalSize: UInt64
    var physicalSize: UInt64
    var nodeType: UInt8
    var isSystemProtected: Bool
    var modTimeSecs: Int64
    var depth: UInt16
    var childCount: UInt32
    var firstChildId: UInt64
    var padding: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
}

/// Converts the raw FFI buffer into a hierarchy of DiskNode.
/// 
/// The FFI buffer layout:
/// [ FileRecord × N ][ String table bytes (NUL-terminated) ]
/// 
/// node_id / parent_id / first_child_id are 1-based indices into the record array.
/// A parent with child_count > 0 stores first_child_id = index of first child,
/// with subsequent children stored at consecutive indices.
struct DiskNodeBuilder {
    
    /// Build a tree of DiskNode from the raw buffers.
    /// Returns (rootNode, allNodes) on success.
    static func build(
        records: UnsafeBufferPointer<FileRecord>,
        strings: UnsafeBufferPointer<UInt8>
    ) -> (root: DiskNode, all: [DiskNode])? {
        guard !records.isEmpty else { return nil }
        
        var nodes: [DiskNode] = []
        nodes.reserveCapacity(records.count)
        
        // Pass 1: create all nodes without parent links
        for (i, rec) in records.enumerated() {
            let name = readString(from: strings, offset: Int(rec.nameOffset), length: Int(rec.nameLen))
            let node = DiskNode(
                recordIndex: i,
                name: name,
                path: "",  // filled in pass 2
                logicalSize: rec.logicalSize,
                physicalSize: rec.physicalSize,
                fileKind: classifyFile(name: name, type: rec.nodeType),
                isSystemProtected: rec.isSystemProtected,
                modTimeSecs: rec.modTimeSecs,
                depth: rec.depth,
                childCount: rec.childCount,
                children: nil,
                totalPhysicalSize: rec.physicalSize
            )
            nodes.append(node)
        }
        
        // Pass 2: wire up children
        for (i, rec) in records.enumerated() {
            if rec.childCount > 0 && rec.firstChildId > 0 {
                let firstIdx = Int(rec.firstChildId) - 1
                let lastIdx = firstIdx + Int(rec.childCount)
                guard firstIdx >= 0, lastIdx <= nodes.count else { continue }
                nodes[i].children = Array(nodes[firstIdx..<lastIdx])
            }
        }
        
        return (nodes[0], nodes)
    }
    
    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------
    
    private static func readString(
        from buffer: UnsafeBufferPointer<UInt8>,
        offset: Int,
        length: Int
    ) -> String {
        guard offset >= 0, offset < buffer.count else { return "" }
        let start = buffer.baseAddress!.advanced(by: offset)
        let end = min(start.advanced(by: length), buffer.baseAddress!.advanced(by: buffer.count))
        return String(cString: start)
    }
    
    /// Classify a file by extension for colour-coding.
    private static func classifyFile(name: String, type: UInt8) -> FileKind {
        if type == DiskNodeType.directory.rawValue { return .directory }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg", "bmp", "tiff":
            return .image
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv":
            return .video
        case "mp3", "wav", "aac", "flac", "m4a", "aiff":
            return .audio
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "xlsx", "pptx":
            return .document
        case "zip", "tar", "gz", "bz2", "7z", "rar", "dmg", "pkg":
            return .archive
        case "app", "dylib", "so", "exe":
            return .application
        default:
            return .other
        }
    }
}
