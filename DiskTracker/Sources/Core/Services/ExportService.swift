//
//  ExportService.swift
//  DiskTracker
//
//  Phase 5: JSON + CSV export of scan results.
//

import Foundation

enum ExportService {

    // MARK: - Top-level entries

    static func exportJSON(root: DiskNode) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let node = SerializableNode.from(root, formatter: Self.defaultDateFormatter)
        guard let data = try? encoder.encode(node),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func exportCSV(root: DiskNode) -> String {
        var lines: [String] = ["Path,Name,PhysicalSize,LogicalSize,Kind,ModDate"]
        appendCSV(from: root, into: &lines, formatter: Self.defaultDateFormatter)
        return lines.joined(separator: "\n")
    }

    // MARK: - Pure helpers (test seams)

    /// ponytail: kept as a hook for tests that want a stable date format. The default
    /// formatter is non-deterministic in earlier revisions; tests should pass their own.
    static func exportCSV(root: DiskNode, formatter: DateFormatter) -> String {
        var lines: [String] = ["Path,Name,PhysicalSize,LogicalSize,Kind,ModDate"]
        appendCSV(from: root, into: &lines, formatter: formatter)
        return lines.joined(separator: "\n")
    }

    static func exportJSON(root: DiskNode, formatter: DateFormatter) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let node = SerializableNode.from(root, formatter: formatter)
        guard let data = try? encoder.encode(node),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// One CSV row for `node`, or nil if `node` is a directory. ponytail: pure helper used
    /// by appendCSV; tests pin this so row format doesn't drift.
    static func csvRow(for node: DiskNode, formatter: DateFormatter) -> String? {
        guard node.fileKind != .directory else { return nil }
        let row = [
            csvEscape(node.path),
            csvEscape(node.name),
            "\(node.physicalSize)",
            "\(node.logicalSize)",
            csvEscape(fileKindLabel(node.fileKind)),
            formatter.string(from: Date(timeIntervalSince1970: TimeInterval(node.modTimeSecs))),
        ].joined(separator: ",")
        return row
    }

    // MARK: - Internal

    private static let defaultDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static func appendCSV(from node: DiskNode, into lines: inout [String], formatter: DateFormatter) {
        if let row = csvRow(for: node, formatter: formatter) {
            lines.append(row)
        }
        node.children?.forEach { appendCSV(from: $0, into: &lines, formatter: formatter) }
    }

    static func fileKindLabel(_ kind: FileKind) -> String {
        switch kind {
        case .image:       return "Image"
        case .video:       return "Video"
        case .audio:       return "Audio"
        case .document:    return "Document"
        case .archive:     return "Archive"
        case .application: return "Application"
        case .directory:   return "Directory"
        case .other:       return "Other"
        }
    }

    static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }

    struct SerializableNode: Codable {
        let name: String
        let path: String
        let physicalSize: UInt64
        let logicalSize: UInt64
        let kind: String
        let modDate: String
        let children: [SerializableNode]?

        static func from(_ node: DiskNode, formatter: DateFormatter) -> SerializableNode {
            SerializableNode(
                name: node.name,
                path: node.path,
                physicalSize: node.physicalSize,
                logicalSize: node.logicalSize,
                kind: fileKindLabel(node.fileKind),
                modDate: formatter.string(from: Date(timeIntervalSince1970: TimeInterval(node.modTimeSecs))),
                children: node.children?.map { from($0, formatter: formatter) }
            )
        }
    }
}