//
//  Models.swift
//  DiskTracker
//
//  The value types a scan produces, and the enums the UI selects with.
//
//  Split out of AppModel.swift, which had grown to 843 lines holding five
//  model types plus navigation, scanning, filtering, selection, batch
//  operations and export. The types here have no dependency on app state —
//  they are what a scan *is*, not what the app is doing with it.
//
//  `DuplicateGroup` in particular has to be visible before the @Observable
//  macro expands on AppModel, since the generated code references it.
//

import SwiftUI

/// The canonical scan state.
enum ScanState: Equatable, Sendable {
    case idle
    case scanning(progress: Double)
    case completed(totalSize: UInt64, fileCount: Int)
    case failed(error: String)

    var progress: Double {
        if case .scanning(let p) = self { return p }
        return 0.0
    }
}

/// File type used for colour-coding the visualisation.
enum FileKind: UInt8, CaseIterable, Sendable, Codable {
    case image = 0, video = 1, audio = 2, document = 3
    case archive = 4, application = 5, other = 6, directory = 7

    /// Singular, human-facing name for one item of this kind.
    var displayName: String {
        switch self {
        case .image:       return "Image"
        case .video:       return "Video"
        case .audio:       return "Audio"
        case .document:    return "Document"
        case .archive:     return "Archive"
        case .application: return "Application"
        case .directory:   return "Folder"
        case .other:       return "File"
        }
    }

    var iconName: String {
        switch self {
        case .image:       return "photo"
        case .video:       return "film"
        case .audio:       return "music.note"
        case .document:    return "doc"
        case .archive:     return "doc.zipper"
        case .application: return "app"
        case .directory:   return "folder"
        case .other:       return "doc.questionmark"
        }
    }
}

/// One node in the flat array returned by the Rust engine.
struct DiskNode: Identifiable, Equatable, Sendable, Hashable, Codable {
    let id = UUID()
    var recordIndex: Int
    var name: String
    var path: String
    var logicalSize: UInt64
    var physicalSize: UInt64
    var fileKind: FileKind
    var isSystemProtected: Bool
    var modTimeSecs: Int64
    var depth: UInt16
    var childCount: UInt32 = 0
    var children: [DiskNode]?

    static func == (lhs: DiskNode, rhs: DiskNode) -> Bool {
        lhs.recordIndex == rhs.recordIndex && lhs.path == rhs.path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(recordIndex)
        hasher.combine(path)
    }

    /// Total logical size of this node and all descendants (recursive).
    var totalLogicalSize: UInt64 {
        children?.reduce(logicalSize) { $0 + $1.totalLogicalSize } ?? logicalSize
    }

    /// Total physical size of this node and all descendants (recursive). Computed by
    /// `computeTotalPhysicalSizes` after the full tree is built.
    var totalPhysicalSize: UInt64 = 0

    /// Classify a file by its extension for colour-coding.
    static func detectFileKind(`extension`: String) -> FileKind {
        switch `extension`.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg", "bmp", "tiff": return .image
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv":                          return .video
        case "mp3", "wav", "aac", "flac", "m4a", "aiff":                        return .audio
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "xlsx", "pptx":       return .document
        case "zip", "tar", "gz", "bz2", "7z", "rar", "dmg", "pkg":              return .archive
        case "app", "dylib", "so", "exe":                                       return .application
        default:                                                                return .other
        }
    }
}

// Phase 5: DuplicateGroup at file scope (before @Observable class) for macro compatibility
// SwiftPM compiles Sources/Core/Engine/ before Sources/Core/Services/.
// The @Observable macro on AppModel generates code referencing DuplicateGroup.
// If DuplicateGroup is defined in DuplicateFinderService.swift (compiled later),
// macro expansion fails. Moving it here ensures it's in scope when macro runs.

/// A group of files with identical content (same full SHA-256).
struct DuplicateGroup: Identifiable, Sendable {
    let id = UUID()
    let hash: Data               // 32-byte SHA-256 digest
    let nodes: [DiskNode]
    let wastedBytes: UInt64

    /// Keep the file with the most recent modification time as the "original."
    var originalNode: DiskNode {
        nodes.max(by: { $0.modTimeSecs < $1.modTimeSecs }) ?? nodes[0]
    }

    var duplicateNodes: [DiskNode] {
        nodes.filter { $0.id != originalNode.id }
    }
}

/// Top-level navigation phase. Drives the root window content in
/// `DiskTrackerApp`. Transitions are explicit via `navigate(to:)` so
/// tests + the UI agree on the state machine.
enum AppPhase: Equatable, Sendable {
    case onboarding
    case dashboard
    case scanResults
}

/// One of the categories shown in the Scan Results sidebar.
/// Mirrors the mock's category list (Directories/Images/Videos/Documents/
/// Applications/Archives/Other).
enum ScanCategory: String, CaseIterable, Identifiable, Sendable {
    case directories = "Directories"
    case images = "Images"
    case videos = "Videos"
    case documents = "Documents"
    case applications = "Applications"
    case archives = "Archives"
    case other = "Other"

    var id: String { rawValue }

    /// SF Symbol for the sidebar row. These were Material Icons names carried
    /// over from the HTML mock, which render as blank rows on macOS.
    var icon: String {
        switch self {
        case .directories:   return "folder"
        case .images:        return "photo"
        case .videos:        return "film"
        case .documents:     return "doc.text"
        case .applications:  return "app"
        case .archives:      return "doc.zipper"
        case .other:         return "ellipsis.circle"
        }
    }

    /// Corresponding `FileKind`s this category aggregates.
    var fileKinds: [FileKind] {
        switch self {
        case .directories:   return [.directory]
        case .images:        return [.image]
        case .videos:        return [.video]
        case .documents:     return [.document, .audio] // docs + audio grouped
        case .applications:  return [.application]
        case .archives:      return [.archive]
        case .other:         return [.other]
        }
    }
}
